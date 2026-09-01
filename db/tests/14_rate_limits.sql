-- =============================================================================
-- 14_rate_limits.sql — write rate limiting (0026)
--
-- What has to be true before a limit is worth having:
--
--   * IT FIRES. A session that writes past its bucket is refused, with a
--     SQLSTATE a client can recognise and a sentence a user can read.
--   * IT REFUSES THE WRITE, not the workspace. The refused row is not there
--     afterwards; everything written before it still is.
--   * IT CANNOT BE RESET BY THE CALLER. A user who could update their own
--     counter would have a decorative limit.
--   * IT IS PER OWNER. One workspace filling its bucket must not refuse
--     another's writes.
--   * IT DOES NOT TOUCH READS, OR CORRECTIONS. Voiding and editing are how a
--     user fixes a mistake; a limit that blocked them would be a worse bug than
--     the one it prevents.
--
-- The limits are lowered inside this transaction so the test does not have to
-- write 120 rows to prove one. The rollback puts them back.
--
--   node db/tools/run-sql.mjs test
-- =============================================================================

begin;

set constraints all immediate;

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

create or replace function pg_temp.assert(p_label text, p_condition boolean)
returns void language plpgsql as $$
begin
  if not p_condition then
    raise exception 'FAIL: %', p_label;
  end if;
  raise notice 'ok  %', p_label;
end $$;

create or replace function pg_temp.assert_eq(p_label text, p_actual bigint, p_expected bigint)
returns void language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL % — expected %, got %', p_label, p_expected, p_actual;
  end if;
  raise notice 'ok  % (%)', p_label, p_actual;
end $$;

-- Tighten the buckets for the duration of this transaction only.
update public.rate_limits set max_events = 3   where bucket = 'transactions';
update public.rate_limits set max_events = 2   where bucket = 'people';
update public.rate_limits set max_events = 100 where bucket = 'writes';

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_ved   uuid;
  v_them  uuid;
  v_state text;
  v_count int;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'ratelimit-owner@example.com', 'x', now(), now(), now()),
         ('00000000-0000-0000-0000-000000000000', v_other, 'authenticated', 'authenticated',
          'ratelimit-other@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);
  perform public.update_my_profile('Limit Tester', null, null, 'INR', null);
  v_ved := (public.create_person('VED', 'person', null, null, null, null, 'INR')).id;

  -- ===========================================================================
  -- It fires, and it fires with a code a client can act on
  -- ===========================================================================
  perform public.create_transaction(
    p_person_id => v_ved, p_type => 'credit', p_amount_minor => 100,
    p_date => current_date, p_description => 'one');
  perform public.create_transaction(
    p_person_id => v_ved, p_type => 'credit', p_amount_minor => 100,
    p_date => current_date, p_description => 'two');
  perform public.create_transaction(
    p_person_id => v_ved, p_type => 'credit', p_amount_minor => 100,
    p_date => current_date, p_description => 'three');

  begin
    perform public.create_transaction(
      p_person_id => v_ved, p_type => 'credit', p_amount_minor => 100,
      p_date => current_date, p_description => 'four');
    raise exception 'FAIL: the fourth write past a limit of three was accepted';
  exception when sqlstate 'AC429' then
    v_state := sqlerrm;
    raise notice 'ok  a write past the limit is refused (%)', v_state;
  end;

  perform pg_temp.assert('the refusal is a sentence, not a code',
    v_state like 'Too many transactions%');
  perform pg_temp.assert('and it says nothing was saved',
    v_state like '%nothing has been saved.');

  -- ===========================================================================
  -- It refuses the write, not the workspace
  -- ===========================================================================
  perform pg_temp.assert_eq('the three accepted entries are still there',
    (select count(*) from public.transactions
     where owner_id = v_owner and description in ('one', 'two', 'three')), 3);

  perform pg_temp.assert_eq('the refused one is not',
    (select count(*) from public.transactions
     where owner_id = v_owner and description = 'four'), 0);

  -- A correction is not a creation: voiding still works with a full bucket.
  perform public.void_transaction(
    (select id from public.transactions where owner_id = v_owner and description = 'one'),
    'still allowed');
  perform pg_temp.assert('voiding is never rate limited',
    (select is_void from public.transactions
     where owner_id = v_owner and description = 'one'));

  -- So does reading.
  perform pg_temp.assert('reading is never rate limited',
    (public.dashboard() -> 'summary') is not null);

  -- ===========================================================================
  -- Buckets are separate, and per owner
  -- ===========================================================================
  perform pg_temp.assert('a full transaction bucket does not block a settlement',
    (public.create_settlement(
       p_person_id => v_ved, p_direction => 'in', p_amount_minor => 100,
       p_date => current_date, p_note => 'settling under a full txn bucket')) is not null);

  perform pg_temp.become(v_other);
  perform public.update_my_profile('Other Limiter', null, null, 'INR', null);
  v_them := (public.create_person('THEIRS', 'person', null, null, null, null, 'INR')).id;
  perform pg_temp.assert('another workspace writes normally with its own bucket',
    (public.create_transaction(
       p_person_id => v_them, p_type => 'credit', p_amount_minor => 100,
       p_date => current_date, p_description => 'theirs')) is not null);

  -- ===========================================================================
  -- The counter is the caller's to see, and nobody's to change
  -- ===========================================================================
  perform pg_temp.become(v_owner);

  select events into v_count
  from public.rate_limit_counters
  where owner_id = v_owner and bucket = 'transactions';
  perform pg_temp.assert('a user can read their own counter', v_count >= 3);

  perform pg_temp.assert_eq('and cannot see anyone else''s',
    (select count(*) from public.rate_limit_counters where owner_id = v_other), 0);

  begin
    update public.rate_limit_counters set events = 0 where owner_id = v_owner;
    if found then
      raise exception 'FAIL: a user reset their own rate-limit counter';
    end if;
    raise notice 'ok  updating a counter changes nothing';
  exception when insufficient_privilege then
    raise notice 'ok  a user cannot write their own counter (denied)';
  end;

  begin
    update public.rate_limits set max_events = 1000000 where bucket = 'transactions';
    if found then
      raise exception 'FAIL: a user raised their own limit';
    end if;
    raise notice 'ok  raising the limit changes nothing';
  exception when insufficient_privilege then
    raise notice 'ok  a user cannot edit the limits (denied)';
  end;

  raise notice '=== 14_rate_limits: all assertions passed ===';
end $$;

rollback;
