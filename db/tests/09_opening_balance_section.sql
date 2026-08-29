-- =============================================================================
-- 09_opening_balance_section.sql — the opening balance is its own thing (0019)
--
-- What this pins:
--
--   1. an opening balance written by an older version, carrying only the
--      description, is reclassified in place by 0019 §1 — same id, same amount,
--      same currency, same date — and never duplicated;
--   2. running that reclassification twice changes nothing the second time;
--   3. the opening balance is served in `opening`, not in `timeline`, and not
--      in `open_transactions`;
--   4. it still counts towards the current position, to the paisa;
--   5. it cannot be settled as an individual transaction, while settling the
--      account as a whole still works and still retires it;
--   6. replacing one retracts the old rather than editing it, and the retracted
--      one appears in `opening_history` and nowhere else.
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

create or replace function pg_temp.assert(p_label text, p_condition boolean)
returns void language plpgsql as $$
begin
  if not p_condition then
    raise exception 'FAIL: %', p_label;
  end if;
  raise notice 'ok  %', p_label;
end $$;

-- 0019 §1, extracted verbatim so the test exercises the migration's own rule
-- rather than a paraphrase of it. If the migration changes and this does not,
-- assertion 2 below stops proving anything — which is why it is a function and
-- not a copy of the WHERE clause inline.
create or replace function pg_temp.reclassify_openings()
returns bigint language plpgsql as $$
declare v_n bigint;
begin
  with candidate as (
    select t.id
    from public.transactions t
    where not t.is_void
      and not t.is_opening
      and lower(btrim(coalesce(t.description, ''))) = 'opening balance'
      and not exists (
        select 1 from public.transactions o
        where o.person_id = t.person_id and o.is_opening and not o.is_void
      )
      and not exists (
        select 1 from public.transactions e
        where e.person_id = t.person_id
          and not e.is_void
          and e.id <> t.id
          and (e.transaction_date, e.created_at) < (t.transaction_date, t.created_at)
      )
      and 1 = (
        select count(*) from public.transactions c
        where c.person_id = t.person_id
          and not c.is_void
          and not c.is_opening
          and lower(btrim(coalesce(c.description, ''))) = 'opening balance'
      )
  )
  -- `opening_role` arrived with 0022 and is not nullable while `is_opening` is
  -- true. A row reclassified today is the balance the account opened with,
  -- which is what 0022 backfilled every pre-existing opening row to.
  update public.transactions t set is_opening = true, opening_role = 'balance'
    from candidate c where t.id = c.id;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

