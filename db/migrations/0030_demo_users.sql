-- =============================================================================
-- 0030_demo_users.sql
-- Demo accounts live in the REAL project, beside real ones.
--
-- 0029 was written for a separate demo project. That is no longer the shape:
-- there is one Accounic database, one accounting engine, one security model,
-- and a demo account is an ordinary account carrying a flag. This migration is
-- what makes that safe and administrable, and it supersedes 0029's copies of
-- `handle_new_auth_user()` and `is_demo_visitor()` rather than editing them.
--
-- The flag has ONE home: profiles.is_demo. 0029 read it out of the auth user's
-- app metadata, which cannot be joined, filtered, indexed or listed, and which
-- an admin RPC cannot write without reaching into the auth schema. The column
-- is backfilled from that metadata below, so nothing set the old way is lost,
-- and `demo-account.mjs` now writes the column.
--
-- WHAT DOES NOT CHANGE, and must not:
--
--   * RLS. A demo user is confined by exactly the predicates a paying user is
--     confined by -- owner_id = current_owner(), nothing else. There is no demo
--     branch in any policy, and this migration adds none. A demo user cannot
--     see another demo user, a real user, or an administrator.
--
--   * The accounting engine. Nothing here computes a balance, and demo_seed()
--     still writes its sample books through create_person(),
--     create_transaction() and create_settlement().
--
--   * The service-role boundary. Every function here is SECURITY DEFINER with
--     an is_admin() check in its own body, callable with the anon key by an
--     administrator and by nobody else. No client is ever given a privileged
--     credential in order to run one.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The flag.
-- -----------------------------------------------------------------------------

alter table public.profiles
  add column if not exists is_demo boolean not null default false;

comment on column public.profiles.is_demo is
  'True for demo accounts -- the shared demo login and every anonymous demo '
  'visitor. Set only by the service role or by admin_convert_demo_user(); a '
  'user cannot change their own. Isolation does not depend on it: RLS confines '
  'a demo account exactly as it confines any other.';

-- Partial, because the question is always "which accounts are demo ones" and
-- never "which are not". On a table where demo rows are the minority this is a
-- few pages rather than one entry per user.
create index if not exists profiles_is_demo_idx
  on public.profiles (created_at desc)
  where is_demo;

-- Backfill from where 0029 kept it, and from the structural fact that an
-- anonymous user can only ever have been a demo visitor.
update public.profiles p
   set is_demo = true
  from auth.users u
 where u.id = p.id
   and p.is_demo = false
   and (
     coalesce((u.raw_app_meta_data ->> 'is_demo')::boolean, false)
     or coalesce(u.is_anonymous, false)
   );

-- -----------------------------------------------------------------------------
-- 2. Provisioning a profile.
--
-- Supersedes 0029's copy. Two additions over the original in 0001, both for the
-- same reason -- an anonymous demo visitor is an auth user with no email:
--
--   * a synthetic address, because profiles.email is NOT NULL (.invalid is
--     reserved by RFC 2606 precisely so it can never resolve);
--   * is_demo, from the anonymous flag or from app metadata, so a demo account
--     is marked the moment it exists rather than by a later sweep.
--
-- The path a real, named user takes through this function is unchanged.
-- -----------------------------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := coalesce(new.email, new.id::text || '@anonymous.invalid');
  v_demo  boolean := coalesce(new.is_anonymous, false)
                     or coalesce((new.raw_app_meta_data ->> 'is_demo')::boolean, false);
begin
  insert into public.profiles (id, email, name, phone, business_name, currency, is_demo)
  values (
    new.id,
    v_email,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(v_email, '@', 1)),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    nullif(new.raw_user_meta_data ->> 'business_name', ''),
    coalesce(nullif(upper(new.raw_user_meta_data ->> 'currency'), ''), 'INR'),
    v_demo
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. Who counts as a demo caller.
--
-- Supersedes 0029's copy, which read app metadata. Two sources, and the second
-- is not a second mechanism: it is the structural fact that an anonymous user
-- has no credentials and therefore can never be anything but a demo visitor,
-- kept as a floor under the column in case a profile row was ever provisioned
-- some other way.
-- -----------------------------------------------------------------------------

