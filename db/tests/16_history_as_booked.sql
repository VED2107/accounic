-- =============================================================================
-- 16_history_as_booked.sql — a historical row keeps the rate it was entered at
-- (0034)
--
--   * 1,000 AED entered on a rupee account at 1 AED = ₹23 is ₹23,000 in every
--     row list — person timeline, Activity, export, the dashboard's recent
--     activity — and STAYS ₹23,000 after today's rate moves to ₹24.50.
--   * A rupee entry on a dirham account is its rupees, at face.
--   * A dirham entry on a dirham account has no rupee figure at all (null):
--     none was ever recorded, and none is invented from today's rate.
--   * Settlements and opening-balance activity follow the same rule.
--   * Editing one entry's rate re-books that entry only.
--   * dashboard()'s totals are untouched: `amount_base_minor` on the view is
--     still the figure its "today" sums read.
--
-- Self-contained: creates its own user, asserts, then ROLLS BACK.
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
  if not coalesce(p_condition, false) then
    raise exception 'FAIL: %', p_label;
  end if;
  raise notice 'ok  %', p_label;
end $$;

-- A row's handed-out amount_base_minor, by note, from a jsonb array of rows.
create or replace function pg_temp.base_of(p_rows jsonb, p_note text)
returns bigint language sql as $$
  select nullif(e ->> 'amount_base_minor', '')::bigint
  from jsonb_array_elements(p_rows) e
  where coalesce(e ->> 'note', e ->> 'description') = p_note
  limit 1
$$;

create or replace function pg_temp.has_row(p_rows jsonb, p_note text)
returns boolean language sql as $$
  select exists (select 1 from jsonb_array_elements(p_rows) e
                 where coalesce(e ->> 'note', e ->> 'description') = p_note)
$$;

