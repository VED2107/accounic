-- =============================================================================
-- 06_manual_conversion.sql — the actual converted amount (v1.1.2)
--
-- The brief's example, kept as the spine of this file:
--
--     Ahmed's account is in AED. Rs 1,000 is handed over.
--     The rate says   AED 44.20.
--     What was given is AED 43.00.
--
-- Both figures are facts, and this file asserts that both survive: the ledger
-- takes the money that moved, and the market figure stays beside it as the
-- audit reference. Everything else here is a way of that going wrong —
-- overriding and then editing, switching back, a manual figure that happens to
-- equal the automatic one, and a v1.1.1 client that has never heard of any of
-- it.
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
  v_owner    uuid := gen_random_uuid();
  v_ahmed    uuid;
  v_rahul    uuid;
  v_legacy   uuid;
  v_row      public.transactions;
  v_set      public.settlements;
  v_bal      public.person_balances%rowtype;
  v_txn_id   uuid;
  v_hist_id  uuid;
  v_hist_amt bigint;
  v_hist_mode text;
  v_page     jsonb;
  v_item     jsonb;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'manual-conversion@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);
  perform public.update_my_profile('Manual Conversion Tester', null, null, 'INR', null);

  -- 1 INR = 0.0442 AED, which is the brief's Rs 1,000 -> AED 44.20.
  perform public.upsert_exchange_rates('INR', '{"AED": 0.0442}'::jsonb, current_date, 'test');
  perform public.upsert_exchange_rates('AED', '{"INR": 22.62}'::jsonb, current_date, 'test');

  v_ahmed := (public.create_person('Ahmed', 'person', null, null, null, null, 'AED')).id;
  v_rahul := (public.create_person('Rahul', 'person', null, null, null, null, 'INR')).id;

  -- ---------------------------------------------------------------------------
  -- 1. Automatic conversion — unchanged, and now says so on the row.
  -- ---------------------------------------------------------------------------
  perform public.create_transaction(
    p_person_id => v_ahmed, p_type => 'credit', p_description => 'automatic',
    p_entered_amount_minor => 100000, p_entered_currency => 'INR',
    p_exchange_rate_e9 => 44200000, p_rate_source => 'test');

  select * into v_row from public.transactions
  where person_id = v_ahmed and description = 'automatic';

  perform pg_temp.assert(
    'automatic conversion still records what the rate says',
    v_row.amount_minor = 4420);                                  -- Rs 1,000 -> AED 44.20
  perform pg_temp.assert(
    'and labels itself automatic',
    v_row.conversion_mode = 'automatic');
  perform pg_temp.assert(
    'with no reference copy, because amount_minor IS the automatic figure',
    v_row.auto_converted_amount_minor is null);
  perform pg_temp.assert(
    'the rupees handed over and the rate are still kept verbatim',
    v_row.entered_amount_minor = 100000 and v_row.entered_currency = 'INR'
      and v_row.exchange_rate_e9 = 44200000);

  -- ---------------------------------------------------------------------------
  -- 2. A manual converted amount — the brief's case.
  -- ---------------------------------------------------------------------------
  perform public.create_transaction(
    p_person_id => v_ahmed, p_type => 'credit', p_description => 'manual',
    p_entered_amount_minor => 100000, p_entered_currency => 'INR',
    p_exchange_rate_e9 => 44200000, p_rate_source => 'test',
    p_converted_amount_minor => 4300, p_conversion_mode => 'manual');

  select * into v_row from public.transactions
  where person_id = v_ahmed and description = 'manual';

  perform pg_temp.assert(
    'the ledger takes the money that actually changed hands',
    v_row.amount_minor = 4300);                                  -- AED 43.00
  perform pg_temp.assert(
    'and keeps what the rate said, as the audit reference',
    v_row.auto_converted_amount_minor = 4420);                   -- AED 44.20
  perform pg_temp.assert(
    'the row says which of the two figures it is',
    v_row.conversion_mode = 'manual');
  perform pg_temp.assert(
    'the entered amount, currency and rate all survive the override',
    v_row.entered_amount_minor = 100000 and v_row.entered_currency = 'INR'
      and v_row.exchange_rate_e9 = 44200000 and v_row.exchange_rate_at is not null
      and v_row.exchange_rate_source = 'test');

  -- ---------------------------------------------------------------------------
  -- 3. Manual differing from automatic moves the balance, and only by the
  --    difference. This is the point of the feature: the balance is what was
  --    exchanged, not what was quoted.
  -- ---------------------------------------------------------------------------
  select * into v_bal from public.person_balances where person_id = v_ahmed;
  perform pg_temp.assert(
    'the balance is the sum of the automatic row and the manual one',
    v_bal.net_balance = 4420 + 4300 and v_bal.currency = 'AED');
  perform pg_temp.assert(
    'the automatic figure never reaches the balance',
    v_bal.net_balance <> 4420 + 4420);

  -- ---------------------------------------------------------------------------
  -- 4. Manual EQUAL to automatic is still manual.
  --
  -- Collapsing it back to 'automatic' would be a lie about a number the user
  -- looked at and confirmed — and would make the row silently re-derivable at
  -- some other rate later.
  -- ---------------------------------------------------------------------------
  perform public.create_transaction(
    p_person_id => v_ahmed, p_type => 'credit', p_description => 'manual-equal',
    p_entered_amount_minor => 100000, p_entered_currency => 'INR',
    p_exchange_rate_e9 => 44200000, p_rate_source => 'test',
    p_converted_amount_minor => 4420, p_conversion_mode => 'manual');

  select * into v_row from public.transactions
  where person_id = v_ahmed and description = 'manual-equal';
  perform pg_temp.assert(
    'a manual figure equal to the automatic one is still recorded as manual',
    v_row.conversion_mode = 'manual' and v_row.amount_minor = 4420
      and v_row.auto_converted_amount_minor = 4420);

  -- ---------------------------------------------------------------------------
  -- 5. Switching manual -> automatic recomputes from the rate on the row.
  -- ---------------------------------------------------------------------------
  select id into v_txn_id from public.transactions
  where person_id = v_ahmed and description = 'manual';

  perform public.update_transaction(
    p_transaction_id => v_txn_id, p_type => 'credit', p_description => 'manual',
    p_entered_amount_minor => 100000, p_entered_currency => 'INR',
    p_exchange_rate_e9 => 44200000, p_rate_source => 'test',
    p_conversion_mode => 'automatic');

  select * into v_row from public.transactions where id = v_txn_id;
  perform pg_temp.assert(
    'switching back to automatic restores the rate-derived amount',
    v_row.amount_minor = 4420 and v_row.conversion_mode = 'automatic');
  perform pg_temp.assert(
    'and drops the reference copy, which is now the amount itself',
    v_row.auto_converted_amount_minor is null);

  -- ... and back to manual again, so the rest of the file has one to edit.
  perform public.update_transaction(
    p_transaction_id => v_txn_id, p_type => 'credit', p_description => 'manual',
    p_entered_amount_minor => 100000, p_entered_currency => 'INR',
    p_exchange_rate_e9 => 44200000, p_rate_source => 'test',
    p_converted_amount_minor => 4300, p_conversion_mode => 'manual');

  -- ---------------------------------------------------------------------------
  -- 6. Editing a manually overridden transaction preserves the override.
  --
  -- The failure this guards is precise: an edit that says nothing about
  -- currency — changing the note, the date, the direction — must not quietly
  -- restate the row at the stored rate and move the balance by AED 1.20.
  -- ---------------------------------------------------------------------------
  perform public.update_transaction(
    p_transaction_id => v_txn_id, p_type => 'credit',
    p_description => 'manual, note edited');

  select * into v_row from public.transactions where id = v_txn_id;
  perform pg_temp.assert(
    'editing the note leaves a manual amount exactly where it was',
    v_row.amount_minor = 4300 and v_row.conversion_mode = 'manual'
      and v_row.auto_converted_amount_minor = 4420);
  perform pg_temp.assert(
    'and leaves the entered figure and rate alone too',
    v_row.entered_amount_minor = 100000 and v_row.entered_currency = 'INR'
      and v_row.exchange_rate_e9 = 44200000);
  perform pg_temp.assert(
    'the note itself did change',
    v_row.description = 'manual, note edited');

  -- Overriding the override: a second actual amount replaces the first, and the
  -- market reference is recomputed from the rate sent with it.
  perform public.update_transaction(
    p_transaction_id => v_txn_id, p_type => 'credit', p_description => 'manual, corrected',
    p_entered_amount_minor => 100000, p_entered_currency => 'INR',
    p_exchange_rate_e9 => 44200000, p_rate_source => 'test',
    p_converted_amount_minor => 4350, p_conversion_mode => 'manual');

  select * into v_row from public.transactions where id = v_txn_id;
  perform pg_temp.assert(
    'a corrected actual amount replaces the previous one',
    v_row.amount_minor = 4350 and v_row.auto_converted_amount_minor = 4420);

  -- Restating the row in the account currency outright drops the conversion,
  -- because there is no longer an entered figure for a mode to describe.
  perform public.create_transaction(
    p_person_id => v_ahmed, p_type => 'credit', p_description => 'to-restate',
    p_entered_amount_minor => 100000, p_entered_currency => 'INR',
    p_exchange_rate_e9 => 44200000, p_rate_source => 'test',
    p_converted_amount_minor => 4300, p_conversion_mode => 'manual');
  select id into v_hist_id from public.transactions
  where person_id = v_ahmed and description = 'to-restate';

  perform public.update_transaction(
    p_transaction_id => v_hist_id, p_type => 'credit',
    p_amount_minor => 5000, p_description => 'to-restate');

  select * into v_row from public.transactions where id = v_hist_id;
  perform pg_temp.assert(
    'restating in the account currency clears the whole conversion, mode included',
    v_row.amount_minor = 5000 and v_row.conversion_mode is null
      and v_row.auto_converted_amount_minor is null
      and v_row.entered_currency is null and v_row.exchange_rate_e9 is null);

  -- ---------------------------------------------------------------------------
  -- 7. Historical rows are untouched by any of this.
  --
  -- Two halves: a pre-0014 row (mode NULL, which the feed reads as automatic),
  -- and any row at all being left alone while its neighbours are edited.
  -- ---------------------------------------------------------------------------
  select id, amount_minor into v_hist_id, v_hist_amt
  from public.transactions where person_id = v_ahmed and description = 'automatic';

  -- Fake a v1.1.1 row: the mode column as it was before this migration existed.
  update public.transactions set conversion_mode = null where id = v_hist_id;

  perform pg_temp.assert(
    'a pre-0014 converted row is legal with no mode stored',
    (select conversion_mode from public.transactions where id = v_hist_id) is null);
  perform pg_temp.assert(
    'and the feed reports it as the automatic conversion it was',
    (select conversion_mode from public.activity_feed where id = v_hist_id) = 'automatic');
  perform pg_temp.assert(
    'its amount did not move',
    (select amount_minor from public.transactions where id = v_hist_id) = v_hist_amt);

  -- Editing an unrelated row does not disturb it.
  perform public.update_transaction(
    p_transaction_id => v_txn_id, p_type => 'credit', p_description => 'manual, again');
  select amount_minor, conversion_mode into v_hist_amt, v_hist_mode
  from public.transactions where id = v_hist_id;
  perform pg_temp.assert(
    'editing one row leaves the history beside it exactly as it was',
    v_hist_amt = 4420 and v_hist_mode is null);

  -- ---------------------------------------------------------------------------
  -- 8. A v1.1.1 client keeps working (requirement 9).
  --
  -- Neither new argument named: the RPC behaves exactly as it did before this
  -- migration, which is what keeps an un-updated APK on somebody's phone from
  -- breaking the day this ships.
  -- ---------------------------------------------------------------------------
  perform public.create_transaction(
    v_ahmed, 'credit', null, current_date, 'v1.1.1 client',
    100000, 'INR', 44200000, null, 'test');

  select * into v_row from public.transactions
  where person_id = v_ahmed and description = 'v1.1.1 client';
  perform pg_temp.assert(
    'a v1.1.1-shaped call converts automatically, as it always did',
    v_row.amount_minor = 4420 and v_row.conversion_mode = 'automatic'
      and v_row.auto_converted_amount_minor is null);

  -- And a v1.0.7-shaped call, with no currency arguments at all.
  perform public.create_transaction(v_rahul, 'credit', 250000, current_date, 'plain');
  select * into v_row from public.transactions
  where person_id = v_rahul and description = 'plain';
  perform pg_temp.assert(
    'a same-currency entry carries no conversion and no mode',
    v_row.amount_minor = 250000 and v_row.conversion_mode is null
      and v_row.entered_currency is null and v_row.auto_converted_amount_minor is null);

  -- ---------------------------------------------------------------------------
  -- 9. Opening balances take an override too.
  -- ---------------------------------------------------------------------------
  perform public.set_person_opening_balance(
    p_person_id => v_ahmed, p_direction => 'they_owe_me',
    p_entered_amount_minor => 100000, p_entered_currency => 'INR',
    p_rate_e9 => 44200000, p_rate_source => 'test',
    p_converted_amount_minor => 4300, p_conversion_mode => 'manual');

  select * into v_row from public.transactions
  where person_id = v_ahmed and is_opening and not is_void;
  perform pg_temp.assert(
    'an opening balance records the actual converted amount',
    v_row.amount_minor = 4300 and v_row.conversion_mode = 'manual'
      and v_row.auto_converted_amount_minor = 4420);

  -- Created with the person, in one call, the way the person form sends it.
  v_legacy := (public.create_person(
    p_name => 'Opening Override', p_type => 'person', p_currency => 'AED',
    p_opening_direction => 'they_owe_me',
    p_opening_entered_minor => 100000, p_opening_entered_currency => 'INR',
    p_opening_rate_e9 => 44200000, p_opening_rate_source => 'test',
    p_opening_converted_minor => 4300, p_opening_conversion_mode => 'manual')).id;

  select * into v_row from public.transactions
  where person_id = v_legacy and is_opening and not is_void;
  perform pg_temp.assert(
    'create_person forwards the override to the opening balance',
    v_row.amount_minor = 4300 and v_row.conversion_mode = 'manual'
      and v_row.auto_converted_amount_minor = 4420);

  -- ---------------------------------------------------------------------------
  -- 10. Settlements take an override, and the guard reads the actual amount.
  -- ---------------------------------------------------------------------------
  select outstanding_receivable into v_hist_amt
  from public.person_balances where person_id = v_ahmed;

  perform public.create_settlement(
    p_person_id => v_ahmed, p_direction => 'in',
    p_entered_amount_minor => 100000, p_entered_currency => 'INR',
    p_exchange_rate_e9 => 44200000, p_rate_source => 'test',
    p_converted_amount_minor => 4300, p_conversion_mode => 'manual',
    p_note => 'manual settlement');

  select * into v_set from public.settlements
  where person_id = v_ahmed and note = 'manual settlement';
  perform pg_temp.assert(
    'a settlement settles what actually changed hands',
    v_set.amount_minor = 4300 and v_set.conversion_mode = 'manual'
      and v_set.auto_converted_amount_minor = 4420);
  perform pg_temp.assert(
    'and the outstanding figure moves by that, not by the rate figure',
    (select outstanding_receivable from public.person_balances where person_id = v_ahmed)
      = v_hist_amt - 4300);

  -- The over-settlement guard compares the ACTUAL amount with what is left. An
  -- override large enough to exceed it is refused, in the ledger currency.
  perform pg_temp.assert_raises(
    'an override that exceeds the outstanding amount is refused',
    format($sql$select public.create_settlement(
             p_person_id => %L, p_direction => 'in',
             p_entered_amount_minor => 100000, p_entered_currency => 'INR',
             p_exchange_rate_e9 => 44200000,
             p_converted_amount_minor => 99999999, p_conversion_mode => 'manual')$sql$,
           v_ahmed));

  -- ---------------------------------------------------------------------------
  -- 11. The rules around the override itself.
  -- ---------------------------------------------------------------------------
  perform pg_temp.assert_raises(
    'manual mode without an actual amount is refused',
    format($sql$select public.create_transaction(
             p_person_id => %L, p_type => 'credit',
             p_entered_amount_minor => 100000, p_entered_currency => 'INR',
             p_exchange_rate_e9 => 44200000, p_conversion_mode => 'manual')$sql$,
           v_ahmed));

  perform pg_temp.assert_raises(
    'an actual amount of zero is refused rather than treated as no override',
    format($sql$select public.create_transaction(
             p_person_id => %L, p_type => 'credit',
             p_entered_amount_minor => 100000, p_entered_currency => 'INR',
             p_exchange_rate_e9 => 44200000,
             p_converted_amount_minor => 0, p_conversion_mode => 'manual')$sql$,
           v_ahmed));

  perform pg_temp.assert_raises(
    'a mode that is neither word is refused',
    format($sql$select public.create_transaction(
             p_person_id => %L, p_type => 'credit',
             p_entered_amount_minor => 100000, p_entered_currency => 'INR',
             p_exchange_rate_e9 => 44200000, p_conversion_mode => 'approximately')$sql$,
           v_ahmed));

  perform pg_temp.assert_raises(
    'a manual row cannot be written straight into the table without its reference',
    format($sql$update public.transactions
             set conversion_mode = 'manual', auto_converted_amount_minor = null
             where id = %L$sql$, v_txn_id));

  perform pg_temp.assert_raises(
    'and a mode cannot be claimed on a row that was never converted',
    format($sql$update public.transactions set conversion_mode = 'automatic'
             where person_id = %L and description = 'plain'$sql$, v_rahul));

  -- An override sent against a same-currency entry is ignored, not refused: the
  -- two figures would be the same number, and refusing would break a client
  -- that sends the field unconditionally.
  perform public.create_transaction(
    p_person_id => v_rahul, p_type => 'credit', p_description => 'same-currency override',
    p_amount_minor => 100000, p_converted_amount_minor => 999, p_conversion_mode => 'manual');
  select * into v_row from public.transactions
  where person_id = v_rahul and description = 'same-currency override';
  perform pg_temp.assert(
    'an override on a same-currency entry is ignored, not applied',
    v_row.amount_minor = 100000 and v_row.conversion_mode is null
      and v_row.auto_converted_amount_minor is null);

  -- ---------------------------------------------------------------------------
  -- 12. The clients can read all of it back in one call.
  -- ---------------------------------------------------------------------------
  v_page := public.person_page(v_ahmed);
  select value into v_item
  from jsonb_array_elements(v_page -> 'timeline')
  where value ->> 'id' = v_txn_id::text;

  perform pg_temp.assert(
    'person_page carries the mode and the automatic reference on the timeline',
    v_item ->> 'conversion_mode' = 'manual'
      and (v_item ->> 'auto_converted_amount_minor')::bigint = 4420
      and (v_item ->> 'amount_minor')::bigint = 4350
      and (v_item ->> 'entered_amount_minor')::bigint = 100000
      and v_item ->> 'entered_currency' = 'INR');

  v_page := public.activity_page(60);
  select value into v_item
  from jsonb_array_elements(v_page -> 'items')
  where value ->> 'id' = v_txn_id::text;
  perform pg_temp.assert(
    'and so does the activity feed',
    v_item ->> 'conversion_mode' = 'manual'
      and (v_item ->> 'auto_converted_amount_minor')::bigint = 4420);

  v_page := public.dashboard(50, 20);
  select value into v_item
  from jsonb_array_elements(v_page -> 'recent_activity')
  where value ->> 'id' = v_txn_id::text;
  perform pg_temp.assert(
    'and the dashboard',
    v_item ->> 'conversion_mode' = 'manual');

  -- ---------------------------------------------------------------------------
  -- 13. The page RPCs still return every key their clients read.
  --
  -- 0014 rewrote dashboard(), person_page() and activity_page() in order to add
  -- two columns to their select lists, and the first cut of dashboard() silently
  -- lost its 'profile' key -- which every web dashboard render reads on its
  -- second line. Nothing caught it: the migration applied, 172 assertions
  -- passed, the snapshot was clean, and the screen was blank.
  --
  -- A read RPC's contract is its key set. This asserts the key set.
  -- ---------------------------------------------------------------------------
  v_page := public.dashboard();
  perform pg_temp.assert(
    'dashboard() returns every key its clients read',
    v_page ? 'profile' and v_page ? 'summary' and v_page ? 'base_currency'
      and v_page ? 'today' and v_page ? 'recent_activity'
      and v_page ? 'people_with_balance');
  perform pg_temp.assert(
    'and the profile it returns carries the currency the screen is denominated in',
    v_page -> 'profile' ? 'currency' and v_page -> 'profile' ? 'name'
      and v_page -> 'profile' ? 'id');
  perform pg_temp.assert(
    'and a summary, even for a workspace with nothing in it',
    v_page -> 'summary' ? 'total_receivable'
      and v_page -> 'summary' ? 'total_payable'
      and v_page -> 'summary' ? 'net_position'
      and v_page -> 'summary' ? 'gross_settled');

  v_page := public.person_page(v_ahmed);
  perform pg_temp.assert(
    'person_page() returns every key its clients read',
    v_page ? 'person' and v_page ? 'balance' and v_page ? 'currency'
      and v_page ? 'default_currency' and v_page ? 'base_currency'
      and v_page ? 'timeline' and v_page ? 'timeline_total'
      and v_page ? 'open_transactions');

  v_page := public.activity_page();
  perform pg_temp.assert(
    'activity_page() returns every key its clients read',
    v_page ? 'items' and v_page ? 'total' and v_page ? 'has_more');

  v_page := public.search_all('a');
  perform pg_temp.assert(
    'search_all() returns every key its clients read',
    v_page ? 'people' and v_page ? 'transactions');

  raise notice '=== ALL MANUAL CONVERSION TESTS PASSED ===';
end $$;

rollback;
