-- =============================================================================
-- 04_currency.sql — per-person currency, opening balances, conversion
--
-- What is asserted here:
--   1. a person with no currency still reads as the owner's base currency
--   2. a person can be created in another currency, and their balance is
--      denominated in it
--   3. an opening balance lands on the right side of the ledger, is flagged,
--      and there can only be one live one
--   4. a foreign-currency entry stores the original amount, currency and rate,
--      and the account amount the database derived from them
--   5. the conversion respects the decimal exponent, which is the part that
--      goes wrong when a yen meets a rupee
--   6. a historical rate is frozen: moving the cached rate does not move a
--      transaction that was already recorded
--   7. the dashboard aggregates into the base currency and says how many people
--      it could not convert
--   8. restating an account keeps every original amount and stays settleable
--   9. an entry in a foreign currency without a rate is refused, and the ledger
--      is unchanged
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
  v_owner  uuid := gen_random_uuid();
  v_legacy uuid;
  v_ahmed  uuid;
  v_john   uuid;
  v_kenji  uuid;
  v_txn    uuid;
  v_row    public.transactions;
  v_bal    public.person_balances%rowtype;
  v_dash   jsonb;
  v_page   jsonb;
  v_amount bigint;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'currency-test@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);

  -- The workspace is on rupees, as every workspace that predates this feature is.
  perform public.update_my_profile('Currency Tester', null, null, 'INR', null);

  -- ---------------------------------------------------------------------------
  -- 1. Backward compatibility: no currency stored means the base currency.
  -- ---------------------------------------------------------------------------
  v_legacy := (public.create_person('Legacy Person', 'person')).id;

  perform pg_temp.assert(
    'a person created without a currency stores NULL',
    (select currency from public.people where id = v_legacy) is null);
  perform pg_temp.assert(
    'and reads as the base currency',
    (select currency from public.person_balances where person_id = v_legacy) = 'INR');
  perform pg_temp.assert(
    'person_currency() agrees',
    public.person_currency(v_legacy) = 'INR');

  -- ---------------------------------------------------------------------------
  -- 2. A person of their own currency.
  -- ---------------------------------------------------------------------------
  v_ahmed := (public.create_person('Ahmed', 'person', null, null, null, null, 'AED')).id;
  v_john  := (public.create_person('John',  'person', null, null, null, null, 'USD')).id;

  perform pg_temp.assert(
    'a person can be created in another currency',
    (select currency from public.person_balances where person_id = v_ahmed) = 'AED');
  perform pg_temp.assert(
    'and another person can be in a third',
    (select currency from public.person_balances where person_id = v_john) = 'USD');
  perform pg_temp.assert_raises(
    'an unsupported currency is refused',
    'select public.create_person(''Nobody'', ''person'', null, null, null, null, ''XXX'')');

  -- ---------------------------------------------------------------------------
  -- 3. Opening balances (upgrade §3, §4).
  -- ---------------------------------------------------------------------------
  -- "They owe me AED 500" on an account that starts from nothing else.
  perform public.set_person_opening_balance(v_ahmed, 'they_owe_me', 50000);

  select * into v_bal from public.person_balances where person_id = v_ahmed;
  perform pg_temp.assert(
    'an opening balance in their favour is a receivable',
    v_bal.outstanding_receivable = 50000 and v_bal.net_balance = 50000);
  perform pg_temp.assert(
    'and is reported as the opening figure',
    v_bal.opening_minor = 50000);
  perform pg_temp.assert(
    'the row is flagged as an opening balance rather than a transaction',
    (select is_opening from public.transactions
      where person_id = v_ahmed and not is_void) is true);
  perform pg_temp.assert(
    'it is dated when the account was created, not today',
    (select transaction_date from public.transactions where person_id = v_ahmed and not is_void)
      = (select created_at::date from public.people where id = v_ahmed));

  -- The other direction, on another account.
  perform public.set_person_opening_balance(v_john, 'i_owe_them', 20000);
  select * into v_bal from public.person_balances where person_id = v_john;
  perform pg_temp.assert(
    'an opening balance the other way is a payable',
    v_bal.outstanding_payable = 20000 and v_bal.net_balance = -20000);

  -- Replacing one retracts the old rather than editing it.
  perform public.set_person_opening_balance(v_john, 'i_owe_them', 30000);
  perform pg_temp.assert(
    'replacing an opening balance leaves exactly one live opening row',
    (select count(*) from public.transactions
      where person_id = v_john and is_opening and not is_void) = 1);
  perform pg_temp.assert(
    'the replaced one is kept as a retraction',
    (select count(*) from public.transactions
      where person_id = v_john and is_opening and is_void) = 1);
  perform pg_temp.assert(
    'and the balance is the new figure',
    (select net_balance from public.person_balances where person_id = v_john) = -30000);

  -- Clearing it.
  perform public.set_person_opening_balance(v_john, 'none');
  perform pg_temp.assert(
    'an opening balance can be cleared',
    (select net_balance from public.person_balances where person_id = v_john) = 0);

  perform pg_temp.assert_raises(
    'an opening balance without a direction is refused',
    format('select public.set_person_opening_balance(%L, ''sideways'', 1000)', v_john));

  -- ---------------------------------------------------------------------------
  -- 4 & 5. Conversion, and what a minor unit means.
  -- ---------------------------------------------------------------------------
  -- 1 INR = 0.0416 AED, so ₹1,000.00 is AED 41.60.
  perform public.upsert_exchange_rates('INR', '{"AED": 0.0416, "USD": 0.0113}'::jsonb,
                                       current_date, 'test');
  perform public.upsert_exchange_rates('AED', '{"INR": 24.01}'::jsonb, current_date, 'test');

  perform public.create_transaction(
    p_person_id => v_ahmed, p_type => 'credit',
    p_entered_amount_minor => 100000,        -- ₹1,000.00
    p_entered_currency     => 'INR',
    p_exchange_rate_e9     => 41600000,      -- 1 INR = 0.0416 AED
    p_rate_source          => 'test'
  );

  select * into v_row from public.transactions
   where person_id = v_ahmed and not is_opening and not is_void;

  perform pg_temp.assert(
    'the account amount is the converted one',
    v_row.amount_minor = 4160);                                  -- AED 41.60
  perform pg_temp.assert(
    'the original amount is kept',
    v_row.entered_amount_minor = 100000 and v_row.entered_currency = 'INR');
  perform pg_temp.assert(
    'so is the rate, and when it was taken',
    v_row.exchange_rate_e9 = 41600000 and v_row.exchange_rate_at is not null);
  perform pg_temp.assert(
    'and where it came from',
    v_row.exchange_rate_source = 'test');

  -- The yen has no minor unit at all: ¥1,000 is 1000, not 100000.
  v_kenji := (public.create_person('Kenji', 'person', null, null, null, null, 'JPY')).id;
  perform pg_temp.assert(
    'the yen carries no decimals',
    public.currency_decimals('JPY') = 0);

  -- ₹1,000.00 at 1 INR = 1.78 JPY is ¥1,780 — 1780 minor units, not 178000.
  v_amount := public.convert_amount_minor(100000, 'INR', 'JPY', 1780000000);
  perform pg_temp.assert(
    'converting into a zero-decimal currency shifts the exponent', v_amount = 1780);

  -- And back the other way.
  perform pg_temp.assert(
    'and out of one',
    public.convert_amount_minor(1780, 'JPY', 'INR', 561797752) = 100000);

  perform pg_temp.assert(
    'a conversion to the same currency is the identity',
    public.convert_amount_minor(12345, 'INR', 'INR', null) = 12345);

  -- ---------------------------------------------------------------------------
  -- 6. History does not move when the rate does (upgrade §8).
  -- ---------------------------------------------------------------------------
  perform public.upsert_exchange_rates('INR', '{"AED": 0.0500}'::jsonb,
                                       current_date, 'test-moved');

  select * into v_row from public.transactions where id = v_row.id;
  perform pg_temp.assert(
    'a recorded transaction keeps the rate it was recorded at',
    v_row.exchange_rate_e9 = 41600000);
  perform pg_temp.assert(
    'and keeps its amount',
    v_row.amount_minor = 4160);
  perform pg_temp.assert(
    'so the account balance is unchanged by a rate move',
    (select net_balance from public.person_balances where person_id = v_ahmed)
      = 50000 + 4160);

  -- ---------------------------------------------------------------------------
  -- 7. Aggregation into the base currency (upgrade §9).
  -- ---------------------------------------------------------------------------
  select * into v_bal from public.person_balances where person_id = v_ahmed;
  perform pg_temp.assert(
    'the person page reports the base-currency equivalent',
    v_bal.net_balance_base is not null and v_bal.base_currency = 'INR');

  -- No rate has ever been cached for the yen, so Kenji cannot be converted.
  perform public.create_transaction(v_kenji, 'credit', 5000);   -- ¥5,000
  perform pg_temp.assert(
    'a person with no usable rate reports no base equivalent',
    (select net_balance_base from public.person_balances where person_id = v_kenji) is null);

  v_dash := public.dashboard();
  perform pg_temp.assert(
    'the dashboard states the base currency',
    v_dash -> 'summary' ->> 'base_currency' = 'INR');
  perform pg_temp.assert(
    'and counts the people it could not convert',
    (v_dash -> 'summary' ->> 'unconverted_people')::int = 1);
  perform pg_temp.assert(
    'and reports more than one currency in play',
    (v_dash -> 'summary' ->> 'currency_count')::int >= 3);

  v_page := public.person_page(v_ahmed);
  perform pg_temp.assert(
    'the person page carries the account currency',
    v_page ->> 'currency' = 'AED');
  perform pg_temp.assert(
    'and the base currency beside it',
    v_page ->> 'base_currency' = 'INR');
  perform pg_temp.assert(
    'and marks the opening balance in the timeline',
    exists (
      select 1 from jsonb_array_elements(v_page -> 'timeline') e
      where (e ->> 'is_opening')::boolean
    ));

  -- ---------------------------------------------------------------------------
  -- 8. Changing a person's currency affects future entries ONLY (upgrade §1).
  --
  -- This is the correction v1.1.1 exists for. v1.1.0 restated the account --
  -- rewriting amount_minor on every historical row at a confirmed rate. It no
  -- longer does anything of the kind: the ledger denomination is frozen where
  -- it was, every recorded figure stays exactly as recorded, and only the
  -- default for new entries moves.
  -- ---------------------------------------------------------------------------

  -- Photograph the account before the change, so "unchanged" can be asserted
  -- against what was actually there rather than against a remembered literal.
  create temporary table pg_temp_before_switch on commit drop as
    select id, amount_minor, entered_amount_minor, entered_currency,
           exchange_rate_e9, exchange_rate_at, exchange_rate_source, is_void
    from public.transactions where person_id = v_ahmed;

  select net_balance into v_amount from public.person_balances where person_id = v_ahmed;

  perform pg_temp.assert_raises(
    'changing the currency of an account with history needs confirming',
    format('select public.update_person(%L, ''Ahmed'', ''person'', null, null, null, null, ''USD'')',
           v_ahmed));

  perform pg_temp.assert(
    'and nothing moved when it was refused',
    (select currency from public.people where id = v_ahmed) = 'AED'
      and (select ledger_currency from public.people where id = v_ahmed) is null);

  perform public.update_person(
    p_person_id => v_ahmed, p_name => 'Ahmed', p_type => 'person',
    p_currency => 'USD', p_currency_change_confirmed => true);

  -- The point of the whole release: history is byte-for-byte what it was.
  perform pg_temp.assert(
    'not one historical row was rewritten by the currency change',
    not exists (
      select 1 from public.transactions t
      join pg_temp_before_switch b on b.id = t.id
      where t.amount_minor         is distinct from b.amount_minor
         or t.entered_amount_minor is distinct from b.entered_amount_minor
         or t.entered_currency     is distinct from b.entered_currency
         or t.exchange_rate_e9     is distinct from b.exchange_rate_e9
         or t.exchange_rate_at     is distinct from b.exchange_rate_at
         or t.exchange_rate_source is distinct from b.exchange_rate_source
         or t.is_void              is distinct from b.is_void)
    and (select count(*) from public.transactions where person_id = v_ahmed)
      = (select count(*) from pg_temp_before_switch));

  perform pg_temp.assert(
    'the opening balance is still the AED 500 that was entered',
    (select amount_minor from public.transactions
      where person_id = v_ahmed and is_opening and not is_void) = 50000);

  perform pg_temp.assert(
    'the ledger denomination was frozen where it stood',
    (select ledger_currency from public.people where id = v_ahmed) = 'AED'
      and public.person_ledger_currency(v_ahmed) = 'AED');

  perform pg_temp.assert(
    'the default for new entries is the new currency',
    (select currency from public.people where id = v_ahmed) = 'USD'
      and public.person_currency(v_ahmed) = 'USD');

  select * into v_bal from public.person_balances where person_id = v_ahmed;
  perform pg_temp.assert(
    'the balance is unchanged and still reported in the ledger currency',
    v_bal.net_balance = v_amount and v_bal.currency = 'AED');
  perform pg_temp.assert(
    'and the view reports the entry default beside it',
    v_bal.default_currency = 'USD');

  v_page := public.person_page(v_ahmed);
  perform pg_temp.assert(
    'the person page separates the two currencies',
    v_page ->> 'currency' = 'AED' and v_page ->> 'default_currency' = 'USD');

  -- A future entry, in the new default currency, converts into the frozen
  -- ledger and keeps the dollars it was entered in.
  perform public.upsert_exchange_rates('USD', '{"AED": 3.6725}'::jsonb, current_date, 'test');

  perform public.create_transaction(
    p_person_id => v_ahmed, p_type => 'credit',
    p_entered_amount_minor => 10000,        -- USD 100.00
    p_entered_currency     => 'USD',
    p_exchange_rate_e9     => 3672500000,
    p_rate_source          => 'test');

  select * into v_row from public.transactions
  where person_id = v_ahmed and entered_currency = 'USD';

  perform pg_temp.assert(
    'a new entry is stored in the ledger currency',
    v_row.amount_minor = 36725);                     -- USD 100 -> AED 367.25
  perform pg_temp.assert(
    'and keeps the dollars that were actually handed over',
    v_row.entered_amount_minor = 10000
      and v_row.entered_currency = 'USD'
      and v_row.exchange_rate_e9 = 3672500000
      and v_row.exchange_rate_source = 'test');
  perform pg_temp.assert(
    'the balance moved by the converted amount, not the entered one',
    (select net_balance from public.person_balances where person_id = v_ahmed)
      = v_amount + 36725);

  -- Switching a second time moves the default again and leaves the frozen
  -- denomination exactly where it was set the first time.
  perform public.update_person(
    p_person_id => v_ahmed, p_name => 'Ahmed', p_type => 'person',
    p_currency => 'EUR', p_currency_change_confirmed => true);
  perform pg_temp.assert(
    'a second switch does not re-freeze the ledger',
    (select ledger_currency from public.people where id = v_ahmed) = 'AED'
      and (select currency from public.people where id = v_ahmed) = 'EUR');

  -- Restatement is gone, and so is the RPC that performed it.
  perform pg_temp.assert(
    'the restatement RPC no longer exists',
    not exists (
      select 1 from pg_proc where proname = 'restate_person_currency'));

  -- A person with no history changes currency freely, and stays undiverged.
  perform public.update_person(
    p_person_id => v_legacy, p_name => 'Legacy Person', p_type => 'person', p_currency => 'EUR');
  perform pg_temp.assert(
    'an account with no entries changes currency without ceremony',
    (select currency from public.people where id = v_legacy) = 'EUR'
      and (select ledger_currency from public.people where id = v_legacy) is null);
  perform pg_temp.assert(
    'and its ledger simply follows the new currency',
    public.person_ledger_currency(v_legacy) = 'EUR');

  -- ---------------------------------------------------------------------------
  -- 9. A foreign amount with no rate is refused, and nothing is written.
  -- ---------------------------------------------------------------------------
  perform pg_temp.assert_raises(
    'a foreign-currency entry without a rate is refused',
    format($sql$select public.create_transaction(
             p_person_id => %L, p_type => 'credit',
             p_entered_amount_minor => 100000, p_entered_currency => 'INR')$sql$, v_kenji));

  perform pg_temp.assert(
    'and the balance is untouched',
    (select net_balance from public.person_balances where person_id = v_kenji) = 5000);

  perform pg_temp.assert_raises(
    'an unsupported currency cannot be cached as a rate',
    'select public.upsert_exchange_rates(''XXX'', ''{"INR": 1}''::jsonb)');

  perform pg_temp.assert(
    'unknown codes in a rate payload are skipped, not fatal',
    public.upsert_exchange_rates('GBP', '{"INR": 105.5, "ZZZ": 3}'::jsonb, current_date, 'test') = 1);

  raise notice '=== ALL CURRENCY TESTS PASSED ===';
end $$;

rollback;
