-- =============================================================================
-- 07_void_person_history.sql — retracting a whole account at once
--
-- `void_person_history()` exists so an account entered wrong can be started
-- over without retracting thirty rows by hand. The thing that makes it safe to
-- offer at all is that it is a **void**, not a delete, and these assertions are
-- what hold that line:
--
--   1. it voids every live transaction and settlement and reports the counts
--   2. the balance goes to zero
--   3. NOTHING is deleted — every row is still in the table, with its amount,
--      its date and its currency intact
--   4. the entries leave the activity feed
--   5. the person survives; only their history is retracted
--   6. rows already voided are not counted twice, and a second call is a no-op
--   7. it never touches another person's rows, or another owner's
--   8. an unknown person is refused rather than silently doing nothing
--
-- Self-contained: creates its own users, asserts, then ROLLS BACK.
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

create or replace function pg_temp.assert_raises(p_label text, p_sql text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'ok  % (rejected: %)', p_label, sqlerrm;
    return;
  end;
  raise exception 'FAIL: % — the statement was allowed', p_label;
end $$;

do $$
declare
  v_owner     uuid := gen_random_uuid();
  v_stranger  uuid := gen_random_uuid();
  v_person    uuid;
  v_bystander uuid;
  v_theirs    uuid;
  v_txn       uuid;
  v_result    jsonb;
  v_again     jsonb;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'void-history@example.com', 'x', now(), now(), now()),
         ('00000000-0000-0000-0000-000000000000', v_stranger, 'authenticated', 'authenticated',
          'void-history-other@example.com', 'x', now(), now(), now());

  -- The stranger's own account, used at the end to prove the scoping.
  perform pg_temp.become(v_stranger);
  v_theirs := (public.create_person('Not Yours', 'person')).id;
  perform public.create_transaction(v_theirs, 'credit', 700000, current_date, null);

  perform pg_temp.become(v_owner);

  -- Three live transactions and a settlement against one of them, plus one row
  -- the user had already retracted by hand.
  v_person := (public.create_person('Wrongly Entered', 'business')).id;
  perform public.create_transaction(v_person, 'credit', 500000, current_date, 'first');
  perform public.create_transaction(v_person, 'debit',  300000, current_date, 'second');
  perform public.create_transaction(v_person, 'credit', 200000, current_date, 'third');

  select id into v_txn from public.transactions
   where person_id = v_person and description = 'third';
  perform public.create_settlement(v_person, 200000, 'in', v_txn, current_date, 'paid');

  -- A fourth entry, already voided before the bulk call.
  perform public.create_transaction(v_person, 'debit', 100000, current_date, 'already gone');
  perform public.void_transaction(
    (select id from public.transactions where person_id = v_person and description = 'already gone'),
    'mistake');

  -- A second person who must be left completely alone.
  v_bystander := (public.create_person('Untouched', 'person')).id;
  perform public.create_transaction(v_bystander, 'credit', 900000, current_date, null);

  -- ---------------------------------------------------------------- the call
  v_result := public.void_person_history(v_person, 'entered against the wrong account');

  -- 1. Counts. Three live transactions, one settlement. The row that was
  --    already voided is not counted again.
  perform pg_temp.assert(
    'every live transaction is voided, and only those',
    (v_result->>'transactions_voided')::int = 3);
  perform pg_temp.assert(
    'the settlement is voided too',
    (v_result->>'settlements_voided')::int = 1);

  -- 2. The balance goes to zero.
  perform pg_temp.assert(
    'the balance is zero afterwards',
    coalesce((select net_balance from public.person_balances where person_id = v_person), 0) = 0);
  perform pg_temp.assert(
    'and nothing is left outstanding either way',
    coalesce((select outstanding_receivable + outstanding_payable
                from public.person_balances where person_id = v_person), 0) = 0);

  -- 3. Nothing was deleted. This is the assertion the whole feature rests on.
  perform pg_temp.assert(
    'all four transactions are still in the table',
    (select count(*) from public.transactions where person_id = v_person) = 4);
  perform pg_temp.assert(
    'the settlement is still in the table',
    (select count(*) from public.settlements where person_id = v_person) = 1);
  perform pg_temp.assert(
    'and every one of them is marked voided',
    not exists (select 1 from public.transactions
                 where person_id = v_person and not is_void)
    and not exists (select 1 from public.settlements
                     where person_id = v_person and not is_void));
  perform pg_temp.assert(
    'the amounts are untouched — this is a retraction, not a rewrite',
    (select sum(amount_minor) from public.transactions where person_id = v_person)
      = 500000 + 300000 + 200000 + 100000);
  perform pg_temp.assert(
    'the reason is recorded on the rows',
    (select count(*) from public.transactions
      where person_id = v_person
        and void_reason = 'entered against the wrong account') = 3);

  -- 4. They leave the feed.
  perform pg_temp.assert(
    'the entries are gone from the activity feed',
    not exists (select 1 from public.activity_feed
                 where person_id = v_person and not is_void));

  -- 5. The person is still there.
  perform pg_temp.assert(
    'the person survives — only their history was retracted',
    exists (select 1 from public.people where id = v_person));

  -- 6. A second call is a no-op rather than an error.
  v_again := public.void_person_history(v_person, null);
  perform pg_temp.assert(
    'a second call voids nothing and does not fail',
    (v_again->>'transactions_voided')::int = 0
    and (v_again->>'settlements_voided')::int = 0);
  perform pg_temp.assert(
    'and it did not overwrite the reason already recorded',
    (select count(*) from public.transactions
      where person_id = v_person
        and void_reason = 'entered against the wrong account') = 3);

  -- 7. Scoping, both ways.
  perform pg_temp.assert(
    'another person in the same workspace is untouched',
    (select count(*) from public.transactions
      where person_id = v_bystander and not is_void) = 1);
  perform pg_temp.assert(
    'and their balance still stands',
    (select net_balance from public.person_balances where person_id = v_bystander) <> 0);

  perform pg_temp.assert_raises(
    'another owner''s person cannot be retracted',
    format('select public.void_person_history(%L)', v_theirs));

  perform pg_temp.become(v_stranger);
  perform pg_temp.assert(
    'and their history is genuinely still live',
    (select count(*) from public.transactions
      where person_id = v_theirs and not is_void) = 1);

  perform pg_temp.become(v_owner);

  -- 8. An unknown person is refused by name.
  perform pg_temp.assert_raises(
    'an unknown person is refused',
    format('select public.void_person_history(%L)', gen_random_uuid()));

  raise notice '=== ALL VOID PERSON HISTORY TESTS PASSED ===';
end $$;

rollback;
