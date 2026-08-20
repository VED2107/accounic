-- =============================================================================
-- 02_rls_isolation.sql — context.md §3, §24, §33
--
-- Proves tenant isolation at the database layer by actually becoming each user:
--   set role authenticated + request.jwt.claims  ==  exactly what PostgREST does
--   for an anon-key request carrying a user's JWT.
--
-- If any of these assertions fail, a user can reach another user's books.
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/tests/02_rls_isolation.sql
-- =============================================================================

begin;
set constraints all immediate;

create or replace function pg_temp.assert_eq(p_label text, p_actual bigint, p_expected bigint)
returns void language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL % — expected %, got %', p_label, p_expected, p_actual;
  end if;
  raise notice 'ok   % (%)', p_label, p_actual;
end $$;

create or replace function pg_temp.assert_denied(p_label text, p_sql text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'ok   % (denied: %)', p_label, sqlerrm;
    return;
  end;
  raise exception 'SECURITY FAIL % — the operation succeeded but must be denied', p_label;
end $$;

create or replace function pg_temp.become(p_uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
                     true);
  execute 'set local role authenticated';
end $$;

create or replace function pg_temp.become_superuser()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end $$;

-- --- fixture: two workspaces + one disabled user -----------------------------

create temporary table t_ids (label text primary key, id uuid);

do $$
declare
  ua uuid := gen_random_uuid();
  ub uuid := gen_random_uuid();
  ud uuid := gen_random_uuid();
  pa uuid; pb uuid; ta uuid; tb uuid; sa uuid;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values
    ('00000000-0000-0000-0000-000000000000', ua, 'authenticated', 'authenticated', 'rls-a-'||ua||'@example.test', 'x', now(), now(), now()),
    ('00000000-0000-0000-0000-000000000000', ub, 'authenticated', 'authenticated', 'rls-b-'||ub||'@example.test', 'x', now(), now(), now()),
    ('00000000-0000-0000-0000-000000000000', ud, 'authenticated', 'authenticated', 'rls-d-'||ud||'@example.test', 'x', now(), now(), now());

  insert into public.people (owner_id, name, phone) values (ua, 'A-Person', '+911111111111') returning id into pa;
  insert into public.people (owner_id, name, phone) values (ub, 'B-Person', '+912222222222') returning id into pb;

  insert into public.transactions (owner_id, person_id, type, amount_minor, description)
  values (ua, pa, 'credit', 1000000, 'A secret invoice') returning id into ta;
  insert into public.transactions (owner_id, person_id, type, amount_minor, description)
  values (ub, pb, 'credit', 2000000, 'B secret invoice') returning id into tb;

  insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor)
  values (ua, pa, ta, 'in', 100000) returning id into sa;

  update public.profiles set is_active = false where id = ud;

  insert into t_ids values
    ('user_a', ua), ('user_b', ub), ('user_disabled', ud),
    ('person_a', pa), ('person_b', pb),
    ('txn_a', ta), ('txn_b', tb), ('settlement_a', sa);
end $$;

-- --- User A sees only their own workspace ------------------------------------

do $$
declare
  ua uuid := (select id from t_ids where label = 'user_a');
  ub uuid := (select id from t_ids where label = 'user_b');
  pb uuid := (select id from t_ids where label = 'person_b');
  tb uuid := (select id from t_ids where label = 'txn_b');
begin
  perform pg_temp.become(ua);

  perform pg_temp.assert_eq('A sees own people only',
    (select count(*) from public.people), 1);
  perform pg_temp.assert_eq('A sees own transactions only',
    (select count(*) from public.transactions), 1);
  perform pg_temp.assert_eq('A sees own settlements only',
    (select count(*) from public.settlements), 1);
  perform pg_temp.assert_eq('A sees own profile only',
    (select count(*) from public.profiles), 1);
  perform pg_temp.assert_eq('A cannot read B''s person by id',
    (select count(*) from public.people where id = pb), 0);
  perform pg_temp.assert_eq('A cannot read B''s transaction by id',
    (select count(*) from public.transactions where id = tb), 0);
  perform pg_temp.assert_eq('A cannot read B via person_balances view',
    (select count(*) from public.person_balances where owner_id = ub), 0);
  perform pg_temp.assert_eq('A cannot read B via owner_summary view',
    (select count(*) from public.owner_summary where owner_id = ub), 0);
  perform pg_temp.assert_eq('A cannot read B via activity_feed view',
    (select count(*) from public.activity_feed where owner_id = ub), 0);

  -- Search must not leak either (it runs security invoker on the same views).
  perform pg_temp.assert_eq('search does not leak B''s person',
    jsonb_array_length(public.search_all('B-Person') -> 'people'), 0);
  perform pg_temp.assert_eq('search does not leak B''s note',
    jsonb_array_length(public.search_all('B secret') -> 'transactions'), 0);

  perform pg_temp.become_superuser();
end $$;

-- --- User A cannot write into B's workspace ----------------------------------

do $$
declare
  ua uuid := (select id from t_ids where label = 'user_a');
  ub uuid := (select id from t_ids where label = 'user_b');
  pa uuid := (select id from t_ids where label = 'person_a');
  pb uuid := (select id from t_ids where label = 'person_b');
  tb uuid := (select id from t_ids where label = 'txn_b');
