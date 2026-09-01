-- =============================================================================
-- 13_export.sql — the workspace export (0025)
--
-- What an export has to be before anyone can rely on it as a backup:
--
--   * AUTHORIZED. A second workspace exists throughout this suite with money in
--     it. Nothing exported here may contain a byte of it, including when its
--     person id is passed in by hand.
--   * COMPLETE. Every person, every entry, both books, the workspace summary,
--     and the definition of every currency used — enough to read the file
--     without the app.
--   * HONEST ABOUT CURRENCY. Amounts leave in the currency they were entered
--     in, with the base equivalent alongside. Nothing is silently restated.
--   * FILTERED THE SAME WAY TWICE. The header's counts and the paged entries
--     agree, because they apply one filter contract.
--   * DETERMINISTIC. The same request twice gives byte-identical entries, so
--     two exports can be diffed.
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

create or replace function pg_temp.assert_eq(p_label text, p_actual bigint, p_expected bigint)
returns void language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL % — expected %, got %', p_label, p_expected, p_actual;
  end if;
  raise notice 'ok  % (%)', p_label, p_actual;
end $$;

-- One entry out of a page, by its note.
create or replace function pg_temp.entry_by_note(p_page jsonb, p_note text)
returns jsonb language sql as $$
  select e
  from jsonb_array_elements(p_page -> 'entries') e
  where e ->> 'note' = p_note
  limit 1
$$;

do $$
declare
  c_aed_e9 constant bigint := 24000000000;   -- 1 AED = 24 INR

  v_owner   uuid := gen_random_uuid();
  v_other   uuid := gen_random_uuid();
  v_ved     uuid;
  v_amir    uuid;
  v_stranger uuid;
  v_txn     uuid;

  v_head    jsonb;
  v_page    jsonb;
  v_page2   jsonb;
  v_entry   jsonb;
  v_person  jsonb;
  v_first   text;
  v_second  text;
