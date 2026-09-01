-- =============================================================================
-- seed_bench.sql — a workspace the size of a decade of real use (Phase 8).
--
-- docs/performance.md measured the engine on a seeded workspace of a few dozen
-- entries and said outright what was missing: the numbers at realistic scale,
-- where `person_balances`' lateral joins and the FIFO allocator in
-- `transaction_settlement_status()` are the two things most likely to bend.
--
-- This builds that workspace:
--
--     50 accounts across 5 currencies
--     20,000 transactions over three years
--      ~5,000 settlements, most of them targeted at a specific entry
--         20 opening balances, with adjustments
--        200 transfer legs
--
-- Written as bulk inserts rather than as RPC calls, deliberately. The RPCs are
-- validated one row at a time and rate limited (0026); this is a fixture, not a
-- test of the write path, and it needs to exist in seconds rather than hours.
-- It runs as the table owner with no JWT claims, so auth.uid() is null and the
-- rate-limit triggers pass it through.
--
-- Idempotent: it removes its own workspace first. It touches nothing else, and
-- it is NEVER run against the live project — db/tools/bench.mjs points at
-- whatever DATABASE_URL says, so point that at a throwaway database.
--
--   node db/tools/run-sql.mjs file db/bench/seed_bench.sql
--   node db/tools/bench.mjs 30
-- =============================================================================

do $$
declare
  c_owner  constant uuid := '00000000-0000-4000-8000-0000000be000'::uuid;
begin
  delete from auth.users where id = c_owner;
end $$;