create or replace function public.is_demo_visitor()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
      (select p.is_demo from public.profiles p where p.id = auth.uid()),
      false
    )
    or coalesce(
      (select u.is_anonymous from auth.users u where u.id = auth.uid()),
      false
    );
$$;

revoke all on function public.is_demo_visitor() from public, anon;
grant execute on function public.is_demo_visitor() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4. The client learns its own status.
--
-- One key added to me(). It is what separates the two concepts the application
-- deliberately keeps apart: the BUILD may be the demo build, and the ACCOUNT
-- may be a demo account, and neither implies the other. A demo account signing
-- in to the Windows app is still a demo account, and this is how that build
-- finds out (app/lib/core/demo.dart).
-- -----------------------------------------------------------------------------

create or replace function public.me()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return null;
  end if;

  return (
    select jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'email', p.email::text,
      'phone', p.phone,
      'business_name', p.business_name,
      'avatar_url', p.avatar_url,
      'currency', p.currency,
      'is_active', p.is_active,
      'is_admin', public.is_admin(p.id),
      'is_demo', p.is_demo,
      'created_at', p.created_at
    )
    from public.profiles p where p.id = v_uid
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. Administrative record.
--
-- There was no admin audit table before this. One is added rather than a second
-- audit system invented later: a conversion changes what a person is allowed to
-- do, and an operation like that should leave a trace naming who did it.
--
-- Deliberately generic in shape and deliberately tiny in scope. It records
-- administrative ACTIONS. It is not, and must never become, a log of what
-- anybody's ledger contains.
-- -----------------------------------------------------------------------------

create table if not exists public.admin_events (
  id         uuid primary key default gen_random_uuid(),
  at         timestamptz not null default now(),
  actor_id   uuid references auth.users (id) on delete set null,
  action     text not null,
  target_id  uuid references auth.users (id) on delete set null,
  detail     jsonb not null default '{}'::jsonb,

  constraint admin_events_action_len check (char_length(action) between 1 and 64)
);

comment on table public.admin_events is
  'Administrative actions, for accountability. Written by SECURITY DEFINER '
  'admin functions; readable by administrators only. Never ledger contents.';

create index if not exists admin_events_at_idx on public.admin_events (at desc);

alter table public.admin_events enable row level security;

-- Read-only, administrators only. There is deliberately no insert, update or
-- delete policy: rows arrive through SECURITY DEFINER functions, which bypass
-- RLS, so no client can write or rewrite the record of what it did.
drop policy if exists admin_events_read on public.admin_events;
create policy admin_events_read on public.admin_events
  for select to authenticated
  using (public.is_admin());

revoke all on table public.admin_events from public, anon;
grant select on table public.admin_events to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Listing users, now with demo status.
--
-- The existing RPC extended rather than a second one added beside it: the
-- administration screen has one account list, and "show me the demo ones" is a
-- filter on that list, not a different list.
--
-- p_demo_only defaults to null, meaning "everyone", so every existing caller --
-- including a Windows client built before this migration -- keeps behaving
-- exactly as it did.
-- -----------------------------------------------------------------------------

-- Adding a parameter creates an OVERLOAD, it does not replace. Both would then
-- match a three-argument call and Postgres would refuse it as ambiguous, so the
-- old signature goes first. Nothing depends on it that is not updated here.
drop function if exists public.admin_list_users(text, int, int);

