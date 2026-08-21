-- =============================================================================
-- 03_delete_person.sql — the rule for deleting a person
--
-- Regression: a person whose only transactions had been voided reported zero
-- transactions and a zero balance — because `person_balances` excludes voided
-- rows from every figure — and then refused to be deleted, because
-- `delete_person()` counted every row including the voided ones. The clients
-- read the view, so Delete was offered and then refused.
--
-- What is asserted here:
--   1. a person with nothing at all can be deleted
--   2. a person whose transactions are all voided can be deleted, and the
--      voided rows go with them
--   3. one live transaction blocks the delete
--   4. an account whose transaction and settlement were both reversed is
--      deletable, and the voided settlement is removed with it
--   5. the delete is still scoped to the owner
--
-- Self-contained: creates its own user, asserts, then ROLLS BACK.
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
  v_owner uuid := gen_random_uuid();
  v_empty uuid;
  v_void  uuid;
  v_live  uuid;
  v_paid  uuid;
  v_txn   uuid;
  v_settlement uuid;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'delete-test@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);

  -- 1. Nothing recorded at all.
  v_empty := (public.create_person('Nobody', 'person')).id;
  perform public.delete_person(v_empty);
  perform pg_temp.assert(
    'a person with no records is deleted',
    not exists (select 1 from public.people where id = v_empty));

  -- 2. Every transaction voided. This is the reported bug.
  v_void := (public.create_person('All Voided', 'person')).id;
  perform public.create_transaction(v_void, 'debit', 480000, current_date, null);
  select id into v_txn from public.transactions where person_id = v_void;
  perform public.void_transaction(v_txn, 'mistake');

  perform pg_temp.assert(
    'the view reports no transactions once they are voided',
    (select transaction_count from public.person_balances where person_id = v_void) = 0);

  perform public.delete_person(v_void);
  perform pg_temp.assert(
    'a person whose transactions are all voided is deleted',
    not exists (select 1 from public.people where id = v_void));
  perform pg_temp.assert(
    'the voided rows go with them',
    not exists (select 1 from public.transactions where person_id = v_void));

  -- 3. One live transaction blocks it.
  v_live := (public.create_person('Has History', 'person')).id;
  perform public.create_transaction(v_live, 'credit', 500000, current_date, null);
  perform pg_temp.assert_raises(
    'a live transaction blocks the delete',
    format('select public.delete_person(%L)', v_live));
  perform pg_temp.assert(
    'and the person is still there',
    exists (select 1 from public.people where id = v_live));

  -- 4. A settlement that was itself reversed. Voiding a *settled* transaction
  --    is refused by the engine, so the only way to a fully retracted account
  --    is to reverse the settlement first — and then the person is deletable,
  --    and the voided settlement goes with them.
  v_paid := (public.create_person('Paid Then Reversed', 'person')).id;
  perform public.create_transaction(v_paid, 'credit', 100000, current_date, null);
  select id into v_txn from public.transactions where person_id = v_paid;
  perform public.create_settlement(v_paid, 100000, 'in', v_txn, current_date, null);

  select id into v_settlement from public.settlements where person_id = v_paid;
  perform public.void_settlement(v_settlement, 'reversed');
  perform public.void_transaction(v_txn, 'mistake');

  perform pg_temp.assert(
    'nothing live is left on the account',
    (select transaction_count from public.person_balances where person_id = v_paid) = 0
    and (select total_settled from public.person_balances where person_id = v_paid) = 0);

  perform public.delete_person(v_paid);
  perform pg_temp.assert(
    'a fully retracted account is deleted',
    not exists (select 1 from public.people where id = v_paid));
  perform pg_temp.assert(
    'the voided settlement goes with them',
    not exists (select 1 from public.settlements where person_id = v_paid));

  -- 5. Still scoped to the owner: another signed-in user cannot delete it.
  perform pg_temp.become(gen_random_uuid());
  perform pg_temp.assert_raises(
    'a different caller cannot delete this person',
    format('select public.delete_person(%L)', v_live));

  perform pg_temp.become_superuser();
end $$;

do $$ begin raise notice E'\n=== ALL DELETE-PERSON TESTS PASSED ===\n'; end $$;

rollback;
