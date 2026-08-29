-- =============================================================================
-- 11_cash_in_hand.sql — cash in hand and the opening balance reconcile (0022)
--
-- What this pins:
--
--   1. THE INVARIANT. cash_in_hand_minor + opening_net_minor = net_balance, for
--      every account, after every kind of entry. Nothing is double-counted and
--      nothing is lost between the two figures.
--   2. Cash in hand does not contain the opening balance — not the balance row,
--      not an adjustment to it, not a settlement against it.
--   3. The opening balance is calculated independently, and moves only when
--      something in the opening book moves.
--   4. Opening-balance credit, debit and settlement create NO regular
--      transaction row: they are absent from `timeline`, from
--      `open_transactions`, and from cash in hand.
--   5. Transfers keep behaving exactly as 0020 made them behave.
--   6. INR + USD + AED reconcile: every figure keeps its own denomination and
--      the base-currency totals add up at the cached rate, never a rounded one.
--   7. THE REGRESSION. Editing an opening balance and reloading the person
--      succeeds, the new amount is served, `opening_history` carries the same
--      keys as `opening` (which is what the Flutter client crashed on), no
--      duplicate opening balance exists, and no regular transaction changed.
--
-- Self-contained: creates its own user, asserts, then ROLLS BACK.
--
--   node db/tools/run-sql.mjs test
-- =============================================================================

begin;

-- Deliberately NOT `set constraints all immediate` at the top, unlike the other
-- suites: §5 writes a transfer, and the DEFERRABLE constraint that insists a
-- transfer has exactly two legs would fire after the first one and refuse it.
-- It is forced where it matters instead, and deferral restored, exactly as
-- db/tests/10 does.

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

-- The invariant, as a callable check, so every stage below can re-assert it
-- rather than assert it once and hope.
create or replace function pg_temp.assert_reconciles(p_label text)
returns void language plpgsql as $$
declare v_bad bigint;
begin
  select count(*) into v_bad
  from public.person_balances b
  where b.cash_in_hand_minor + b.opening_net_minor <> b.net_balance;
  if v_bad > 0 then
    raise exception 'FAIL: % — % account(s) do not reconcile', p_label, v_bad;
  end if;
  raise notice 'ok  % (cash_in_hand + opening_net = net_balance)', p_label;
end $$;