create or replace function public.admin_list_users(
  p_query     text default null,
  p_limit     int  default 50,
  p_offset    int  default 0,
  p_demo_only boolean default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text;
  v_demo boolean := p_demo_only;
begin
  if not public.is_admin() then
    raise exception 'Administrator access is required.' using errcode = 'insufficient_privilege';
  end if;

  p_limit  := least(greatest(coalesce(p_limit, 50), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);
  v_like   := '%' || btrim(coalesce(p_query, '')) || '%';

  return jsonb_build_object(
    'total', (
      select count(*) from public.profiles p
      where (p.name ilike v_like or p.email::text ilike v_like)
        and (v_demo is null or p.is_demo = v_demo)
    ),
    'users', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from (
        select p.id, p.name, p.email::text as email, p.phone, p.business_name,
               p.currency, p.is_active, p.is_demo, p.created_at, p.updated_at,
               public.is_admin(p.id) as is_admin,
               coalesce(u.is_anonymous, false) as is_anonymous,
               u.last_sign_in_at,
               (select count(*) from public.people       x where x.owner_id = p.id) as people_count,
               (select count(*) from public.transactions x where x.owner_id = p.id) as transaction_count
        from public.profiles p
        join auth.users u on u.id = p.id
        where (p.name ilike v_like or p.email::text ilike v_like)
          and (v_demo is null or p.is_demo = v_demo)
        order by p.created_at desc
        limit p_limit offset p_offset
      ) r
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_list_users(text, int, int, boolean) from public, anon;
grant execute on function public.admin_list_users(text, int, int, boolean)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7. Demo account -> real account.
--
-- The same person, the same account, the same books. One column changes.
--
-- Every check the operation needs is HERE, not in the client, because the
-- client is the thing being defended against:
--
--   1. the caller is an administrator;
--   2. the target exists;
--   3. the target is currently a demo account -- if it is not, this REFUSES
--      rather than writing, so a misfired click on a paying customer's row
--      cannot quietly do nothing visible and something real;
--   4. the target is not anonymous, because an anonymous user has no email and
--      no password, and "converting" one would produce a real account that
--      nobody on earth can sign in to.
--
-- What it deliberately does NOT do is touch the ledger. Not one person, entry
-- or settlement is read, moved or removed. The account's demo books become its
-- real books, which is the point -- a visitor who becomes a customer keeps the
-- work they did while deciding. Discarding that history would be a different
-- operation, and it would have to be asked for by name.
-- -----------------------------------------------------------------------------

create or replace function public.admin_convert_demo_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor     uuid := auth.uid();
  v_profile   public.profiles;
  v_anonymous boolean;
  v_people    int;
  v_entries   int;
begin
  if not public.is_admin() then
    raise exception 'Administrator access is required.' using errcode = 'insufficient_privilege';
  end if;

  select * into v_profile from public.profiles p where p.id = p_user_id;
  if not found then
    raise exception 'User not found.' using errcode = 'no_data_found';
  end if;

  if not v_profile.is_demo then
    raise exception 'That account is not a demo account, so there is nothing to convert.'
      using errcode = 'check_violation';
  end if;

  select coalesce(u.is_anonymous, false) into v_anonymous
  from auth.users u where u.id = p_user_id;

  if v_anonymous then
    raise exception
      'That is an anonymous demo visitor with no email or password. Create a real '
      'account for them instead.'
      using errcode = 'check_violation';
  end if;

  -- Counted before the change, so the record says what the account was carrying
  -- at the moment it became real.
  select count(*) into v_people  from public.people       x where x.owner_id = p_user_id;
  select count(*) into v_entries from public.transactions x where x.owner_id = p_user_id and not x.is_void;

  update public.profiles set is_demo = false where id = p_user_id;

  insert into public.admin_events (actor_id, action, target_id, detail)
  values (
    v_actor,
    'demo_user_converted',
    p_user_id,
    jsonb_build_object(
      'email', v_profile.email::text,
      'name', v_profile.name,
      'people_kept', v_people,
      'transactions_kept', v_entries
    )
  );

  return jsonb_build_object(
    'id', p_user_id,
    'email', v_profile.email::text,
    'name', v_profile.name,
    'is_demo', false,
    'people_kept', v_people,
    'transactions_kept', v_entries
  );
end;
$$;

revoke all on function public.admin_convert_demo_user(uuid) from public, anon;
grant execute on function public.admin_convert_demo_user(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 8. The summary counts demo accounts.
--
-- One number, on the screen an administrator already looks at, answering the
-- question this whole migration creates: how many of these are demos?
-- -----------------------------------------------------------------------------

create or replace function public.admin_system_info()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access is required.' using errcode = 'insufficient_privilege';
  end if;

  return jsonb_build_object(
    'users_total',        (select count(*) from public.profiles),
    'users_active',       (select count(*) from public.profiles where is_active),
    'users_demo',         (select count(*) from public.profiles where is_demo),
    'admins',             (select count(*) from public.app_admins),
    'people_total',       (select count(*) from public.people),
    'transactions_total', (select count(*) from public.transactions where not is_void),
    'settlements_total',  (select count(*) from public.settlements where not is_void),
    'database_size',      pg_size_pretty(pg_database_size(current_database())),
    'server_time',        now()
  );
end;
$$;