do $$
declare
  v_owner   uuid := gen_random_uuid();
  v_legacy  uuid;   -- a person whose opening balance predates the flag
  v_modern  uuid;   -- a person whose opening balance was written properly
  v_id      uuid;
  v_before  bigint;
  v_after   bigint;
  v_amount  bigint;
  v_date    date;
  v_ccy     text;
  v_n       bigint;
  v_page    jsonb;
  v_bal     public.person_balances%rowtype;
  v_txn     uuid;
  v_caught  boolean;
  v_remaining bigint;
  v_legacy_no_opening uuid;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'opening-section@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);
  perform public.update_my_profile('Opening Tester', null, null, 'INR', null);

  -- ---------------------------------------------------------------------------
  -- 1. A pre-flag opening balance is reclassified in place
  --
  -- Written the way a user would have written it before the feature existed: an
  -- ordinary credit, described "Opening Balance", and the oldest thing on the
  -- account.
  -- ---------------------------------------------------------------------------
  v_legacy := (public.create_person('Legacy Larsen', 'person')).id;

  perform public.create_transaction(
    p_person_id => v_legacy, p_type => 'credit', p_amount_minor => 750000,
    p_date => current_date - 200, p_description => 'Opening Balance');

  select id, amount_minor, transaction_date into v_id, v_amount, v_date
  from public.transactions where person_id = v_legacy;

  -- Something later, so "oldest" is a real test rather than a tautology.
  perform public.create_transaction(
    p_person_id => v_legacy, p_type => 'debit', p_amount_minor => 100000,
    p_date => current_date - 10, p_description => 'later entry');

  select count(*) into v_before from public.transactions where person_id = v_legacy;

  perform pg_temp.assert(
    'before the migration the legacy row is an ordinary transaction',
    not (select is_opening from public.transactions where id = v_id));

  v_n := pg_temp.reclassify_openings();

  perform pg_temp.assert('the migration reclassified exactly one row', v_n = 1);

  select count(*) into v_after from public.transactions where person_id = v_legacy;
  perform pg_temp.assert(
    'and created nothing: the row count is unchanged',
    v_after = v_before);

  perform pg_temp.assert(
    'the SAME row now carries the flag, with its id, amount, currency and date intact',
    (select is_opening and amount_minor = v_amount and transaction_date = v_date
            and entered_currency is null
       from public.transactions where id = v_id));

  perform pg_temp.assert(
    'and it is the only opening balance on the account',
    (select count(*) from public.transactions
      where person_id = v_legacy and is_opening and not is_void) = 1);

  -- ---------------------------------------------------------------------------
  -- 2. Idempotent
  -- ---------------------------------------------------------------------------
  v_n := pg_temp.reclassify_openings();
  perform pg_temp.assert('running the migration again reclassifies nothing', v_n = 0);

  select count(*) into v_after from public.transactions where person_id = v_legacy;
  perform pg_temp.assert('and still writes no row', v_after = v_before);

  perform pg_temp.assert(
    'a second run leaves exactly one opening balance, never two',
    (select count(*) from public.transactions
      where person_id = v_legacy and is_opening and not is_void) = 1);

  -- ---------------------------------------------------------------------------
  -- 3. Separated from the regular activity
  -- ---------------------------------------------------------------------------
  v_legacy_no_opening := (public.create_person('Nil Nayar', 'person')).id;

  v_modern := (public.create_person(
    'Modern Mehta', 'person', null, null, null, null, 'INR',
    'they_owe_me', 400000)).id;

  perform public.create_transaction(
    p_person_id => v_modern, p_type => 'credit', p_amount_minor => 100000,
    p_description => 'regular credit');

  v_page := public.person_page(v_modern);

  perform pg_temp.assert(
    'person_page serves the opening balance in its own section',
    v_page -> 'opening' ->> 'transaction_id' is not null
      and (v_page -> 'opening' ->> 'signed_minor')::bigint = 400000
      and v_page -> 'opening' ->> 'ledger_currency' = 'INR');

  perform pg_temp.assert(
    'and no opening row appears in the regular timeline',
    not exists (
      select 1 from jsonb_array_elements(v_page -> 'timeline') e
      where (e ->> 'is_opening')::boolean));

  perform pg_temp.assert(
    'while the regular entry is still there',
    exists (
      select 1 from jsonb_array_elements(v_page -> 'timeline') e
      where e ->> 'note' = 'regular credit'));

  perform pg_temp.assert(
    'timeline_total counts what the timeline holds',
    (v_page ->> 'timeline_total')::int = 1);

  perform pg_temp.assert(
    'and no "Settle this" is offered against an opening balance',
    not exists (
      select 1 from jsonb_array_elements(v_page -> 'open_transactions') e
      where (e ->> 'is_opening')::boolean));

  -- ---------------------------------------------------------------------------
  -- 4. It still counts towards the position
  -- ---------------------------------------------------------------------------
  select * into v_bal from public.person_balances where person_id = v_modern;
  perform pg_temp.assert(
    'the current position is opening + regular entries, to the paisa',
    v_bal.net_balance = 400000 + 100000
      and v_bal.opening_minor = 400000);

  perform pg_temp.assert(
    'and person_page reports the same balance it always did',
    (v_page -> 'balance' ->> 'net_balance')::bigint = 500000);

  -- ---------------------------------------------------------------------------
  -- 5. It cannot be settled as a transaction; the account still can
  -- ---------------------------------------------------------------------------
  select id into v_txn from public.transactions
   where person_id = v_modern and is_opening and not is_void;

  v_caught := false;
  begin
    perform public.create_settlement(
      p_person_id => v_modern, p_amount_minor => 100000,
      p_direction => 'in', p_transaction_id => v_txn);
  exception when others then
    v_caught := true;
  end;
  perform pg_temp.assert(
    'settling an opening balance as an individual transaction is refused',
    v_caught);

  perform pg_temp.assert(
    'and nothing was recorded by the attempt',
    (select count(*) from public.settlements where person_id = v_modern) = 0);

  -- The account as a whole is a different question, and the answer is yes.
  perform public.settle_account(p_person_id => v_modern, p_amount_minor => 50000);

  select * into v_bal from public.person_balances where person_id = v_modern;
  perform pg_temp.assert(
    'settling the account works and retires part of the whole position',
    v_bal.net_balance = 450000 and v_bal.opening_minor = 400000);

  -- ---------------------------------------------------------------------------
  -- 5b. The opening balance has its OWN way of being settled (0021)
  --
  -- Two sections, two settlement paths, one page. What is refused above is the
  -- generic row action; what is offered here is the dedicated one, and it is
  -- the only route by which a settlement may name an opening balance.
  -- ---------------------------------------------------------------------------
  select st.remaining_minor into v_remaining
  from public.transaction_settlement_status(v_modern) st
  where st.transaction_id = v_txn;

  perform pg_temp.assert(
    'the opening section can see how much of itself is left',
    (select o.remaining_minor from public.person_opening o where o.person_id = v_modern)
      = v_remaining);

  perform public.settle_opening_balance(
    p_person_id => v_modern, p_amount_minor => 100000, p_note => 'against the opening');

  perform pg_temp.assert(
    'the dedicated action settles the opening balance itself',
    (select o.settled_minor from public.person_opening o where o.person_id = v_modern) > 0);

  perform pg_temp.assert(
    'and the settlement is recorded against that entry, in the derived direction',
    exists (
      select 1 from public.settlements s
      where s.person_id = v_modern and s.transaction_id = v_txn
        and s.direction = 'in' and not s.is_void));

  select * into v_bal from public.person_balances where person_id = v_modern;
  perform pg_temp.assert(
    'the position falls by exactly what was settled',
    v_bal.net_balance = 350000);

  perform pg_temp.assert(
    'the opening balance itself is untouched — settling is not editing',
    v_bal.opening_minor = 400000);

  -- The exemption does not outlive the call that was granted it.
  v_caught := false;
  begin
    perform public.create_settlement(
      p_person_id => v_modern, p_amount_minor => 1000,
      p_direction => 'in', p_transaction_id => v_txn);
  exception when others then
    v_caught := true;
  end;
  perform pg_temp.assert(
    'and the generic path is refused again immediately afterwards',
    v_caught);

  -- Settling it twice over is refused by the same ceiling every entry has.
  v_caught := false;
  begin
    perform public.settle_opening_balance(
      p_person_id => v_modern, p_amount_minor => 9000000);
  exception when others then
    v_caught := true;
  end;
  perform pg_temp.assert(
    'an opening balance cannot be over-settled', v_caught);

  v_caught := false;
  begin
    perform public.settle_opening_balance(p_person_id => v_legacy_no_opening);
  exception when others then
    v_caught := true;
  end;
  perform pg_temp.assert(
    'and an account with no opening balance has nothing to settle', v_caught);

  -- ---------------------------------------------------------------------------
  -- 6. Replacing one retracts the old
  -- ---------------------------------------------------------------------------
  perform public.set_person_opening_balance(
    p_person_id => v_legacy, p_direction => 'i_owe_them', p_amount_minor => 250000);

  v_page := public.person_page(v_legacy);

  perform pg_temp.assert(
    'the new opening balance is the one in the section',
    (v_page -> 'opening' ->> 'signed_minor')::bigint = -250000);

  perform pg_temp.assert(
    'the replaced one is kept as history, and only there',
    jsonb_array_length(v_page -> 'opening_history') = 1
      and (v_page -> 'opening_history' -> 0 ->> 'amount_minor')::bigint = 750000
      and not exists (
        select 1 from jsonb_array_elements(v_page -> 'timeline') e
        where (e ->> 'is_opening')::boolean));

  perform pg_temp.assert(
    'and there is still exactly one live opening balance',
    (select count(*) from public.transactions
      where person_id = v_legacy and is_opening and not is_void) = 1);

  raise notice '=== 09_opening_balance_section: all assertions passed ===';
end $$;

rollback;