do $$
declare
  v_owner    uuid := gen_random_uuid();
  v_inr      uuid;
  v_usd      uuid;
  v_aed      uuid;
  v_plain    uuid;
  v_to       uuid;
  v_bal      public.person_balances%rowtype;
  v_page     jsonb;
  v_dash     jsonb;
  v_open     jsonb;
  v_hist     jsonb;
  v_txn_ids  uuid[];
  v_txn_sig  text;
  v_after    text;
  v_caught   boolean;
  v_count    bigint;
  v_id       uuid;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'cash-in-hand@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);
  perform public.update_my_profile('Cash Tester', null, null, 'INR', null);

  -- Rates this workspace will convert at. Cached, not guessed, and the same
  -- ones every figure below is checked against.
  perform public.upsert_exchange_rates('USD', jsonb_build_object('INR', 88), current_date, 'test');
  perform public.upsert_exchange_rates('AED', jsonb_build_object('INR', 24), current_date, 'test');

  -- ===========================================================================
  -- 1. An account with both halves
  -- ===========================================================================
  v_inr := (public.create_person('Inr Iyer', 'person', null, null, null, null, 'INR')).id;

  -- Opening balance: they owe 5,000.00
  perform public.set_person_opening_balance(
    p_person_id => v_inr, p_direction => 'they_owe_me', p_amount_minor => 500000);

  -- Regular trading: they owe another 1,000.00, we owe them 200.00
  perform public.create_transaction(
    p_person_id => v_inr, p_type => 'credit', p_amount_minor => 100000,
    p_date => current_date, p_description => 'goods');
  perform public.create_transaction(
    p_person_id => v_inr, p_type => 'debit', p_amount_minor => 20000,
    p_date => current_date, p_description => 'refund');

  select * into v_bal from public.person_balances where person_id = v_inr;

  perform pg_temp.assert(
    'cash in hand is the regular position only: 1,000 - 200 = 800',
    v_bal.cash_in_hand_minor = 80000);

  perform pg_temp.assert(
    'the opening balance is calculated independently: 5,000',
    v_bal.opening_net_minor = 500000);

  perform pg_temp.assert(
    'and neither figure contains the other',
    v_bal.cash_in_hand_minor <> v_bal.net_balance
      and v_bal.opening_net_minor <> v_bal.net_balance);

  perform pg_temp.assert_reconciles('an account with both halves');

  -- ===========================================================================
  -- 2. Opening-balance credit and debit create no regular transaction
  -- ===========================================================================
  select array_agg(id order by created_at) into v_txn_ids
  from public.transactions where person_id = v_inr and not is_opening;

  select string_agg(id::text || ':' || amount_minor::text || ':' || type::text
                    || ':' || transaction_date::text, '|' order by created_at)
    into v_txn_sig
  from public.transactions where person_id = v_inr and not is_opening;

  perform public.adjust_opening_balance(
    p_person_id => v_inr, p_type => 'credit', p_amount_minor => 100000,
    p_date => current_date, p_note => 'opening was short');

  select * into v_bal from public.person_balances where person_id = v_inr;

  perform pg_temp.assert(
    'an opening credit moves the opening balance: 5,000 + 1,000 = 6,000',
    v_bal.opening_net_minor = 600000);

  perform pg_temp.assert(
    'and leaves cash in hand exactly where it was',
    v_bal.cash_in_hand_minor = 80000);

  perform public.adjust_opening_balance(
    p_person_id => v_inr, p_type => 'debit', p_amount_minor => 50000,
    p_date => current_date, p_note => 'opening was over');

  select * into v_bal from public.person_balances where person_id = v_inr;

  perform pg_temp.assert(
    'an opening debit moves it back: 6,000 - 500 = 5,500',
    v_bal.opening_net_minor = 550000);

  perform pg_temp.assert(
    'cash in hand is still untouched by either',
    v_bal.cash_in_hand_minor = 80000);

  perform pg_temp.assert_reconciles('after opening credit and debit');

  v_page := public.person_page(v_inr);

  perform pg_temp.assert(
    'no opening-book row reaches the regular timeline',
    not exists (
      select 1 from jsonb_array_elements(v_page -> 'timeline') e
      where (e ->> 'opening_scope')::boolean));

  perform pg_temp.assert(
    'the regular timeline still holds exactly the two trading rows',
    jsonb_array_length(v_page -> 'timeline') = 2
      and (v_page ->> 'timeline_total')::bigint = 2);

  perform pg_temp.assert(
    'the adjustments are in the opening section instead',
    jsonb_array_length(v_page -> 'opening_activity') = 2);

  perform pg_temp.assert(
    'and none of them is offered as a settleable transaction',
    not exists (
      select 1 from jsonb_array_elements(v_page -> 'open_transactions') e
      where (e ->> 'is_opening')::boolean));

  perform pg_temp.assert(
    'the page states both positions itself, and they agree with the view',
    (v_page -> 'regular' ->> 'position')::bigint = v_bal.cash_in_hand_minor
      and (v_page -> 'opening_position' ->> 'position')::bigint = v_bal.opening_net_minor);

  select string_agg(id::text || ':' || amount_minor::text || ':' || type::text
                    || ':' || transaction_date::text, '|' order by created_at)
    into v_after
  from public.transactions where person_id = v_inr and not is_opening;

  perform pg_temp.assert(
    'and not one regular transaction was created, moved or rewritten',
    v_after = v_txn_sig);

  -- ===========================================================================
  -- 3. Settling the opening balance settles the opening balance, and nothing
  --    else
  -- ===========================================================================
  perform public.settle_opening_balance(p_person_id => v_inr, p_amount_minor => 250000);

  select * into v_bal from public.person_balances where person_id = v_inr;

  perform pg_temp.assert(
    'a part-settlement takes 2,500 off the opening balance: 5,500 - 2,500 = 3,000',
    v_bal.opening_net_minor = 300000);

  perform pg_temp.assert(
    'cash in hand did not move: the settlement never touched a regular row',
    v_bal.cash_in_hand_minor = 80000);

  perform pg_temp.assert(
    'and the regular receivable is intact',
    v_bal.regular_receivable = 100000 and v_bal.regular_payable = 20000);

  perform pg_temp.assert_reconciles('after an opening settlement');

  v_page := public.person_page(v_inr);

  perform pg_temp.assert(
    'the opening settlement is in the opening section, not among the transactions',
    exists (
      select 1 from jsonb_array_elements(v_page -> 'opening_activity') e
      where e ->> 'entry_kind' = 'settlement')
    and not exists (
      select 1 from jsonb_array_elements(v_page -> 'timeline') e
      where e ->> 'entry_kind' = 'settlement'));

  perform pg_temp.assert(
    'and settling it in full closes it',
    (public.settle_opening_balance(p_person_id => v_inr) -> 'balance' ->> 'opening_net_minor')::bigint = 0);

  select * into v_bal from public.person_balances where person_id = v_inr;
  perform pg_temp.assert(
    'with cash in hand still exactly 800',
    v_bal.cash_in_hand_minor = 80000 and v_bal.opening_net_minor = 0);

  perform pg_temp.assert_reconciles('after the opening balance is closed');

  -- A closed opening balance refuses a second settlement rather than inventing
  -- a negative one.
  begin
    v_caught := false;
    perform public.settle_opening_balance(p_person_id => v_inr);
  exception when others then
    v_caught := true;
  end;
  perform pg_temp.assert('settling a closed opening balance is refused', v_caught);

  -- ===========================================================================
  -- 4. An account with no opening balance at all
  -- ===========================================================================
  v_plain := (public.create_person('Plain Patel', 'person', null, null, null, null, 'INR')).id;
  perform public.create_transaction(
    p_person_id => v_plain, p_type => 'credit', p_amount_minor => 33300,
    p_date => current_date, p_description => 'one thing');

  select * into v_bal from public.person_balances where person_id = v_plain;

  perform pg_temp.assert(
    'with no opening balance, cash in hand IS the whole position',
    v_bal.cash_in_hand_minor = 33300
      and v_bal.opening_net_minor = 0
      and v_bal.net_balance = 33300);

  begin
    v_caught := false;
    perform public.adjust_opening_balance(
      p_person_id => v_plain, p_type => 'credit', p_amount_minor => 1000);
  exception when others then
    v_caught := true;
  end;
  perform pg_temp.assert(
    'and an opening credit against an account that has none is refused',
    v_caught);

  -- ===========================================================================
  -- 5. Transfers are unchanged
  -- ===========================================================================
  v_to := (public.create_person('Transfer Target', 'person', null, null, null, null, 'INR')).id;

  perform public.create_transfer(
    p_from_person_id => v_plain, p_to_person_id => v_to,
    p_amount_minor => 10000, p_date => current_date, p_note => 'move');

  -- Both legs are written now, so check them here rather than at a commit this
  -- test never reaches; then restore deferral for whatever follows.
  set constraints all immediate;
  set constraints all deferred;

  select * into v_bal from public.person_balances where person_id = v_plain;
  perform pg_temp.assert(
    'a transfer leg is regular activity and lands in cash in hand',
    v_bal.cash_in_hand_minor = 23300 and v_bal.opening_net_minor = 0);

  select * into v_bal from public.person_balances where person_id = v_to;
  perform pg_temp.assert(
    'and so does the other leg, in the opposite direction',
    v_bal.cash_in_hand_minor = 10000 and v_bal.opening_net_minor = 0);

  v_page := public.person_page(v_plain);
  perform pg_temp.assert(
    'the transfer leg is still on the regular timeline, carrying its transfer id',
    exists (
      select 1 from jsonb_array_elements(v_page -> 'timeline') e
      where e ->> 'transfer_id' is not null and e ->> 'transfer_role' = 'source'));

  perform pg_temp.assert_reconciles('after a transfer');

  -- ===========================================================================
  -- 6. INR + USD + AED reconcile at the cached rate
  -- ===========================================================================
  v_usd := (public.create_person('Usd Umar', 'person', null, null, null, null, 'USD')).id;
  v_aed := (public.create_person('Aed Ahmed', 'person', null, null, null, null, 'AED')).id;

  -- USD account: opening $100.00, regular trading $50.00
  perform public.set_person_opening_balance(
    p_person_id => v_usd, p_direction => 'they_owe_me', p_amount_minor => 10000);
  perform public.create_transaction(
    p_person_id => v_usd, p_type => 'credit', p_amount_minor => 5000,
    p_date => current_date, p_description => 'usd goods');

  -- AED account: opening AED 200.00, and we owe them AED 25.00
  perform public.set_person_opening_balance(
    p_person_id => v_aed, p_direction => 'they_owe_me', p_amount_minor => 20000);
  perform public.create_transaction(
    p_person_id => v_aed, p_type => 'debit', p_amount_minor => 2500,
    p_date => current_date, p_description => 'aed refund');

  select * into v_bal from public.person_balances where person_id = v_usd;
  perform pg_temp.assert(
    'the USD account keeps its own denomination in both halves',
    v_bal.currency = 'USD'
      and v_bal.cash_in_hand_minor = 5000
      and v_bal.opening_net_minor = 10000);
  perform pg_temp.assert(
    'and its base equivalents use the cached rate, not a rounded one',
    v_bal.cash_in_hand_base = 440000        -- 50.00 x 88
      and v_bal.opening_net_base = 880000); -- 100.00 x 88

  select * into v_bal from public.person_balances where person_id = v_aed;
  perform pg_temp.assert(
    'the AED account likewise',
    v_bal.currency = 'AED'
      and v_bal.cash_in_hand_minor = -2500
      and v_bal.opening_net_minor = 20000
      and v_bal.cash_in_hand_base = -60000   -- -25.00 x 24
      and v_bal.opening_net_base = 480000);  --  200.00 x 24

  perform pg_temp.assert_reconciles('across INR, USD and AED');

  -- An opening credit in a foreign account keeps the original figure and the
  -- rate it was frozen at, and moves only the opening half.
  perform public.adjust_opening_balance(
    p_person_id => v_usd, p_type => 'credit', p_amount_minor => 1000);

  select * into v_bal from public.person_balances where person_id = v_usd;
  perform pg_temp.assert(
    'a USD opening credit moves the USD opening balance only',
    v_bal.opening_net_minor = 11000 and v_bal.cash_in_hand_minor = 5000);

  -- ---- the dashboard says the same thing ------------------------------------
  v_dash := public.dashboard();

  perform pg_temp.assert(
    'the dashboard reports cash in hand and the opening balance separately',
    v_dash ? 'cash_in_hand' and v_dash ? 'opening');

  perform pg_temp.assert(
    'cash in hand on the dashboard is the sum of the per-person cash positions',
    (v_dash -> 'cash_in_hand' ->> 'position')::bigint =
      (select coalesce(sum(pb.cash_in_hand_base), 0)
       from public.person_balances pb
       where pb.owner_id = v_owner and not pb.is_archived));

  perform pg_temp.assert(
    'the opening total is the sum of the per-person opening positions',
    (v_dash -> 'opening' ->> 'position')::bigint =
      (select coalesce(sum(pb.opening_net_base), 0)
       from public.person_balances pb
       where pb.owner_id = v_owner and not pb.is_archived));

  perform pg_temp.assert(
    'the two dashboard totals add up to the net position, so nothing is double-counted',
    (v_dash -> 'cash_in_hand' ->> 'position')::bigint
      + (v_dash -> 'opening' ->> 'position')::bigint
      = (v_dash -> 'summary' ->> 'net_position')::bigint);

  perform pg_temp.assert(
    'and the cash-in-hand total is strictly smaller than the net position here, '
    'so it demonstrably excludes the opening balances',
    (v_dash -> 'cash_in_hand' ->> 'position')::bigint
      < (v_dash -> 'summary' ->> 'net_position')::bigint);

  -- ===========================================================================
  -- 7. THE REGRESSION: edit an opening balance, then reload the person
  --
  -- This is the exact sequence that broke the desktop client: open a person,
  -- change the opening balance, save, reload. The save always worked; the
  -- reload did not, because `opening_history` — empty until the first edit —
  -- was served with a different key for the transaction id than `opening`, and
  -- one client model parses both.
  -- ===========================================================================
  select array_agg(id order by created_at) into v_txn_ids
  from public.transactions where person_id = v_inr and not is_opening;

  select string_agg(id::text || ':' || amount_minor::text || ':' || type::text, '|'
                    order by created_at)
    into v_txn_sig
  from public.transactions where person_id = v_inr and not is_opening;

  -- 3. change the amount, 4. save
  perform public.set_person_opening_balance(
    p_person_id => v_inr, p_direction => 'they_owe_me', p_amount_minor => 750000);

  -- 5. reload the person
  v_page := public.person_page(v_inr);

  perform pg_temp.assert(
    'the account loads after the edit',
    v_page is not null and v_page -> 'person' ->> 'id' = v_inr::text);

  perform pg_temp.assert(
    'and shows the updated opening balance',
    (v_page -> 'opening' ->> 'amount_minor')::bigint = 750000);

  v_hist := v_page -> 'opening_history';

  perform pg_temp.assert(
    'the replaced opening balance is in the history',
    jsonb_array_length(v_hist) = 1
      and (v_hist -> 0 ->> 'amount_minor')::bigint = 500000);

  -- THE BUG. Every key `opening` carries, `opening_history` must carry too, or
  -- a client that parses both with one model fails on the second.
  v_open := v_page -> 'opening';
  perform pg_temp.assert(
    'and carries a transaction_id, exactly as `opening` does',
    v_hist -> 0 ? 'transaction_id'
      and (v_hist -> 0 ->> 'transaction_id') is not null);

  perform pg_temp.assert(
    'and every other key `opening` has, so one model parses both',
    not exists (
      select 1 from jsonb_object_keys(v_open) k
      where not (v_hist -> 0 ? k)));

  perform pg_temp.assert(
    'no duplicate opening balance was created',
    (select count(*) from public.transactions
      where person_id = v_inr and is_opening and opening_role = 'balance' and not is_void) = 1);

  select string_agg(id::text || ':' || amount_minor::text || ':' || type::text, '|'
                    order by created_at)
    into v_after
  from public.transactions where person_id = v_inr and not is_opening;

  perform pg_temp.assert(
    'and every regular transaction is byte-for-byte what it was',
    v_after = v_txn_sig);

  -- 6. open the person again — the step that used to fail on the second read
  --
  -- The opening position is 2,500, not the 7,500 just entered, and that is
  -- right: this book was settled in full in §3, so 6,000 of settlement is
  -- already recorded against it. Replacing the 5,000 balance with 7,500 leaves
  -- 7,500 + 1,000 adjustment - 6,000 settled = 2,500 outstanding. The figure the
  -- account OPENED with is 7,500 and is asserted above; this is what is left of
  -- the book.
  v_page := public.person_page(v_inr);
  perform pg_temp.assert(
    'reopening the person still works, and still reports both halves',
    (v_page -> 'regular' ->> 'position')::bigint = 80000
      and (v_page -> 'opening_position' ->> 'position')::bigint = 250000);

  perform pg_temp.assert(
    'and cash in hand did not move when the opening balance was rewritten',
    (v_page -> 'regular' ->> 'position')::bigint = 80000
      and (v_page -> 'balance' ->> 'net_balance')::bigint = 80000 + 250000);

  perform pg_temp.assert_reconciles('after the opening balance was edited');

  -- THE SPILL (db/migrations/0023). Replacing a SETTLED opening balance orphans
  -- the settlement that named it: its target is now void, so the whole amount
  -- spills. Before 0023 that spill was account-wide and landed on whatever row
  -- was oldest — frequently an ordinary credit — so editing an opening balance
  -- silently moved cash in hand. It was non-deterministic too: rows written in
  -- one transaction share `created_at`, so the tie-break fell to a random uuid
  -- and this suite passed and failed on alternate runs.
  --
  -- Cash in hand is 800 here and was 800 before the edit. That is the assertion.
  perform pg_temp.assert(
    'an orphaned opening settlement never spills onto a regular transaction',
    (v_page -> 'regular' ->> 'position')::bigint = 80000
      and (v_page -> 'regular' ->> 'receivable')::bigint = 100000
      and (v_page -> 'regular' ->> 'settled')::bigint = 0);

  perform pg_temp.assert(
    'and the regular transactions are still reported as open',
    not exists (
      select 1 from jsonb_array_elements(v_page -> 'timeline') e
      where e ->> 'entry_kind' = 'transaction'
        and coalesce((e ->> 'settled_minor')::bigint, 0) <> 0));

  -- The adjustments made in §2 survive a balance replacement: they are separate
  -- movements of money, not part of the figure that was corrected.
  perform pg_temp.assert(
    'the earlier adjustments were not retracted with the old balance',
    (select count(*) from public.transactions
      where person_id = v_inr and is_opening and opening_role = 'adjustment'
        and not is_void) = 2);

  -- ===========================================================================
  -- 8. Nothing anywhere in the workspace fails to reconcile
  -- ===========================================================================
  perform pg_temp.assert_reconciles('every account in the workspace, finally');

  select count(*) into v_count
  from public.transactions
  where is_opening and opening_role is null;
  perform pg_temp.assert(
    'every opening row carries a role',
    v_count = 0);

  raise notice '=== 11_cash_in_hand: all assertions passed ===';
end $$;

rollback;
