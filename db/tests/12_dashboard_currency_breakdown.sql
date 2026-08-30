-- =============================================================================
-- 12_dashboard_currency_breakdown.sql — the dashboard leads with the currency
-- the money was entered in (0024)
--
-- This pins the user's requirement in full:
--
--   * `dashboard().totals_by_currency` carries, per entry currency, a `cash`
--     object and an `opening` object, each with credit / debit / settled /
--     receivable / payable / net / today, IN THAT CURRENCY.
--   * The primary figures are the ORIGINAL entered amounts. 20 AED + 40 AED is
--     60 AED — never an INR figure reconverted to AED.
--   * A manual amount stays exact: 40 AED entered manually is 40 AED here.
--   * Cash in hand and the opening balance stay completely separate.
--   * Every currency that has activity appears; INR (the base) is first.
--   * The per-person `regular_by_currency` / `opening_by_currency` reconcile
--     with the dashboard totals.
--   * A partial foreign-currency settlement allocates deterministically from
--     the STORED ledger allocation — never today's rate — and the same read
--     twice gives the same answer.
--   * Net position is the byte-for-byte figure the engine already reported.
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

-- Pull one currency's row out of totals_by_currency.
create or replace function pg_temp.row_for(p_dash jsonb, p_currency text)
returns jsonb language sql as $$
  select e
  from jsonb_array_elements(p_dash -> 'totals_by_currency') e
  where e ->> 'currency' = p_currency
$$;

