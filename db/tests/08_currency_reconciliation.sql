-- =============================================================================
-- 08_currency_reconciliation.sql — the conversion arithmetic, and the two
-- invariants every screen depends on (v1.5.0)
--
-- The report this file answers:
--
--     400 AED · displayed rate 1 AED = ₹25.9842 · displayed ₹10,393.69
--     400 × 25.9842 = ₹10,393.68
--
-- The stored rate is 25.984225, not 25.9842. Multiplying the full rate and
-- rounding once, at the end, gives ₹10,393.69 — the figure shown. Multiplying
-- the four-decimal DISPLAY rate gives ₹10,393.68. §1 pins that: the database
-- must produce the first, and the second must be reachable only by rounding the
-- rate first, which nothing in this product does.
--
-- Then the two invariants:
--
--     person INR balance   = that person's net, converted once
--     dashboard INR total  = sum of every person's INR balance
--
-- with three people, four currencies, an opening balance, a settlement, a
-- manual rate and a manual amount all in the mix.
--
-- Self-contained: creates its own user, asserts, then ROLLS BACK. Not one row
-- of anybody's real ledger is read or written.
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

do $$
declare
  -- 1 AED = 25.984225 INR, 1 USD = 95.427612 INR. Both chosen because their
  -- fourth decimal is not their last: rounding the rate for display changes the
  -- answer, which is the whole point of this file.
  c_aed_inr_e9 constant bigint := 25984225000;
  c_usd_inr_e9 constant bigint := 95427612000;

  v_owner   uuid := gen_random_uuid();
  v_a       uuid;   -- kept in AED
  v_b       uuid;   -- kept in INR
  v_c       uuid;   -- kept in USD
  v_row     public.transactions;
  v_bal     public.person_balances%rowtype;
  v_sum     public.owner_summary%rowtype;
  v_txn     uuid;
  v_dash    jsonb;
  v_people  bigint;
  v_display bigint;
  v_before  bigint;
  v_source  text;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'currency-reconciliation@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);
  perform public.update_my_profile('Reconciliation Tester', null, null, 'INR', null);

  perform public.upsert_exchange_rates(
    'AED', jsonb_build_object('INR', 25.984225, 'USD', 0.272257), current_date, 'test');
  perform public.upsert_exchange_rates(
    'USD', jsonb_build_object('INR', 95.427612, 'AED', 3.6725), current_date, 'test');

  -- ---------------------------------------------------------------------------
  -- 1. The reported figure, and the figure a rounded rate would have given
  -- ---------------------------------------------------------------------------
  perform pg_temp.assert(
    '400 AED at the full stored rate is ₹10,393.69',
    public.convert_amount_minor(40000, 'AED', 'INR', c_aed_inr_e9) = 1039369);

  v_display := public.convert_amount_minor(40000, 'AED', 'INR', 25984200000);
  perform pg_temp.assert(
    'and ₹10,393.68 is reachable only by rounding the rate to four decimals first',
    v_display = 1039368 and v_display <> 1039369);

  perform pg_temp.assert(
    '$40 at the full stored rate is ₹3,817.10',
    public.convert_amount_minor(4000, 'USD', 'INR', c_usd_inr_e9) = 381710);

  -- Rounding happens once, on the final amount. Ten separate $40 entries
  -- therefore need not equal one $400 entry to the paisa — but one amount must
  -- always convert to one figure, whoever asks.
  perform pg_temp.assert(
    'the same amount and rate always give the same figure',
    public.convert_amount_minor(4000, 'USD', 'INR', c_usd_inr_e9)
      = public.convert_for_owner(v_owner, 4000, 'USD', 'INR'));

  perform pg_temp.assert(
    'a zero-decimal currency shifts the exponent rather than the value',
    public.convert_amount_minor(100000, 'INR', 'JPY', 1780000000) = 1780);

  perform pg_temp.assert(
    'no rate is "not known", never zero',
    public.convert_for_owner(v_owner, 40000, 'AED', 'BRL') is null);

  perform pg_temp.assert(
    'a same-currency conversion is the identity, with or without a rate',
    public.convert_amount_minor(12345, 'INR', 'INR', null) = 12345);

  -- ---------------------------------------------------------------------------
  -- 2. Three people, four currencies
  --
  --   A (AED): opening 400 AED, then $40 USD out
  --   B (INR): ₹5,000 in
  --   C (USD): $100 in, half of it settled
  -- ---------------------------------------------------------------------------
  v_a := (public.create_person('Aisha', 'person', null, null, null, null, 'AED')).id;
  v_b := (public.create_person('Bhavna', 'person', null, null, null, null, 'INR')).id;
  v_c := (public.create_person('Chen', 'person', null, null, null, null, 'USD')).id;

  perform public.set_person_opening_balance(
    p_person_id => v_a, p_direction => 'they_owe_me', p_amount_minor => 40000);

  select * into v_row from public.transactions where person_id = v_a and is_opening;
  perform pg_temp.assert(
    'an opening balance in the account currency is stored verbatim',
    v_row.amount_minor = 40000 and v_row.entered_currency is null);

  -- $40 against a dirham account: entered in USD, stored in AED.
  perform public.create_transaction(
    p_person_id => v_a, p_type => 'debit', p_description => 'usd entry',
    p_entered_amount_minor => 4000, p_entered_currency => 'USD',
    p_exchange_rate_e9 => 3672500000, p_rate_source => 'test');

  select * into v_row from public.transactions
  where person_id = v_a and description = 'usd entry';
  perform pg_temp.assert(
    'the original amount and currency survive the conversion',
    v_row.entered_amount_minor = 4000 and v_row.entered_currency = 'USD'
      and v_row.exchange_rate_e9 = 3672500000);
  perform pg_temp.assert(
    'and the ledger figure is what that rate says, to the account currency',
    v_row.amount_minor = 14690);                          -- $40 × 3.6725 = AED 146.90

  perform public.create_transaction(
    p_person_id => v_b, p_type => 'credit', p_description => 'inr entry',
    p_amount_minor => 500000);

  perform public.create_transaction(
    p_person_id => v_c, p_type => 'credit', p_description => 'usd account entry',
    p_amount_minor => 10000);
  select id into v_txn from public.transactions where person_id = v_c;
  perform public.create_settlement(
    p_person_id => v_c, p_amount_minor => 5000, p_direction => 'in',
    p_transaction_id => v_txn);

  -- ---------------------------------------------------------------------------
  -- 3. Person balance = that person's own entries, in their own denomination,
  --    converted once into the base currency.
  -- ---------------------------------------------------------------------------
  select * into v_bal from public.person_balances where person_id = v_a;
  perform pg_temp.assert(
    'A is denominated in AED and nets opening minus the converted USD entry',
    v_bal.currency = 'AED' and v_bal.net_balance = 40000 - 14690);
  perform pg_temp.assert(
    'and A''s base figure is that net converted once, at the cached rate',
    v_bal.net_balance_base
      = public.convert_amount_minor(40000 - 14690, 'AED', 'INR', c_aed_inr_e9));

  select * into v_bal from public.person_balances where person_id = v_b;
  perform pg_temp.assert(
    'a base-currency account needs no conversion at all',
    v_bal.currency = 'INR' and v_bal.net_balance = 500000
      and v_bal.net_balance_base = 500000);

  select * into v_bal from public.person_balances where person_id = v_c;
  perform pg_temp.assert(
    'a settlement retires part of the position in the account''s own currency',
    v_bal.currency = 'USD' and v_bal.net_balance = 5000
      and v_bal.net_balance_base
        = public.convert_amount_minor(5000, 'USD', 'INR', c_usd_inr_e9));

  -- ---------------------------------------------------------------------------
  -- 4. THE INVARIANT: the dashboard total is the sum of the person balances.
  --
  -- Not the sum of the raw amounts — those are dirhams, dollars and rupees and
  -- adding them would be meaningless. Each person's net is converted once and
  -- the converted figures are summed, which is the only order that reconciles.
  -- ---------------------------------------------------------------------------
  select * into v_sum from public.owner_summary where owner_id = v_owner;

  select coalesce(sum(pb.net_balance_base), 0) into v_people
  from public.person_balances pb
  where pb.owner_id = v_owner and not pb.is_archived;

  perform pg_temp.assert(
    'dashboard net position = the sum of every person''s INR balance, exactly',
    v_sum.net_position = v_people);

  perform pg_temp.assert(
    'receivable and payable split that same total and nothing else',
    v_sum.total_receivable - v_sum.total_payable = v_sum.net_position);

  perform pg_temp.assert(
    'and no currency was dropped on the way',
    v_sum.currency_count = 3 and v_sum.unconverted_people = 0);

  v_dash := public.dashboard(10, 10);
  perform pg_temp.assert(
    'dashboard() reports the same consolidated figure it computes from',
    (v_dash -> 'summary' ->> 'net_position')::bigint = v_people);
  perform pg_temp.assert(
    'and states the workspace currency it is consolidated into',
    v_dash ->> 'base_currency' = 'INR');

  -- Every by-currency row is one currency's own total plus the base equivalent
  -- of that single-currency sum. Nothing is ever added across currencies.
  perform pg_temp.assert(
    'totals_by_currency groups by the currency each entry was made in',
    (select count(*) from jsonb_array_elements(v_dash -> 'totals_by_currency')) = 3);

  perform pg_temp.assert(
    'the USD row carries the dollars that were typed, not their conversion',
    (select (r ->> 'gross_credit')::bigint
       from jsonb_array_elements(v_dash -> 'totals_by_currency') r
      where r ->> 'currency' = 'USD') = 10000);

  -- ---------------------------------------------------------------------------
  -- 5. The activity rows carry all three figures, so a screen never converts.
  -- ---------------------------------------------------------------------------
  perform pg_temp.assert(
    'an activity row states what was entered, in what, and what it is worth',
    (select (r ->> 'entry_amount_minor')::bigint = 4000
             and r ->> 'entry_currency' = 'USD'
             and (r ->> 'amount_minor')::bigint = 14690
             and r ->> 'currency' = 'AED'
             and (r ->> 'amount_base_minor')::bigint
                   = public.convert_amount_minor(14690, 'AED', 'INR', c_aed_inr_e9)
             and r ->> 'base_currency' = 'INR'
       from jsonb_array_elements(v_dash -> 'recent_activity') r
      where r ->> 'note' = 'usd entry'));

  perform pg_temp.assert(
    'and says where its rate came from (0018)',
    (select r ->> 'exchange_rate_source' = 'test'
       from jsonb_array_elements(v_dash -> 'recent_activity') r
      where r ->> 'note' = 'usd entry'));

  perform pg_temp.assert(
    'person_page() timeline rows carry the same three figures (0018)',
    (select (r ->> 'entry_amount_minor')::bigint = 4000
             and r ->> 'entry_currency' = 'USD'
             and (r ->> 'amount_minor')::bigint = 14690
             and (r ->> 'amount_base_minor')::bigint
                   = public.convert_amount_minor(14690, 'AED', 'INR', c_aed_inr_e9)
       from jsonb_array_elements(public.person_page(v_a, 30, 0) -> 'timeline') r
      where r ->> 'note' = 'usd entry'));

  -- ---------------------------------------------------------------------------
  -- 6. A rate a human typed
  --
  -- Stored like any other rate, marked by its provenance, and never touched
  -- again by the market.
  -- ---------------------------------------------------------------------------
  perform public.create_transaction(
    p_person_id => v_b, p_type => 'credit', p_description => 'manual rate',
    p_entered_amount_minor => 4000, p_entered_currency => 'USD',
    p_exchange_rate_e9 => 96500000000, p_rate_source => 'manual-rate');

  select * into v_row from public.transactions
  where person_id = v_b and description = 'manual rate';

  perform pg_temp.assert(
    'a typed rate is used exactly as typed',
    v_row.exchange_rate_e9 = 96500000000 and v_row.amount_minor = 386000);
  perform pg_temp.assert(
    'and the row says a human chose it',
    public.rate_is_manual(v_row.exchange_rate_source));
  perform pg_temp.assert(
    'while a fetched rate does not',
    not public.rate_is_manual('test') and not public.rate_is_manual(null));

  v_before := v_row.amount_minor;

  -- The market moves. Nothing that was already written moves with it.
  perform public.upsert_exchange_rates(
    'USD', jsonb_build_object('INR', 110.5), current_date, 'test-later');

  select * into v_row from public.transactions
  where person_id = v_b and description = 'manual rate';
  perform pg_temp.assert(
    'a later automatic rate does not touch the manual one, or its amount',
    v_row.exchange_rate_e9 = 96500000000 and v_row.amount_minor = v_before);

  select * into v_row from public.transactions
  where person_id = v_a and description = 'usd entry';
  perform pg_temp.assert(
    'nor does it restate an ordinary historical entry',
    v_row.amount_minor = 14690 and v_row.exchange_rate_e9 = 3672500000);

  -- ---------------------------------------------------------------------------
  -- 7. A manual AMOUNT is still a different thing from a manual RATE, and the
  --    two compose: this row is at a typed rate AND says what really changed
  --    hands.
  -- ---------------------------------------------------------------------------
  perform public.create_transaction(
    p_person_id => v_b, p_type => 'credit', p_description => 'both',
    p_entered_amount_minor => 4000, p_entered_currency => 'USD',
    p_exchange_rate_e9 => 96500000000, p_rate_source => 'manual-rate',
    p_converted_amount_minor => 385000, p_conversion_mode => 'manual');

  select * into v_row from public.transactions where person_id = v_b and description = 'both';
  perform pg_temp.assert(
    'the ledger takes what changed hands, and keeps what the typed rate said',
    v_row.amount_minor = 385000 and v_row.auto_converted_amount_minor = 386000
      and v_row.conversion_mode = 'manual'
      and public.rate_is_manual(v_row.exchange_rate_source));

  -- ---------------------------------------------------------------------------
  -- 8. And the invariant still holds with all of that in the ledger.
  -- ---------------------------------------------------------------------------
  select * into v_sum from public.owner_summary where owner_id = v_owner;
  select coalesce(sum(pb.net_balance_base), 0) into v_people
  from public.person_balances pb
  where pb.owner_id = v_owner and not pb.is_archived;

  perform pg_temp.assert(
    'dashboard = sum of person balances, after manual rates and manual amounts',
    v_sum.net_position = v_people);

  select * into v_bal from public.person_balances where person_id = v_b;
  perform pg_temp.assert(
    'B''s balance is the sum of B''s own rows and nothing else',
    v_bal.net_balance = 500000 + 386000 + 385000);

  -- ---------------------------------------------------------------------------
  -- 9. Historical rows: every converted row carries a rate, always.
  --
  -- This is the check 0018's migration makes before it will run. Asserting it
  -- here means a future write path that forgets the rate fails a test rather
  -- than a migration.
  -- ---------------------------------------------------------------------------
  perform pg_temp.assert(
    'no converted transaction exists without a stored rate',
    not exists (select 1 from public.transactions
                 where entered_currency is not null and exchange_rate_e9 is null));
  perform pg_temp.assert(
    'no converted settlement exists without a stored rate',
    not exists (select 1 from public.settlements
                 where entered_currency is not null and exchange_rate_e9 is null));

  raise notice '=== 08_currency_reconciliation: all assertions passed ===';
end $$;

rollback;
