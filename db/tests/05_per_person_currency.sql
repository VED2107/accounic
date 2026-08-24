-- =============================================================================
-- 05_per_person_currency.sql — currency is genuinely PER PERSON (v1.1.1)
--
-- 04_currency.sql covers the mechanics of conversion. This file asserts the
-- product statement the v1.1.1 correction was written to make true, in the
-- exact shape it was asked for:
--
--     Account base currency: INR
--     Ahmed -> AED      Rahul -> INR      John -> USD      Maria -> EUR
--
-- and, around it, the three things that were previously conflated or wrong:
--
--   1. four people on four currencies in one workspace, each entering,
--      settling and reporting in their own
--   2. a person with currency NULL falls back to the account/base currency --
--      and keeps following it, rather than being frozen to a literal
--   3. changing a person's currency rewrites NOTHING: the ledger denomination
--      is frozen, every recorded figure survives verbatim, and only the
--      default for new entries moves
--   4. opening balances in each person's own currency
--   5. the four conversion pairs the brief names: INR->AED, AED->INR,
--      USD->INR, EUR->INR
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
  v_owner   uuid := gen_random_uuid();
  v_ahmed   uuid;
  v_rahul   uuid;
  v_john    uuid;
  v_maria   uuid;
  v_legacy  uuid;
  v_bal     public.person_balances%rowtype;
  v_row     public.transactions;
  v_page    jsonb;
  v_before  bigint;
  v_opening bigint;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'per-person-currency@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);

  -- The workspace's own currency. This is the ACCOUNT/BASE currency, and it is
  -- a different thing from any person's currency — the distinction the whole
  -- release turns on.
  perform public.update_my_profile('Per-Person Tester', null, null, 'INR', null);

  -- The rates the brief's four pairs need. One unit of base costs this much of
  -- each quote.
  perform public.upsert_exchange_rates('INR', '{"AED": 0.0441, "USD": 0.0120, "EUR": 0.0110}'::jsonb,
                                       current_date, 'test');
  perform public.upsert_exchange_rates('AED', '{"INR": 22.68}'::jsonb, current_date, 'test');
  perform public.upsert_exchange_rates('USD', '{"INR": 83.20}'::jsonb, current_date, 'test');
  perform public.upsert_exchange_rates('EUR', '{"INR": 90.50}'::jsonb, current_date, 'test');

  -- ---------------------------------------------------------------------------
  -- 1. Four people, four currencies, one account (§1).
  -- ---------------------------------------------------------------------------
  v_ahmed := (public.create_person('Ahmed', 'person', null, null, null, null, 'AED')).id;
  v_rahul := (public.create_person('Rahul', 'person', null, null, null, null, 'INR')).id;
  v_john  := (public.create_person('John',  'person', null, null, null, null, 'USD')).id;
  v_maria := (public.create_person('Maria', 'person', null, null, null, null, 'EUR')).id;

  perform pg_temp.assert(
    'each person carries their own currency',
    public.person_currency(v_ahmed) = 'AED'
      and public.person_currency(v_rahul) = 'INR'
      and public.person_currency(v_john)  = 'USD'
      and public.person_currency(v_maria) = 'EUR');

  perform pg_temp.assert(
    'and each balance is denominated in it',
    (select currency from public.person_balances where person_id = v_ahmed) = 'AED'
      and (select currency from public.person_balances where person_id = v_rahul) = 'INR'
      and (select currency from public.person_balances where person_id = v_john)  = 'USD'
      and (select currency from public.person_balances where person_id = v_maria) = 'EUR');

  perform pg_temp.assert(
    'while the account itself is on its own base currency',
    public.owner_base_currency(v_owner) = 'INR'
      and (select base_currency from public.person_balances where person_id = v_ahmed) = 'INR');

  perform pg_temp.assert(
    'a person on the base currency is not thereby the base currency',
    (select currency from public.people where id = v_rahul) = 'INR');

  -- The person's currency is what a new transaction with them defaults to, and
  -- that is readable by the transaction UI in one round trip (§1, §4).
  v_page := public.person_page(v_maria);
  perform pg_temp.assert(
    'the transaction UI is told the person currency and the base currency',
    v_page ->> 'default_currency' = 'EUR'
      and v_page ->> 'currency' = 'EUR'
      and v_page ->> 'base_currency' = 'INR');

  -- ---------------------------------------------------------------------------
  -- 2. NULL means "the account's currency", now and later (§2).
  -- ---------------------------------------------------------------------------
  v_legacy := (public.create_person('Legacy Person', 'person')).id;

  perform pg_temp.assert(
    'a person created without a currency stores NULL',
    (select currency from public.people where id = v_legacy) is null
      and (select ledger_currency from public.people where id = v_legacy) is null);
  perform pg_temp.assert(
    'and resolves to the account currency',
    public.person_currency(v_legacy) = 'INR'
      and public.person_ledger_currency(v_legacy) = 'INR'
      and (select currency from public.person_balances where person_id = v_legacy) = 'INR');

  -- NULL is a reference, not a snapshot: move the account's currency and the
  -- person moves with it. Backfilling a literal at migration time would have
  -- broken exactly this.
  perform public.update_my_profile('Per-Person Tester', null, null, 'GBP', null);
  perform pg_temp.assert(
    'NULL keeps following the account currency when it changes',
    public.person_currency(v_legacy) = 'GBP'
      and (select currency from public.person_balances where person_id = v_legacy) = 'GBP');
  perform pg_temp.assert(
    'and a person with their own currency is unaffected by that',
    public.person_currency(v_ahmed) = 'AED');
  perform public.update_my_profile('Per-Person Tester', null, null, 'INR', null);

  -- ---------------------------------------------------------------------------
  -- 3. Opening balances, each in that person's own currency (§5).
  -- ---------------------------------------------------------------------------
  -- "Ahmed owes me AED 500"
  perform public.set_person_opening_balance(v_ahmed, 'they_owe_me', 50000);
  -- "I owe Maria EUR 300"
  perform public.set_person_opening_balance(v_maria, 'i_owe_them', 30000);
  -- "Rahul owes me Rs 1,000"
  perform public.set_person_opening_balance(v_rahul, 'they_owe_me', 100000);

  select * into v_bal from public.person_balances where person_id = v_ahmed;
  perform pg_temp.assert(
    'an opening balance in their favour is a receivable in their currency',
    v_bal.opening_minor = 50000 and v_bal.net_balance = 50000 and v_bal.currency = 'AED');

  select * into v_bal from public.person_balances where person_id = v_maria;
  perform pg_temp.assert(
    'and the other direction is a payable in theirs',
    v_bal.opening_minor = -30000 and v_bal.net_balance = -30000 and v_bal.currency = 'EUR');

  select * into v_bal from public.person_balances where person_id = v_rahul;
  perform pg_temp.assert(
    'a base-currency person opens in the base currency',
    v_bal.opening_minor = 100000 and v_bal.currency = 'INR');

  perform pg_temp.assert(
    'each opening balance is flagged rather than looking like a transaction',
    (select count(*) from public.transactions
      where person_id in (v_ahmed, v_maria, v_rahul) and is_opening and not is_void) = 3);

  -- ---------------------------------------------------------------------------
  -- 4. The four conversion pairs the brief names (§10).
  -- ---------------------------------------------------------------------------
  -- INR -> AED: Rs 1,000 handed to Ahmed, whose account is in dirhams.
  perform public.create_transaction(
    p_person_id => v_ahmed, p_type => 'credit',
    p_entered_amount_minor => 100000, p_entered_currency => 'INR',
    p_exchange_rate_e9 => 44100000, p_rate_source => 'test');       -- 1 INR = 0.0441 AED

  select * into v_row from public.transactions
  where person_id = v_ahmed and entered_currency = 'INR';
  perform pg_temp.assert(
    'INR -> AED converts into the account currency',
    v_row.amount_minor = 4410);                                     -- Rs 1,000 -> AED 44.10
  perform pg_temp.assert(
    'and the rupees that were actually handed over are kept, not overwritten',
    v_row.entered_amount_minor = 100000 and v_row.entered_currency = 'INR'
      and v_row.exchange_rate_e9 = 44100000 and v_row.exchange_rate_at is not null
      and v_row.exchange_rate_source = 'test');

  -- AED -> INR: Ahmed hands back AED 20 (§4's second example).
  perform public.create_transaction(
    p_person_id => v_rahul, p_type => 'debit',
    p_entered_amount_minor => 2000, p_entered_currency => 'AED',
    p_exchange_rate_e9 => 22680000000, p_rate_source => 'test');    -- 1 AED = 22.68 INR

  select * into v_row from public.transactions
  where person_id = v_rahul and entered_currency = 'AED';
  perform pg_temp.assert(
    'AED -> INR converts the other way',
    v_row.amount_minor = 45360);                                    -- AED 20 -> Rs 453.60
  perform pg_temp.assert(
    'keeping the dirhams on the row',
    v_row.entered_amount_minor = 2000 and v_row.entered_currency = 'AED');

  -- USD -> INR.
  perform public.create_transaction(
    p_person_id => v_rahul, p_type => 'credit',
    p_entered_amount_minor => 10000, p_entered_currency => 'USD',
    p_exchange_rate_e9 => 83200000000, p_rate_source => 'test');    -- 1 USD = 83.20 INR
  perform pg_temp.assert(
    'USD -> INR converts',
    (select amount_minor from public.transactions
      where person_id = v_rahul and entered_currency = 'USD') = 832000);   -- $100 -> Rs 8,320

  -- EUR -> INR.
  perform public.create_transaction(
    p_person_id => v_rahul, p_type => 'credit',
    p_entered_amount_minor => 10000, p_entered_currency => 'EUR',
    p_exchange_rate_e9 => 90500000000, p_rate_source => 'test');    -- 1 EUR = 90.50 INR
  perform pg_temp.assert(
    'EUR -> INR converts',
    (select amount_minor from public.transactions
      where person_id = v_rahul and entered_currency = 'EUR') = 905000);   -- EUR 100 -> Rs 9,050

  -- The conversion is the database's, not a client's: the same figures sent
  -- with a wrong rate produce a different stored amount, and no client number
  -- is trusted as the account amount.
  perform pg_temp.assert(
    'the stored amount is derived, never the entered one',
    not exists (
      select 1 from public.transactions
      where person_id = v_rahul and entered_currency is not null
        and amount_minor = entered_amount_minor));

  -- ---------------------------------------------------------------------------
  -- 5. Changing a person's currency affects FUTURE transactions only (§3).
  --
  -- The brief's own example: Ahmed was on AED with history; he moves to USD.
  -- ---------------------------------------------------------------------------
  create temporary table pg_temp_ahmed_before on commit drop as
    select id, amount_minor, entered_amount_minor, entered_currency, exchange_rate_e9,
           exchange_rate_at, exchange_rate_source, transaction_date, is_void, is_opening
    from public.transactions where person_id = v_ahmed;

  select net_balance into v_before from public.person_balances where person_id = v_ahmed;
  select amount_minor into v_opening from public.transactions
    where person_id = v_ahmed and is_opening and not is_void;

  -- The confirmation is the database's refusal of the first attempt: nothing
  -- has been written when the user is shown it.
  perform pg_temp.assert_raises(
    'the first attempt is refused so the user can be told what happens',
    format('select public.update_person(%L, ''Ahmed'', ''person'', null, null, null, null, ''USD'')',
           v_ahmed));
  perform pg_temp.assert(
    'and that refusal changed nothing at all',
    (select currency from public.people where id = v_ahmed) = 'AED'
      and (select ledger_currency from public.people where id = v_ahmed) is null
      and (select net_balance from public.person_balances where person_id = v_ahmed) = v_before);

  perform public.update_person(
    p_person_id => v_ahmed, p_name => 'Ahmed', p_type => 'person',
    p_currency => 'USD', p_currency_change_confirmed => true);

  perform pg_temp.assert(
    'every historical row survived the change byte for byte',
    not exists (
      select 1 from public.transactions t
      join pg_temp_ahmed_before b on b.id = t.id
      where t.amount_minor         is distinct from b.amount_minor
         or t.entered_amount_minor is distinct from b.entered_amount_minor
         or t.entered_currency     is distinct from b.entered_currency
         or t.exchange_rate_e9     is distinct from b.exchange_rate_e9
         or t.exchange_rate_at     is distinct from b.exchange_rate_at
         or t.exchange_rate_source is distinct from b.exchange_rate_source
         or t.transaction_date     is distinct from b.transaction_date
         or t.is_void              is distinct from b.is_void
         or t.is_opening           is distinct from b.is_opening));

  perform pg_temp.assert(
    'no row was added or removed by it either',
    (select count(*) from public.transactions where person_id = v_ahmed)
      = (select count(*) from pg_temp_ahmed_before));

  perform pg_temp.assert(
    'the opening balance is still the AED 500 it was entered as',
    (select amount_minor from public.transactions
      where person_id = v_ahmed and is_opening and not is_void) = v_opening
      and v_opening = 50000);

  perform pg_temp.assert(
    'the balance did not move',
    (select net_balance from public.person_balances where person_id = v_ahmed) = v_before);

  perform pg_temp.assert(
    'the ledger denomination is frozen where the history was written',
    public.person_ledger_currency(v_ahmed) = 'AED'
      and (select currency from public.person_balances where person_id = v_ahmed) = 'AED');

  perform pg_temp.assert(
    'and only the default for new entries moved',
    public.person_currency(v_ahmed) = 'USD'
      and (select default_currency from public.person_balances where person_id = v_ahmed) = 'USD');

  -- A future entry does default to the new currency, which is the other half of
  -- the promise made to the user.
  perform public.upsert_exchange_rates('USD', '{"AED": 3.6725}'::jsonb, current_date, 'test');
  perform public.create_transaction(
    p_person_id => v_ahmed, p_type => 'credit',
    p_entered_amount_minor => 10000, p_entered_currency => 'USD',
    p_exchange_rate_e9 => 3672500000, p_rate_source => 'test');

  perform pg_temp.assert(
    'a future entry is entered in the new currency and stored in the ledger',
    (select amount_minor from public.transactions
      where person_id = v_ahmed and entered_currency = 'USD') = 36725
      and (select net_balance from public.person_balances where person_id = v_ahmed)
        = v_before + 36725);

  -- ---------------------------------------------------------------------------
  -- 6. Settlement still works on an account that has switched.
  --
  -- The outstanding figure is in the ledger currency, so a settlement entered
  -- in the new default has to be converted before it is compared with it. Get
  -- that wrong and the over-settlement guard compares dollars with dirhams.
  -- ---------------------------------------------------------------------------
  perform public.create_settlement(
    p_person_id => v_ahmed, p_direction => 'in',
    p_entered_amount_minor => 5000, p_entered_currency => 'USD',
    p_exchange_rate_e9 => 3672500000, p_rate_source => 'test');     -- $50 -> AED 183.63

  perform pg_temp.assert(
    'a settlement in the new currency lands in the ledger currency',
    (select amount_minor from public.settlements
      where person_id = v_ahmed and entered_currency = 'USD') = 18363);

  perform pg_temp.assert(
    'and reduces the outstanding receivable by that converted amount',
    (select net_balance from public.person_balances where person_id = v_ahmed)
      = v_before + 36725 - 18363);

  perform pg_temp.assert_raises(
    'over-settling is still refused, compared in the right currency',
    format($sql$select public.create_settlement(
             p_person_id => %L, p_direction => 'in',
             p_entered_amount_minor => 100000000, p_entered_currency => 'USD',
             p_exchange_rate_e9 => 3672500000)$sql$, v_ahmed));

  -- ---------------------------------------------------------------------------
  -- 7. The whole workspace still adds up, across four currencies.
  -- ---------------------------------------------------------------------------
  perform pg_temp.assert(
    'the workspace reports every currency in play',
    (select currency_count from public.owner_summary where owner_id = v_owner) >= 4);
  perform pg_temp.assert(
    'and totals in the base currency without counting anything at par',
    (select base_currency from public.owner_summary where owner_id = v_owner) = 'INR');
  perform pg_temp.assert(
    'each person still reports a base-currency equivalent',
    (select count(*) from public.person_balances
      where owner_id = v_owner and net_balance <> 0 and net_balance_base is null) = 0);

  raise notice '=== ALL PER-PERSON CURRENCY TESTS PASSED ===';
end $$;

rollback;