do $$
declare
  c_aed23_e9  constant bigint := 23000000000;  -- 1 AED = 23 INR, at entry
  c_inr_aed_e9 constant bigint := 43478261;    -- 1 INR = 1/23 AED, at entry
  v_owner uuid := gen_random_uuid();
  v_inr   uuid;   -- account kept in INR (the workspace currency)
  v_aed   uuid;   -- account kept in AED
  v_txn   uuid;
  v_page  jsonb;
  v_rows  jsonb;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'history-booked@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_owner);
  perform public.update_my_profile('History Tester', null, null, 'INR', null);
  perform public.upsert_exchange_rates('AED', '{"INR": 23}'::jsonb, current_date, 'test');

  v_inr := (public.create_person('Rupee Rao',  'person', null, null, null, null, 'INR')).id;
  v_aed := (public.create_person('Dirham Das', 'person', null, null, null, null, 'AED')).id;

  -- INR account: 1,000 AED lent at 1 AED = ₹23 -> booked ₹23,000.
  perform public.create_transaction(
    p_person_id => v_inr, p_type => 'credit', p_description => 'aed lent',
    p_entered_amount_minor => 100000, p_entered_currency => 'AED',
    p_exchange_rate_e9 => c_aed23_e9, p_rate_source => 'test');
  -- A second AED entry, to prove an edit touches only its own row.
  perform public.create_transaction(
    p_person_id => v_inr, p_type => 'credit', p_description => 'aed lent 2',
    p_entered_amount_minor => 10000, p_entered_currency => 'AED',
    p_exchange_rate_e9 => c_aed23_e9, p_rate_source => 'test');
  -- Partial settlement: ₹10,000 in, against the 1,000 AED entry.
  select id into v_txn from public.transactions where description = 'aed lent';
  perform public.create_settlement(
    p_person_id => v_inr, p_amount_minor => 1000000, p_direction => 'in',
    p_transaction_id => v_txn, p_note => 'part paid');
  -- Opening book: an adjustment of 500 AED at ₹23 -> ₹11,500.
  perform public.set_person_opening_balance(
    p_person_id => v_inr, p_direction => 'they_owe_me', p_amount_minor => 100000);
  perform public.adjust_opening_balance(
    p_person_id => v_inr, p_type => 'credit', p_note => 'opening aed',
    p_entered_amount_minor => 50000, p_entered_currency => 'AED',
    p_exchange_rate_e9 => c_aed23_e9, p_rate_source => 'test');

  -- AED account: 1,000 AED lent in AED, repaid ₹23,000 in rupees.
  perform public.create_transaction(
    p_person_id => v_aed, p_type => 'credit', p_amount_minor => 100000,
    p_description => 'dirham lent');
  perform public.create_transaction(
    p_person_id => v_aed, p_type => 'debit', p_description => 'rupees back',
    p_entered_amount_minor => 2300000, p_entered_currency => 'INR',
    p_exchange_rate_e9 => c_inr_aed_e9, p_rate_source => 'test');

  -- ---------------------------------------------------------------------------
  -- Today's market moves: 1 AED = ₹24.50.
  -- ---------------------------------------------------------------------------
  perform public.upsert_exchange_rates('AED', '{"INR": 24.5}'::jsonb, current_date, 'test');

  v_page := public.person_page(v_inr);
  v_rows := v_page -> 'timeline';
  perform pg_temp.assert('INR account: 1,000 AED row is still ₹23,000 after the rate moved',
    pg_temp.base_of(v_rows, 'aed lent') = 2300000);
  perform pg_temp.assert('INR account: the ledger amount is the booked ₹23,000',
    (select (e ->> 'amount_minor')::bigint from jsonb_array_elements(v_rows) e
     where e ->> 'note' = 'aed lent') = 2300000);
  perform pg_temp.assert('INR account: the settlement row is its ₹10,000',
    pg_temp.base_of(v_rows, 'part paid') = 1000000);
  perform pg_temp.assert('INR account: opening activity row keeps its ₹11,500',
    pg_temp.base_of(v_page -> 'opening_activity', 'opening aed') = 1150000);
  perform pg_temp.assert('INR account: cash in hand is 23,000 + 2,300 - 10,000 booked',
    (v_page -> 'regular' ->> 'position')::bigint = 1530000);
  perform pg_temp.assert('INR account: cash in hand did not move with the rate',
    (v_page -> 'regular' ->> 'position')::bigint
      = (select cash_in_hand_minor from public.person_balances where person_id = v_inr));
  perform pg_temp.assert('INR account: opening position is 1,000 + 11,500, apart from cash',
    (v_page -> 'opening_position' ->> 'position')::bigint = 1250000);

  v_page := public.person_page(v_aed);
  v_rows := v_page -> 'timeline';
  perform pg_temp.assert('AED account: the rupee entry is its ₹23,000 at face',
    pg_temp.base_of(v_rows, 'rupees back') = 2300000);
  perform pg_temp.assert('AED account: the dirham entry has NO rupee figure (none was recorded)',
    pg_temp.has_row(v_rows, 'dirham lent') and pg_temp.base_of(v_rows, 'dirham lent') is null);
  perform pg_temp.assert('AED account: fully offset -> cash in hand 0',
    (v_page -> 'regular' ->> 'position')::bigint = 0);

  -- The same figures on every other row list.
  v_rows := public.activity_page(100, 0) -> 'items';
  perform pg_temp.assert('activity_page: 1,000 AED row is ₹23,000',
    pg_temp.base_of(v_rows, 'aed lent') = 2300000);
  perform pg_temp.assert('activity_page: dirham-on-dirham row has no rupee figure',
    pg_temp.has_row(v_rows, 'dirham lent') and pg_temp.base_of(v_rows, 'dirham lent') is null);

  v_rows := public.dashboard(50, 8) -> 'recent_activity';
  perform pg_temp.assert('dashboard recent_activity: 1,000 AED row is ₹23,000',
    pg_temp.base_of(v_rows, 'aed lent') = 2300000);

  v_rows := public.export_entries() -> 'entries';
  perform pg_temp.assert('export_entries: 1,000 AED row is ₹23,000',
    pg_temp.base_of(v_rows, 'aed lent') = 2300000);
  perform pg_temp.assert('export_entries: dirham-on-dirham row has no rupee figure',
    pg_temp.has_row(v_rows, 'dirham lent') and pg_temp.base_of(v_rows, 'dirham lent') is null);

  -- The dashboard's totals still read the view's unchanged column.
  perform pg_temp.assert('dashboard cash-in-hand position unchanged for an INR-only book',
    (public.dashboard() -> 'cash_in_hand' ->> 'position')::bigint is not null);
  perform pg_temp.assert('view still carries amount_base_minor at the cached rate (dashboard sums it)',
    (select amount_base_minor from public.activity_entries where note = 'dirham lent') = 2450000);

  -- ---------------------------------------------------------------------------
  -- Editing one entry's rate re-books that entry only.
  -- ---------------------------------------------------------------------------
  select id into v_txn from public.transactions where description = 'aed lent 2';
  perform public.update_transaction(
    p_transaction_id => v_txn, p_type => 'credit', p_description => 'aed lent 2',
    p_entered_amount_minor => 10000, p_entered_currency => 'AED',
    p_exchange_rate_e9 => 25000000000, p_rate_source => 'test');

  v_rows := public.person_page(v_inr) -> 'timeline';
  perform pg_temp.assert('edited entry re-booked at its new rate: 100 AED x 25 = ₹2,500',
    pg_temp.base_of(v_rows, 'aed lent 2') = 250000);
  perform pg_temp.assert('the other entry kept its ₹23,000',
    pg_temp.base_of(v_rows, 'aed lent') = 2300000);
  perform pg_temp.assert('the edited entry stored its new rate',
    (select exchange_rate_e9 from public.transactions where id = v_txn) = 25000000000);
end $$;

rollback;