do $$
declare
  c_owner   constant uuid := '00000000-0000-4000-8000-0000000be000'::uuid;
  c_people  constant int  := 50;
  c_entries constant int  := 20000;

  v_person  uuid;
  v_txn     uuid;
  v_seed    int;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', c_owner, 'authenticated', 'authenticated',
          'bench@example.test', 'x', now(), now(), now());

  update public.profiles
     set name = 'Bench Workspace', currency = 'INR'
   where id = c_owner;

  -- Rates for the currencies below, so conversion is not the thing being
  -- measured by its absence.
  insert into public.exchange_rates (owner_id, base, quote, rate_e9, as_of, source, fetched_at)
  values (c_owner, 'AED', 'INR', 24000000000, current_date, 'bench', now()),
         (c_owner, 'USD', 'INR', 88000000000, current_date, 'bench', now()),
         (c_owner, 'EUR', 'INR', 95000000000, current_date, 'bench', now()),
         (c_owner, 'GBP', 'INR', 112000000000, current_date, 'bench', now())
  on conflict do nothing;

  -- --- accounts --------------------------------------------------------------
  insert into public.people (owner_id, name, type, phone, currency, ledger_currency, created_at)
  select
    c_owner,
    'Bench Account ' || lpad(i::text, 3, '0'),
    (case when i % 7 = 0 then 'business' else 'person' end)::public.party_type,
    '+9198' || lpad(i::text, 8, '0'),
    (array['INR', 'INR', 'INR', 'AED', 'USD', 'EUR', 'GBP'])[1 + (i % 7)],
    (array['INR', 'INR', 'INR', 'AED', 'USD', 'EUR', 'GBP'])[1 + (i % 7)],
    now() - ((c_people - i) || ' days')::interval
  from generate_series(1, c_people) i;

  -- --- the ledger ------------------------------------------------------------
  -- Spread over three years, alternating direction, a fifth of them entered in
  -- a currency other than the account's own so the conversion path is exercised.
  insert into public.transactions (
    owner_id, person_id, type, amount_minor, transaction_date, description,
    entered_amount_minor, entered_currency, exchange_rate_e9, exchange_rate_source,
    created_at
  )
  select
    c_owner,
    p.id,
    (case when i % 2 = 0 then 'credit' else 'debit' end)::public.txn_type,
    case
      when i % 5 = 0 then (2000 + (i % 900) * 24)::bigint
      else (5000 + (i % 45000))::bigint
    end,
    (current_date - ((i % 1095))::int),
    (array['rent', 'materials', 'advance', 'labour', 'transport', 'repair',
           'supplies', 'commission', 'fuel', 'misc'])[1 + (i % 10)]
      || ' #' || i,
    case when i % 5 = 0 then (2000 + (i % 900))::bigint end,
    case when i % 5 = 0 then 'AED' end,
    case when i % 5 = 0 then 24000000000::bigint end,
    case when i % 5 = 0 then 'bench' end,
    now() - ((i % 1095) || ' days')::interval
  from generate_series(1, c_entries) i
  join lateral (
    select id from public.people
    where owner_id = c_owner
    order by name
    offset (i % c_people) limit 1
  ) p on true;

  -- --- settlements -----------------------------------------------------------
  -- A quarter of the entries carry a targeted part settlement, which is what
  -- makes the FIFO allocator do real work: every unsettled row before a
  -- targeted one still has to be walked.
  insert into public.settlements (
    owner_id, person_id, transaction_id, direction, amount_minor, settlement_date, note, created_at
  )
  select
    c_owner,
    t.person_id,
    t.id,
    -- credit is settled by money coming in; debit by money going out.
    (case when t.type = 'credit' then 'in' else 'out' end)::public.settlement_direction,
    greatest(1, (t.amount_minor / 2))::bigint,
    t.transaction_date,
    'part settlement',
    t.created_at + interval '1 day'
  from public.transactions t
  where t.owner_id = c_owner
    and (('x' || substr(md5(t.id::text), 1, 8))::bit(32)::int % 4) = 0;

  -- --- opening balances ------------------------------------------------------
  -- Twenty accounts opened with a balance, and half of those adjusted once, so
  -- the opening book is not empty when the dashboard splits the two positions.
  for v_person in
    select id from public.people where owner_id = c_owner order by name limit 20
  loop
    insert into public.transactions (
      owner_id, person_id, type, amount_minor, transaction_date, description,
      is_opening, opening_role, created_at
    )
    values (
      c_owner, v_person, 'credit', 250000, current_date - 1200,
      'opening balance', true, 'balance', now() - interval '1200 days'
    );
  end loop;

  for v_person in
    select id from public.people where owner_id = c_owner order by name limit 10
  loop
    insert into public.transactions (
      owner_id, person_id, type, amount_minor, transaction_date, description,
      is_opening, opening_role, created_at
    )
    values (
      c_owner, v_person, 'debit', 40000, current_date - 900,
      'opening adjustment', true, 'adjustment', now() - interval '900 days'
    );
  end loop;

  -- --- transfers -------------------------------------------------------------
  -- 100 transfers, each two linked legs, between neighbouring accounts.
  for v_seed in 1..100 loop
    declare
      v_from uuid;
      v_to   uuid;
      v_id   uuid := gen_random_uuid();
      v_a    uuid := gen_random_uuid();
      v_b    uuid := gen_random_uuid();
    begin
      select id into v_from from public.people
       where owner_id = c_owner order by name offset (v_seed % c_people) limit 1;
      select id into v_to from public.people
       where owner_id = c_owner order by name offset ((v_seed + 7) % c_people) limit 1;

      insert into public.transfers (
        id, owner_id, from_person_id, to_person_id, transfer_date, note,
        entry_amount_minor, entry_currency, from_amount_minor, from_currency,
        to_amount_minor, to_currency, created_at
      )
      values (
        v_id, c_owner, v_from, v_to, current_date - (v_seed % 700), 'bench transfer',
        50000, 'INR', 50000, 'INR', 50000, 'INR', now() - ((v_seed % 700) || ' days')::interval
      );

      insert into public.transactions (
        id, owner_id, person_id, type, amount_minor, transaction_date, description,
        transfer_id, transfer_role, created_at
      )
      values
        (v_a, c_owner, v_from, 'debit', 50000, current_date - (v_seed % 700),
         'bench transfer', v_id, 'source', now() - ((v_seed % 700) || ' days')::interval),
        (v_b, c_owner, v_to, 'credit', 50000, current_date - (v_seed % 700),
         'bench transfer', v_id, 'destination', now() - ((v_seed % 700) || ' days')::interval);
    end;
  end loop;

  analyze public.transactions;
  analyze public.settlements;
  analyze public.people;
  analyze public.transfers;

  raise notice 'bench workspace: % people, % transactions, % settlements, % transfers',
    (select count(*) from public.people where owner_id = c_owner),
    (select count(*) from public.transactions where owner_id = c_owner),
    (select count(*) from public.settlements where owner_id = c_owner),
    (select count(*) from public.transfers where owner_id = c_owner);
end $$;