begin
  -- ===========================================================================
  -- Two workspaces. The second one exists only to stay invisible.
  -- ===========================================================================
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'export-owner@example.com', 'x', now(), now(), now()),
         ('00000000-0000-0000-0000-000000000000', v_other, 'authenticated', 'authenticated',
          'export-other@example.com', 'x', now(), now(), now());

  perform pg_temp.become(v_other);
  perform public.update_my_profile('Other Owner', null, null, 'INR', null);
  v_stranger := (public.create_person('STRANGER', 'person', null, null, null, null, 'INR')).id;
  perform public.create_transaction(
    p_person_id => v_stranger, p_type => 'credit', p_amount_minor => 999900,
    p_date => current_date, p_description => 'stranger money');

  perform pg_temp.become(v_owner);
  perform public.update_my_profile('Export Tester', null, null, 'INR', null);
  perform public.upsert_exchange_rates('AED', '{"INR": 24}'::jsonb, current_date, 'test');

  -- VED: an opening balance, two regular entries (one of them in AED), and a
  -- part settlement. AMIR: one entry, later voided.
  v_ved  := (public.create_person('VED',  'person', null, null, null, null, 'INR')).id;
  v_amir := (public.create_person('AMIR', 'person', null, null, null, null, 'INR')).id;

  perform public.set_person_opening_balance(
    p_person_id => v_ved, p_direction => 'they_owe_me', p_amount_minor => 500000,
    p_date => current_date - 40);

  perform public.create_transaction(
    p_person_id => v_ved, p_type => 'credit', p_amount_minor => 100000,
    p_date => current_date - 10, p_description => 'ved inr');

  perform public.create_transaction(
    p_person_id => v_ved, p_type => 'credit', p_description => 'ved aed',
    p_entered_amount_minor => 2000, p_entered_currency => 'AED',
    p_exchange_rate_e9 => c_aed_e9, p_rate_source => 'test');

  select id into v_txn from public.transactions
  where owner_id = v_owner and description = 'ved inr' limit 1;

  perform public.create_settlement(
    p_person_id => v_ved, p_direction => 'in', p_amount_minor => 40000,
    p_date => current_date - 5, p_note => 'part settle ved',
    p_transaction_id => v_txn);

  perform public.create_transaction(
    p_person_id => v_amir, p_type => 'debit', p_amount_minor => 30000,
    p_date => current_date - 3, p_description => 'amir voided');
  perform public.void_transaction(
    (select id from public.transactions where owner_id = v_owner and description = 'amir voided'),
    'test void');

  -- ===========================================================================
  -- The header
  -- ===========================================================================
  v_head := public.export_workspace();

  perform pg_temp.assert('schema is versioned',
    (v_head ->> 'schema_version') = '1');
  perform pg_temp.assert('the export names its generator and time',
    (v_head ->> 'generator') = 'accounic' and (v_head ->> 'exported_at') is not null);
  perform pg_temp.assert('the header carries the workspace profile',
    (v_head -> 'workspace' ->> 'name') = 'Export Tester'
    and (v_head -> 'workspace' ->> 'base_currency') = 'INR');
  perform pg_temp.assert('the header carries the engine summary, not a recomputation',
    (v_head -> 'summary' ->> 'owner_id') = v_owner::text);

  perform pg_temp.assert_eq('two people are exported',
    jsonb_array_length(v_head -> 'people'), 2);

  perform pg_temp.assert('a person carries its balance and its opening row',
    (select count(*) from jsonb_array_elements(v_head -> 'people') p
     where p ->> 'name' = 'VED'
       and p -> 'balance' is not null
       and p -> 'opening' is not null) = 1);

  perform pg_temp.assert('every currency in use is defined in the file',
    (select count(*) from jsonb_array_elements(v_head -> 'currencies') c
     where c ->> 'code' in ('INR', 'AED')) = 2);
  perform pg_temp.assert('a currency definition carries its minor-unit exponent',
    (select (c ->> 'decimals')::int from jsonb_array_elements(v_head -> 'currencies') c
     where c ->> 'code' = 'INR') = 2);

  -- The void is excluded by default and counted when asked for.
  perform pg_temp.assert_eq('voided history is out by default',
    (v_head -> 'counts' ->> 'voided')::bigint, 0);
  perform pg_temp.assert_eq('voided history comes back when it is asked for',
    (public.export_workspace(p_include_void => true) -> 'counts' ->> 'voided')::bigint, 1);

  -- ===========================================================================
  -- The entries
  -- ===========================================================================
  v_page := public.export_entries();

  perform pg_temp.assert('the header count and the page total agree',
    (v_head -> 'counts' ->> 'entries') = (v_page ->> 'total'));

  perform pg_temp.assert_eq('four live entries: opening, two regular, one settlement',
    (v_page ->> 'total')::bigint, 4);

  v_entry := pg_temp.entry_by_note(v_page, 'ved aed');
  perform pg_temp.assert('an entry leaves in the currency it was entered in',
    (v_entry ->> 'entry_currency') = 'AED'
    and (v_entry ->> 'entry_amount_minor')::bigint = 2000);
  perform pg_temp.assert('and carries its ledger and base equivalents alongside',
    (v_entry ->> 'ledger_currency') = 'INR'
    and (v_entry ->> 'amount_minor')::bigint = 48000
    and (v_entry ->> 'base_currency') = 'INR');
  perform pg_temp.assert('with the rate that produced them, and its source',
    (v_entry ->> 'exchange_rate_e9')::bigint = c_aed_e9
    and (v_entry ->> 'exchange_rate_source') = 'test');

  v_entry := pg_temp.entry_by_note(v_page, 'ved inr');
  perform pg_temp.assert_eq('a part-settled transaction reports what is settled',
    (v_entry ->> 'settled_minor')::bigint, 40000);
  perform pg_temp.assert_eq('and what remains',
    (v_entry ->> 'remaining_minor')::bigint, 60000);
  perform pg_temp.assert('and says so in words',
    (v_entry ->> 'settlement_status') = 'partial');

  perform pg_temp.assert('an opening row is marked as one, and never as a transaction',
    (select count(*) from jsonb_array_elements(v_page -> 'entries') e
     where e ->> 'scope' = 'opening') = 1);

  perform pg_temp.assert('every entry names its person',
    (select count(*) from jsonb_array_elements(v_page -> 'entries') e
     where e ->> 'person_name' is null) = 0);

  -- ===========================================================================
  -- Filters — the same contract on both halves
  -- ===========================================================================
  perform pg_temp.assert_eq('scope=opening returns only the opening book',
    (public.export_entries(p_scope => 'opening') ->> 'total')::bigint, 1);
  perform pg_temp.assert_eq('scope=regular returns everything else',
    (public.export_entries(p_scope => 'regular') ->> 'total')::bigint, 3);
  perform pg_temp.assert_eq('currency filters on what was ENTERED, not on the base',
    (public.export_entries(p_currency => 'AED') ->> 'total')::bigint, 1);
  perform pg_temp.assert_eq('kinds filter to settlements alone',
    (public.export_entries(p_kinds => array['settlement']) ->> 'total')::bigint, 1);
  perform pg_temp.assert_eq('a date range excludes what falls outside it',
    (public.export_entries(p_from => current_date - 6) ->> 'total')::bigint, 2);
  perform pg_temp.assert_eq('one person can be exported alone',
    (public.export_entries(p_person_id => v_amir, p_include_void => true) ->> 'total')::bigint, 1);
  -- ===========================================================================
  -- Paging and determinism
  -- ===========================================================================
  v_page  := public.export_entries(p_limit => 2, p_offset => 0);
  v_page2 := public.export_entries(p_limit => 2, p_offset => 2);

  perform pg_temp.assert_eq('a page is the size it was asked for',
    jsonb_array_length(v_page -> 'entries'), 2);
  perform pg_temp.assert('the first page says there is more',
    (v_page ->> 'has_more')::boolean);
  perform pg_temp.assert('the last page says there is not',
    not (v_page2 ->> 'has_more')::boolean);
  perform pg_temp.assert('the pages do not overlap',
    not exists (
      select 1
      from jsonb_array_elements(v_page -> 'entries') a,
           jsonb_array_elements(v_page2 -> 'entries') b
      where a ->> 'id' = b ->> 'id'));

  v_first  := md5((public.export_entries() -> 'entries')::text);
  v_second := md5((public.export_entries() -> 'entries')::text);
  perform pg_temp.assert('the same request twice is byte-identical', v_first = v_second);

  -- ===========================================================================
  -- Isolation — the part that matters most
  -- ===========================================================================
  perform pg_temp.assert('no person from another workspace is in the header',
    (select count(*) from jsonb_array_elements(v_head -> 'people') p
     where p ->> 'name' = 'STRANGER') = 0);

  perform pg_temp.assert('no entry from another workspace is in the export',
    (select count(*) from jsonb_array_elements(public.export_entries() -> 'entries') e
     where e ->> 'note' = 'stranger money') = 0);

  perform pg_temp.assert_eq('naming another workspace''s person returns nothing at all',
    (public.export_entries(p_person_id => v_stranger) ->> 'total')::bigint, 0);

  perform pg_temp.assert_eq('and exports no people either',
    jsonb_array_length(public.export_workspace(p_person_id => v_stranger) -> 'people'), 0);

  -- The reverse direction, from the other workspace's own session.
  perform pg_temp.become(v_other);
  perform pg_temp.assert_eq('the other workspace sees only its own entry',
    (public.export_entries() ->> 'total')::bigint, 1);
  perform pg_temp.assert('and its own name',
    (public.export_workspace() -> 'workspace' ->> 'name') = 'Other Owner');

  raise notice '=== 13_export: all assertions passed ===';
end $$;

-- An unknown scope is a refusal, not a guess. Asserted outside the block above
-- so the raised exception can be caught without abandoning the transaction.
do $$
begin
  begin
    perform public.export_entries(p_scope => 'sideways');
    raise exception 'FAIL: an unknown export scope was accepted';
  exception
    when invalid_parameter_value then
      raise notice 'ok  an unknown scope is refused (%)', sqlerrm;
  end;
end $$;

rollback;