begin
  perform pg_temp.become(ua);

  perform pg_temp.assert_denied('A cannot insert a person owned by B',
    format('insert into public.people (owner_id, name) values (%L, ''hijack'')', ub));

  perform pg_temp.assert_denied('A cannot attach a transaction to B''s person',
    format('insert into public.transactions (owner_id, person_id, type, amount_minor) values (%L, %L, ''credit'', 100)', ua, pb));

  perform pg_temp.assert_denied('A cannot forge ownership on a transaction',
    format('insert into public.transactions (owner_id, person_id, type, amount_minor) values (%L, %L, ''credit'', 100)', ub, pb));

  perform pg_temp.assert_denied('A cannot settle against B''s transaction',
    format('insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor) values (%L, %L, %L, ''in'', 100)', ua, pa, tb));

  perform pg_temp.assert_denied('A cannot call person_page on B''s person',
    format('select public.person_page(%L)', pb));

  -- Updates silently match zero rows rather than erroring; assert the effect.
  update public.people set name = 'renamed by A' where id = pb;
  perform pg_temp.become_superuser();
  perform pg_temp.assert_eq('A''s update touched none of B''s rows',
    (select count(*) from public.people where id = pb and name = 'renamed by A'), 0);
end $$;

-- --- Privilege escalation attempts -------------------------------------------

do $$
declare
  ua uuid := (select id from t_ids where label = 'user_a');
begin
  perform pg_temp.become(ua);

  perform pg_temp.assert_denied('user cannot make themselves an admin',
    format('insert into public.app_admins (user_id) values (%L)', ua));

  perform pg_temp.assert_denied('user cannot call grant_admin',
    'select public.grant_admin(''anything@example.test'')');

  perform pg_temp.assert_denied('non-admin cannot list users',
    'select public.admin_list_users()');

  perform pg_temp.assert_denied('non-admin cannot read system info',
    'select public.admin_system_info()');

  perform pg_temp.assert_denied('non-admin cannot toggle account status',
    format('select public.admin_set_user_active(%L, false)', ua));

  perform pg_temp.assert_denied('user cannot reactivate/deactivate themselves',
    'update public.profiles set is_active = false where id = auth.uid()');

  perform pg_temp.assert_eq('is_admin() is false for a normal user',
    (public.is_admin())::int, 0);

  perform pg_temp.become_superuser();
end $$;

-- --- A disabled account is cut off at the database ---------------------------

do $$
declare
  ud uuid := (select id from t_ids where label = 'user_disabled');
  pd uuid;
begin
  -- give the disabled user something to lose
  insert into public.people (owner_id, name) values (ud, 'D-Person') returning id into pd;

  perform pg_temp.become(ud);

  perform pg_temp.assert_eq('disabled user reads no people',
    (select count(*) from public.people), 0);
  perform pg_temp.assert_denied('disabled user cannot insert a person',
    format('insert into public.people (owner_id, name) values (%L, ''nope'')', ud));
  perform pg_temp.assert_denied('disabled user cannot call a write RPC',
    'select public.create_person(''nope'')');
  perform pg_temp.assert_denied('disabled user cannot load the dashboard',
    'select public.dashboard()');

  perform pg_temp.become_superuser();
end $$;

-- --- The anon role reaches nothing at all ------------------------------------

do $$
begin
  execute 'set local role anon';
  perform pg_temp.assert_denied('anon cannot select people',      'select count(*) from public.people');
  perform pg_temp.assert_denied('anon cannot select transactions','select count(*) from public.transactions');
  perform pg_temp.assert_denied('anon cannot select profiles',    'select count(*) from public.profiles');
  perform pg_temp.assert_denied('anon cannot read balances view', 'select count(*) from public.person_balances');
  perform pg_temp.assert_denied('anon cannot call the dashboard', 'select public.dashboard()');
  execute 'reset role';
end $$;

-- --- An admin can manage users but still cannot read their books -------------

do $$
declare
  ua uuid := (select id from t_ids where label = 'user_a');
  ub uuid := (select id from t_ids where label = 'user_b');
begin
  insert into public.app_admins (user_id) values (ua) on conflict do nothing;
  perform pg_temp.become(ua);

  perform pg_temp.assert_eq('admin can list users',
    (case when (public.admin_list_users() ->> 'total')::bigint >= 3 then 1 else 0 end)::bigint, 1::bigint);
  perform pg_temp.assert_eq('admin still cannot see another user''s people',
    (select count(*) from public.people where owner_id = ub), 0);
  perform pg_temp.assert_eq('admin still cannot see another user''s transactions',
    (select count(*) from public.transactions where owner_id = ub), 0);

  perform public.admin_set_user_active(ub, false);
  perform pg_temp.become_superuser();
  perform pg_temp.assert_eq('admin disabled user B',
    (select is_active::int from public.profiles where id = ub), 0);

  perform pg_temp.become(ua);
  perform pg_temp.assert_denied('admin cannot disable their own account',
    format('select public.admin_set_user_active(%L, false)', ua));
  perform pg_temp.become_superuser();
end $$;

do $$ begin raise notice E'\n=== ALL RLS / AUTHORIZATION TESTS PASSED ===\n'; end $$;

rollback;