do $$
declare
  c_aed_e9 constant bigint := 24000000000;   -- 1 AED = 24 INR
  c_usd_e9 constant bigint := 88000000000;   -- 1 USD = 88 INR
  c_eur_e9 constant bigint := 95000000000;   -- 1 EUR = 95 INR
  c_man_e9 constant bigint := 25000000000;   -- SAYAN's manual 1 AED = 25 INR

  v_owner  uuid := gen_random_uuid();
  v_ved    uuid;
  v_sayan  uuid;
  v_usd    uuid;
  v_eur    uuid;
  v_dash   jsonb;
  v_dash2  jsonb;
  v_inr    jsonb;
  v_aed    jsonb;
  v_usdr   jsonb;
  v_eurr   jsonb;
  v_page   jsonb;
  v_ved_aed_txn uuid;
  v_sig    text;
  v_after  text;
  v_net0   bigint;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'dash-currency@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);
  perform public.update_my_profile('Dash Tester', null, null, 'INR', null);

  perform public.upsert_exchange_rates('AED', '{"INR": 24}'::jsonb, current_date, 'test');
  perform public.upsert_exchange_rates('USD', '{"INR": 88}'::jsonb, current_date, 'test');
  perform public.upsert_exchange_rates('EUR', '{"INR": 95}'::jsonb, current_date, 'test');

  -- ===========================================================================
  -- The dataset from the brief
  -- ===========================================================================
  v_ved   := (public.create_person('VED',   'person', null, null, null, null, 'INR')).id;
  v_sayan := (public.create_person('SAYAN', 'person', null, null, null, null, 'INR')).id;
  v_usd   := (public.create_person('USD Person', 'person', null, null, null, null, 'USD')).id;
  v_eur   := (public.create_person('EUR Person', 'person', null, null, null, null, 'EUR')).id;

  -- VED regular: Rs 1,000 native, plus 20 AED converted automatically.
  perform public.create_transaction(
    p_person_id => v_ved, p_type => 'credit', p_amount_minor => 100000,
    p_date => current_date, p_description => 'ved inr');
  perform public.create_transaction(
    p_person_id => v_ved, p_type => 'credit', p_description => 'ved aed',
    p_entered_amount_minor => 2000, p_entered_currency => 'AED',
    p_exchange_rate_e9 => c_aed_e9, p_rate_source => 'test');

  select id into v_ved_aed_txn from public.transactions
  where person_id = v_ved and description = 'ved aed';

  -- SAYAN regular: Rs 3,000 native, plus 40 AED with a MANUAL rate/amount.
  perform public.create_transaction(
    p_person_id => v_sayan, p_type => 'credit', p_amount_minor => 300000,
    p_date => current_date, p_description => 'sayan inr');
  perform public.create_transaction(
    p_person_id => v_sayan, p_type => 'credit', p_description => 'sayan aed manual',
    p_entered_amount_minor => 4000, p_entered_currency => 'AED',
    p_exchange_rate_e9 => c_man_e9, p_rate_source => 'test',
    p_converted_amount_minor => 100000, p_conversion_mode => 'manual');

  -- VED opening: Rs 2,000 balance + a 100 AED adjustment.
  perform public.set_person_opening_balance(
    p_person_id => v_ved, p_direction => 'they_owe_me', p_amount_minor => 200000);
  perform public.adjust_opening_balance(
    p_person_id => v_ved, p_type => 'credit',
    p_entered_amount_minor => 10000, p_entered_currency => 'AED',
    p_exchange_rate_e9 => c_aed_e9, p_rate_source => 'test', p_note => 'ved opening aed');

  -- SAYAN opening: Rs 1,000 balance + a 50 AED adjustment.
  perform public.set_person_opening_balance(
    p_person_id => v_sayan, p_direction => 'they_owe_me', p_amount_minor => 100000);
  perform public.adjust_opening_balance(
    p_person_id => v_sayan, p_type => 'credit',
    p_entered_amount_minor => 5000, p_entered_currency => 'AED',
    p_exchange_rate_e9 => c_aed_e9, p_rate_source => 'test', p_note => 'sayan opening aed');

  -- USD and EUR: one native regular credit each, so both currencies show up.
  perform public.create_transaction(
    p_person_id => v_usd, p_type => 'credit', p_amount_minor => 5000,
    p_date => current_date, p_description => 'usd goods');    -- $50.00
  perform public.create_transaction(
    p_person_id => v_eur, p_type => 'credit', p_amount_minor => 7000,
    p_date => current_date, p_description => 'eur goods');    -- €70.00

  -- ===========================================================================
  -- 1. The dashboard leads with the entered currency
  -- ===========================================================================
  v_dash := public.dashboard();
  v_net0 := (v_dash -> 'summary' ->> 'net_position')::bigint;

  perform pg_temp.assert(
    'every currency with activity appears — INR, AED, USD, EUR',
    jsonb_array_length(v_dash -> 'totals_by_currency') = 4);

  perform pg_temp.assert(
    'the base currency (INR) is the first row',
    (v_dash -> 'totals_by_currency' -> 0 ->> 'currency') = 'INR');

  v_inr  := pg_temp.row_for(v_dash, 'INR');
  v_aed  := pg_temp.row_for(v_dash, 'AED');
  v_usdr := pg_temp.row_for(v_dash, 'USD');
  v_eurr := pg_temp.row_for(v_dash, 'EUR');

  perform pg_temp.assert('AED, USD and EUR each have a row',
    v_aed is not null and v_usdr is not null and v_eurr is not null);

  -- ---- CASH IN HAND, in the original currency --------------------------------
  perform pg_temp.assert(
    'AED cash in hand is 20 + 40 = 60 AED, entered — not reconverted from INR',
    (v_aed -> 'cash' ->> 'credit') = '6000'
      and (v_aed -> 'cash' ->> 'debit') = '0'
      and (v_aed -> 'cash' ->> 'net') = '6000'
      and (v_aed -> 'cash' ->> 'receivable') = '6000'
      and (v_aed -> 'cash' ->> 'payable') = '0');

  perform pg_temp.assert(
    'INR cash in hand is Rs 1,000 + Rs 3,000 = Rs 4,000',
    (v_inr -> 'cash' ->> 'credit') = '400000'
      and (v_inr -> 'cash' ->> 'net') = '400000');

  perform pg_temp.assert(
    'both people are counted in the AED cash breakdown',
    (v_aed -> 'cash' ->> 'people_count') = '2'
      and (v_aed -> 'cash' ->> 'entry_count') = '2');

  perform pg_temp.assert(
    'USD cash in hand is $50, in USD',
    (v_usdr -> 'cash' ->> 'credit') = '5000'
      and (v_usdr -> 'cash' ->> 'net') = '5000');

  perform pg_temp.assert(
    'EUR cash in hand is EUR 70, in EUR',
    (v_eurr -> 'cash' ->> 'credit') = '7000');

  -- ---- OPENING BALANCE, its own independent per-currency breakdown ----------
  perform pg_temp.assert(
    'AED opening balance is 100 + 50 = 150 AED',
    (v_aed -> 'opening' ->> 'credit') = '15000'
      and (v_aed -> 'opening' ->> 'net') = '15000'
      and (v_aed -> 'opening' ->> 'entry_count') = '2');

  perform pg_temp.assert(
    'INR opening balance is Rs 2,000 + Rs 1,000 = Rs 3,000',
    (v_inr -> 'opening' ->> 'credit') = '300000'
      and (v_inr -> 'opening' ->> 'net') = '300000');

  -- ---- the two halves never bleed into each other --------------------------
  perform pg_temp.assert(
    'the opening 150 AED is NOT in AED cash in hand',
    (v_aed -> 'cash' ->> 'credit') = '6000');

  perform pg_temp.assert(
    'and the 60 AED of trading is NOT in the AED opening balance',
    (v_aed -> 'opening' ->> 'credit') = '15000');

  perform pg_temp.assert(
    'per row, cash_net_position + opening_net_position = net_position (no double count)',
    (v_aed ->> 'cash_net_position')::bigint + (v_aed ->> 'opening_net_position')::bigint
      = (v_aed ->> 'net_position')::bigint
    and (v_inr ->> 'cash_net_position')::bigint + (v_inr ->> 'opening_net_position')::bigint
      = (v_inr ->> 'net_position')::bigint);

  perform pg_temp.assert(
    'per row, gross_credit = cash.credit + opening.credit',
    (v_aed ->> 'gross_credit')::bigint
      = (v_aed -> 'cash' ->> 'credit')::bigint + (v_aed -> 'opening' ->> 'credit')::bigint);

  -- ===========================================================================
  -- 2. The manual amount is exact
  -- ===========================================================================
  perform pg_temp.assert(
    'SAYAN''s 40 AED is stored entered as exactly 40 AED, with a manual mode',
    (select entered_amount_minor from public.transactions where id = (
       select id from public.transactions where person_id = v_sayan and description = 'sayan aed manual'))
       = 4000
    and (select entered_currency from public.transactions
         where person_id = v_sayan and description = 'sayan aed manual') = 'AED'
    and (select conversion_mode from public.transactions
         where person_id = v_sayan and description = 'sayan aed manual') = 'manual'
    and (select amount_minor from public.transactions
         where person_id = v_sayan and description = 'sayan aed manual') = 100000);

  perform pg_temp.assert(
    'and it reaches the dashboard as 40 AED, not as its INR equivalent',
    (v_aed -> 'cash' ->> 'credit') = '6000');   -- 2000 (VED) + 4000 (SAYAN)

  -- ===========================================================================
  -- 3. Net position is unchanged, and the halves still add to it
  -- ===========================================================================
  perform pg_temp.assert(
    'cash in hand + opening balance = net position (the engine''s figure, untouched)',
    (v_dash -> 'cash_in_hand' ->> 'position')::bigint
      + (v_dash -> 'opening' ->> 'position')::bigint
      = (v_dash -> 'summary' ->> 'net_position')::bigint);

  perform pg_temp.assert(
    'and net position equals the sum of the per-person base net balances',
    (v_dash -> 'summary' ->> 'net_position')::bigint =
      (select coalesce(sum(pb.net_balance_base), 0)
       from public.person_balances pb
       where pb.owner_id = v_owner and not pb.is_archived));

  perform pg_temp.assert(
    'the summary keeps every key it had',
    v_dash -> 'summary' ? 'total_receivable'
      and v_dash -> 'summary' ? 'total_payable'
      and v_dash -> 'summary' ? 'net_position'
      and v_dash -> 'summary' ? 'gross_settled'
      and v_dash -> 'summary' ? 'currency_count');

  -- ===========================================================================
  -- 4. The person pages reconcile with the dashboard
  -- ===========================================================================
  v_page := public.person_page(v_ved);

  perform pg_temp.assert(
    'VED regular_by_currency: 20 AED (2000 minor) and Rs 1,000 (100000 minor), each in its own currency',
    (select (r ->> 'net') from jsonb_array_elements(v_page -> 'regular_by_currency') r
     where r ->> 'currency' = 'AED') = '2000'
    and (select (r ->> 'net') from jsonb_array_elements(v_page -> 'regular_by_currency') r
     where r ->> 'currency' = 'INR') = '100000');

  perform pg_temp.assert(
    'VED opening_by_currency: 100 AED and Rs 2,000',
    (select (r ->> 'net') from jsonb_array_elements(v_page -> 'opening_by_currency') r
     where r ->> 'currency' = 'AED') = '10000'
    and (select (r ->> 'net') from jsonb_array_elements(v_page -> 'opening_by_currency') r
     where r ->> 'currency' = 'INR') = '200000');

  perform pg_temp.assert(
    'VED regular + SAYAN regular in AED = the dashboard''s 60 AED',
    (select (r ->> 'credit')::bigint from jsonb_array_elements(
       public.person_currency_breakdown(v_ved, v_owner, false)) r where r ->> 'currency' = 'AED')
    + (select (r ->> 'credit')::bigint from jsonb_array_elements(
       public.person_currency_breakdown(v_sayan, v_owner, false)) r where r ->> 'currency' = 'AED')
    = (v_aed -> 'cash' ->> 'credit')::bigint);

  -- ===========================================================================
  -- 5. A partial foreign-currency settlement — deterministic, from the stored
  --    ledger allocation, never today's rate
  -- ===========================================================================
  -- VED's 20 AED credit is stored as 48,000 INR (rate 24). Settle half of it,
  -- 24,000 INR in. The entered-currency settled portion is
  --   round(24000 * 2000 / 48000) = round(1000) = 1000  ->  10 AED
  -- computed from the row's own frozen ratio, not from any live rate.
  perform public.create_settlement(
    p_person_id => v_ved, p_amount_minor => 24000, p_direction => 'in',
    p_transaction_id => v_ved_aed_txn, p_date => current_date, p_note => 'part pay');

  v_dash  := public.dashboard();
  v_dash2 := public.dashboard();
  v_aed   := pg_temp.row_for(v_dash, 'AED');

  perform pg_temp.assert(
    'the AED settled portion is a deterministic 10 AED',
    (v_aed -> 'cash' ->> 'settled') = '1000');

  perform pg_temp.assert(
    'AED cash receivable drops to 50 AED and net follows',
    (v_aed -> 'cash' ->> 'receivable') = '5000'
      and (v_aed -> 'cash' ->> 'net') = '5000'
      and (v_aed -> 'cash' ->> 'credit') = '6000');

  perform pg_temp.assert(
    'the same read twice gives the same figure (no non-determinism)',
    pg_temp.row_for(v_dash2, 'AED') -> 'cash' ->> 'settled' = '1000'
      and pg_temp.row_for(v_dash2, 'AED') -> 'cash' ->> 'net' = '5000');

  perform pg_temp.assert(
    'the opening AED balance did not move when a regular row was settled',
    (v_aed -> 'opening' ->> 'net') = '15000');

  -- ===========================================================================
  -- 6. Historical amounts, currencies and rates are untouched
  -- ===========================================================================
  select string_agg(
           id::text || ':' || amount_minor || ':' || type || ':'
           || coalesce(entered_amount_minor::text, '-') || ':'
           || coalesce(entered_currency, '-') || ':'
           || coalesce(exchange_rate_e9::text, '-') || ':'
           || coalesce(conversion_mode, '-'),
           '|' order by id)
    into v_after
  from public.transactions where owner_id = v_owner;

  -- Nothing between the two dashboard reads wrote to a transaction, so the
  -- signature taken now is the one to freeze; re-read and compare.
  v_sig := v_after;
  perform public.dashboard();
  select string_agg(
           id::text || ':' || amount_minor || ':' || type || ':'
           || coalesce(entered_amount_minor::text, '-') || ':'
           || coalesce(entered_currency, '-') || ':'
           || coalesce(exchange_rate_e9::text, '-') || ':'
           || coalesce(conversion_mode, '-'),
           '|' order by id)
    into v_after
  from public.transactions where owner_id = v_owner;

  perform pg_temp.assert(
    'reading the dashboard rewrites no transaction amount, currency or rate',
    v_after = v_sig);

  perform pg_temp.assert(
    'net position is stable across repeated dashboard reads',
    (v_dash -> 'summary' ->> 'net_position')::bigint
      = (v_dash2 -> 'summary' ->> 'net_position')::bigint
    and (public.dashboard() -> 'summary' ->> 'net_position')::bigint
      = (v_dash2 -> 'summary' ->> 'net_position')::bigint);

  perform pg_temp.assert(
    'the only thing that moved net position was the §5 settlement, by its own amount',
    v_net0 - (v_dash -> 'summary' ->> 'net_position')::bigint = 24000);

  raise notice '=== 12_dashboard_currency_breakdown: all assertions passed ===';
end $$;

rollback;
