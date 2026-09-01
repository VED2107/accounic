-- =============================================================================
-- 15_client_errors.sql — production error telemetry (0028)
--
-- Telemetry in an accounting product is a privacy feature before it is a
-- debugging one. What has to be true:
--
--   * IT ANSWERS "WHERE DID IT FAIL AND WHAT WAS THE USER DOING" — app,
--     version, route, operation, type, message, grouped by fingerprint.
--   * IT CANNOT ANSWER "WHAT ARE THEIR FINANCIAL RECORDS". An amount, a phone
--     number, an email address or an entry id in a report is stripped on the
--     way in, even when the client that sent it was careless.
--   * A REPORT BELONGS TO ITS OWNER. One workspace can never read another's.
--   * NOBODY WRITES THE TABLE DIRECTLY. The RPC is the only door, which is what
--     makes the redaction unavoidable rather than optional.
--   * A CRASH LOOP CANNOT FLOOD IT. Telemetry has its own rate-limit bucket.
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

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_id    uuid;
  v_row   public.client_errors%rowtype;
  v_sum   jsonb;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'telemetry-owner@example.com', 'x', now(), now(), now()),
         ('00000000-0000-0000-0000-000000000000', v_other, 'authenticated', 'authenticated',
          'telemetry-other@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);

  -- ===========================================================================
  -- A report says where and what
  -- ===========================================================================
  v_id := public.report_client_error(
    p_app         => 'android',
    p_error_type  => 'StateError',
    p_message     => 'Bad state: no element',
    p_fingerprint => 'android:person_screen:StateError:no-element',
    p_app_version => '1.9.0+22',
    p_environment => 'production',
    p_route       => '/people/detail',
    p_operation   => 'load_person_page',
    p_context     => jsonb_build_object('screen', 'person', 'sqlstate', 'P0002', 'attempt', 2)
  );

  select * into v_row from public.client_errors where id = v_id;

  perform pg_temp.assert('the report is attributed to the caller', v_row.owner_id = v_owner);
  perform pg_temp.assert('it names the build', v_row.app = 'android' and v_row.app_version = '1.9.0+22');
  perform pg_temp.assert('it names where', v_row.route = '/people/detail');
  perform pg_temp.assert('it names what the user was doing', v_row.operation = 'load_person_page');
  perform pg_temp.assert('and it groups', v_row.fingerprint like 'android:person_screen:%');
  perform pg_temp.assert('whitelisted context survives',
    (v_row.context ->> 'sqlstate') = 'P0002' and (v_row.context ->> 'attempt') = '2');

  -- ===========================================================================
  -- It cannot answer what the money is
  -- ===========================================================================
  v_id := public.report_client_error(
    p_app         => 'web',
    p_error_type  => 'PostgrestException',
    p_message     => 'Failed to settle 12,500.00 for rahul.kumar@example.com '
                     || 'on +919812345678 (person 3f1a2b4c-5d6e-4f70-8901-abcdef123456)',
    p_fingerprint => 'web:settle:PostgrestException',
    p_context     => jsonb_build_object(
                       'amount_minor', 1250000,
                       'note', 'rent for August, paid in cash',
                       'person_name', 'Rahul Kumar',
                       'access_token', 'ey.super.secret',
                       'screen', 'settle sheet for 12,500.00')
  );

  select * into v_row from public.client_errors where id = v_id;

  perform pg_temp.assert('an amount in the message is redacted',
    v_row.message not like '%12,500.00%' and v_row.message like '%[amount]%');
  perform pg_temp.assert('an email address is redacted',
    v_row.message not like '%@example.com%' and v_row.message like '%[email]%');
  perform pg_temp.assert('a phone number is redacted',
    v_row.message not like '%919812345678%' and v_row.message like '%[number]%');
  perform pg_temp.assert('an entry id is redacted',
    v_row.message not like '%3f1a2b4c%' and v_row.message like '%[id]%');

  perform pg_temp.assert('an amount sent as context is dropped entirely',
    not (v_row.context ? 'amount_minor'));
  perform pg_temp.assert('so is a note',
    not (v_row.context ? 'note'));
  perform pg_temp.assert('so is a person''s name',
    not (v_row.context ? 'person_name'));
  perform pg_temp.assert('and so is anything that looks like a credential',
    not (v_row.context ? 'access_token'));
  perform pg_temp.assert('a whitelisted key is still redacted inside',
    (v_row.context ->> 'screen') like '%[amount]%');

  perform pg_temp.assert('the whole row carries no digit run at all',
    (v_row.message || coalesce(v_row.route, '') || v_row.context::text) !~ '[0-9]{7,}');

  -- ===========================================================================
  -- Ownership
  -- ===========================================================================
  perform pg_temp.become(v_other);
  perform public.report_client_error('web', 'TypeError', 'theirs', 'other:fingerprint');

  perform pg_temp.assert_eq('a user sees only their own reports',
    (select count(*) from public.client_errors), 1);

  perform pg_temp.become(v_owner);
  perform pg_temp.assert_eq('and so does the other one',
    (select count(*) from public.client_errors), 2);

  perform pg_temp.assert('no report from another workspace is visible',
    (select count(*) from public.client_errors where message = 'theirs') = 0);

  -- ===========================================================================
  -- The table has one door
  -- ===========================================================================
  begin
    insert into public.client_errors (app, error_type, message, fingerprint)
    values ('web', 'Direct', 'written around the RPC', 'direct');
    raise exception 'FAIL: a client wrote the telemetry table directly';
  exception when insufficient_privilege then
    raise notice 'ok  the table cannot be written directly (denied)';
  end;

  begin
    update public.client_errors set message = 'rewritten' where owner_id = v_owner;
    if found then
      raise exception 'FAIL: a report was rewritten after the fact';
    end if;
    raise notice 'ok  a report cannot be rewritten';
  exception when insufficient_privilege then
    raise notice 'ok  a report cannot be rewritten (denied)';
  end;

  -- ===========================================================================
  -- What an operator reads
  -- ===========================================================================
  perform public.report_client_error(
    'android', 'StateError', 'Bad state: no element',
    'android:person_screen:StateError:no-element', '1.9.0+22');

  v_sum := public.my_error_summary(14);

  perform pg_temp.assert('the summary groups by fault, not by occurrence',
    jsonb_array_length(v_sum) = 2);
  perform pg_temp.assert('and counts the repeats',
    (select (e ->> 'occurrences')::int
     from jsonb_array_elements(v_sum) e
     where e ->> 'fingerprint' = 'android:person_screen:StateError:no-element') = 2);

  raise notice '=== 15_client_errors: all assertions passed ===';
end $$;

-- A crash loop is recorded, then refused — in its own bucket, so the ledger's
-- write budget is untouched by it.
do $$
declare
  v_owner uuid := gen_random_uuid();
  i int;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'telemetry-loop@example.com', 'x', now(), now(), now());

  update public.rate_limits set max_events = 3 where bucket = 'telemetry';
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  for i in 1..3 loop
    perform public.report_client_error('web', 'Loop', 'again', 'loop:fingerprint');
  end loop;

  begin
    perform public.report_client_error('web', 'Loop', 'again', 'loop:fingerprint');
    raise exception 'FAIL: a crash loop reported without limit';
  exception when sqlstate 'AC429' then
    raise notice 'ok  a crash loop is recorded a few times, then refused';
  end;
end $$;

rollback;
