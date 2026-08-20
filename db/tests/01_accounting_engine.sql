-- =============================================================================
-- 01_accounting_engine.sql — context.md §33
--
-- Verifies every arithmetic case the spec names, plus the integrity guards.
-- Self-contained: creates its own users, asserts, then ROLLS BACK, so it can be
-- run repeatedly against a live database without leaving anything behind.
--
-- Run in the Supabase SQL editor (service role) or:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/tests/01_accounting_engine.sql
--
-- Any failure raises and aborts. "ALL ACCOUNTING TESTS PASSED" means all green.
-- =============================================================================

begin;

-- The over-settlement guards are DEFERRABLE INITIALLY DEFERRED so that a
-- multi-row statement is judged on its final state. Deferred events would fire
-- at COMMIT, which this script never reaches — make them immediate so each
-- assertion below is evaluated where it is written.
set constraints all immediate;

create or replace function pg_temp.assert_eq(p_label text, p_actual bigint, p_expected bigint)
returns void language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL % — expected %, got %', p_label, p_expected, p_actual;
  end if;
  raise notice 'ok   % (%)', p_label, p_actual;
end $$;

create or replace function pg_temp.assert_raises(p_label text, p_sql text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'ok   % (rejected: %)', p_label, sqlerrm;
    return;
  end;
  raise exception 'FAIL % — statement was accepted but should have been rejected', p_label;
end $$;

do $$
declare
  u        uuid := gen_random_uuid();
  person_a uuid;
  person_b uuid;
  t1 uuid; t2 uuid; t3 uuid;
  b  public.person_balances%rowtype;
  s  public.owner_summary%rowtype;
  st record;
begin
  ---------------------------------------------------------------------------
  -- Fixture
  ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', u, 'authenticated', 'authenticated',
          'test-engine-' || u || '@example.test', 'x', now(), now(), now());

  insert into public.people (owner_id, name) values (u, 'Test Person A') returning id into person_a;
  insert into public.people (owner_id, name) values (u, 'Test Person B') returning id into person_b;

  ---------------------------------------------------------------------------
  -- §33 Credit: Credit 10,000 -> outstanding 10,000
  ---------------------------------------------------------------------------
  insert into public.transactions (owner_id, person_id, type, amount_minor)
  values (u, person_a, 'credit', 1000000) returning id into t1;

  select * into b from public.person_balances where person_id = person_a;
  perform pg_temp.assert_eq('credit -> outstanding_receivable', b.outstanding_receivable, 1000000);
  perform pg_temp.assert_eq('credit -> net_balance',            b.net_balance,            1000000);
  perform pg_temp.assert_eq('credit -> outstanding_payable',    b.outstanding_payable,    0);

  ---------------------------------------------------------------------------
  -- §33 Debit: Debit 5,000 -> outstanding 5,000
  ---------------------------------------------------------------------------
  insert into public.transactions (owner_id, person_id, type, amount_minor)
  values (u, person_b, 'debit', 500000);

  select * into b from public.person_balances where person_id = person_b;
  perform pg_temp.assert_eq('debit -> outstanding_payable', b.outstanding_payable, 500000);
  perform pg_temp.assert_eq('debit -> net_balance',         b.net_balance,        -500000);

  ---------------------------------------------------------------------------
  -- §33 Partial settlement: 10,000 - 4,000 = 6,000
  ---------------------------------------------------------------------------
  insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor)
  values (u, person_a, t1, 'in', 400000);

  select * into b from public.person_balances where person_id = person_a;
  perform pg_temp.assert_eq('partial settlement -> outstanding', b.outstanding_receivable, 600000);
  perform pg_temp.assert_eq('partial settlement -> total_settled', b.total_settled, 400000);

  select * into st from public.transaction_settlement_status(person_a) where transaction_id = t1;
  perform pg_temp.assert_eq('partial settlement -> tx remaining', st.remaining_minor, 600000);
  if st.status <> 'partial' then
    raise exception 'FAIL partial settlement -> tx status, got %', st.status;
  end if;

  ---------------------------------------------------------------------------
  -- §33 Full settlement: remaining 6,000 settled -> 0, history preserved
  ---------------------------------------------------------------------------
  insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor)
  values (u, person_a, t1, 'in', 600000);

  select * into b from public.person_balances where person_id = person_a;
  perform pg_temp.assert_eq('full settlement -> outstanding', b.outstanding_receivable, 0);
  perform pg_temp.assert_eq('full settlement -> transaction still present', b.transaction_count, 1);

  select * into st from public.transaction_settlement_status(person_a) where transaction_id = t1;
  if st.status <> 'settled' then
    raise exception 'FAIL full settlement -> tx status, got %', st.status;
  end if;

  ---------------------------------------------------------------------------
  -- §33 Multiple transactions: 10,000 + 5,000 - 3,000 = 12,000
  ---------------------------------------------------------------------------
  delete from public.settlements where person_id = person_a;
  delete from public.transactions where person_id = person_a;

  insert into public.transactions (owner_id, person_id, type, amount_minor, transaction_date)
  values (u, person_a, 'credit', 1000000, current_date - 2) returning id into t1;
  insert into public.transactions (owner_id, person_id, type, amount_minor, transaction_date)
  values (u, person_a, 'credit', 500000, current_date - 1) returning id into t2;
  insert into public.settlements (owner_id, person_id, direction, amount_minor)
  values (u, person_a, 'in', 300000);

  select * into b from public.person_balances where person_id = person_a;
  perform pg_temp.assert_eq('multiple txns -> outstanding', b.outstanding_receivable, 1200000);

  -- Account-level settlement allocates FIFO to the oldest open transaction.
  select * into st from public.transaction_settlement_status(person_a) where transaction_id = t1;
  perform pg_temp.assert_eq('FIFO -> oldest txn absorbs settlement', st.settled_minor, 300000);
  select * into st from public.transaction_settlement_status(person_a) where transaction_id = t2;
  perform pg_temp.assert_eq('FIFO -> newer txn untouched', st.settled_minor, 0);

  ---------------------------------------------------------------------------
  -- Targeted settlement beats FIFO: pressing Settle on the NEWER invoice must
  -- apply there, not to the older one.
  ---------------------------------------------------------------------------
  delete from public.settlements where person_id = person_a;
  insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor)
  values (u, person_a, t2, 'in', 200000);

  select * into st from public.transaction_settlement_status(person_a) where transaction_id = t2;
  perform pg_temp.assert_eq('targeted settlement -> named txn', st.settled_minor, 200000);
  select * into st from public.transaction_settlement_status(person_a) where transaction_id = t1;
  perform pg_temp.assert_eq('targeted settlement -> older txn untouched', st.settled_minor, 0);

  ---------------------------------------------------------------------------
  -- §33 Mixed account: credit 10,000 + debit 4,000 -> net 6,000 receivable
  ---------------------------------------------------------------------------
  delete from public.settlements where person_id = person_a;
  delete from public.transactions where person_id = person_a;

  insert into public.transactions (owner_id, person_id, type, amount_minor)
  values (u, person_a, 'credit', 1000000);
  insert into public.transactions (owner_id, person_id, type, amount_minor)
  values (u, person_a, 'debit', 400000);

  select * into b from public.person_balances where person_id = person_a;
  perform pg_temp.assert_eq('mixed -> receivable', b.outstanding_receivable, 1000000);
  perform pg_temp.assert_eq('mixed -> payable',    b.outstanding_payable,     400000);
  perform pg_temp.assert_eq('mixed -> net',        b.net_balance,             600000);

  ---------------------------------------------------------------------------
  -- Workspace totals net per person, then split across the two sides.
  -- person_a: net +6,000   person_b: net -5,000
  ---------------------------------------------------------------------------
  select * into s from public.owner_summary where owner_id = u;
  perform pg_temp.assert_eq('summary -> total_receivable', s.total_receivable, 600000);
  perform pg_temp.assert_eq('summary -> total_payable',    s.total_payable,    500000);
  perform pg_temp.assert_eq('summary -> net_position',     s.net_position,     100000);

  ---------------------------------------------------------------------------
  -- Voided transactions leave history but no longer affect balances (§17)
  ---------------------------------------------------------------------------
  insert into public.transactions (owner_id, person_id, type, amount_minor)
  values (u, person_a, 'credit', 999900) returning id into t3;
  select * into b from public.person_balances where person_id = person_a;
  perform pg_temp.assert_eq('before void -> receivable', b.outstanding_receivable, 1999900);

  update public.transactions set is_void = true, void_reason = 'entered twice' where id = t3;
  select * into b from public.person_balances where person_id = person_a;
  perform pg_temp.assert_eq('after void -> receivable', b.outstanding_receivable, 1000000);
  perform pg_temp.assert_eq('after void -> row still exists',
    (select count(*) from public.transactions where id = t3), 1);

  raise notice '--- integrity guards ---';
end $$;

-- --- integrity guards (each must be rejected) --------------------------------

do $$
declare
  u uuid; pa uuid; pb uuid; other uuid; other_p uuid; t uuid;
begin
  select p.owner_id, p.id into u, pa
  from public.people p
  where p.name = 'Test Person A'
  order by p.created_at desc limit 1;

  select id into pb from public.people where owner_id = u and name = 'Test Person B';

  -- a separate workspace, to prove cross-owner references are impossible
  other := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', other, 'authenticated', 'authenticated',
          'test-other-' || other || '@example.test', 'x', now(), now(), now());
  insert into public.people (owner_id, name) values (other, 'Other Workspace Person') returning id into other_p;

  perform pg_temp.assert_raises('negative amount rejected',
    format('insert into public.transactions (owner_id, person_id, type, amount_minor) values (%L, %L, ''credit'', -100)', u, pa));

  perform pg_temp.assert_raises('zero amount rejected',
    format('insert into public.transactions (owner_id, person_id, type, amount_minor) values (%L, %L, ''credit'', 0)', u, pa));

  perform pg_temp.assert_raises('cross-owner person_id rejected',
    format('insert into public.transactions (owner_id, person_id, type, amount_minor) values (%L, %L, ''credit'', 1000)', u, other_p));

  perform pg_temp.assert_raises('over-settlement rejected',
    format('insert into public.settlements (owner_id, person_id, direction, amount_minor) values (%L, %L, ''in'', 99999999)', u, pa));

  perform pg_temp.assert_raises('settling a payable with money-in rejected',
    format('insert into public.settlements (owner_id, person_id, direction, amount_minor) values (%L, %L, ''in'', 1000)', u, pb));

  select id into t from public.transactions
  where owner_id = u and person_id = pa and type = 'credit' and not is_void limit 1;

  perform pg_temp.assert_raises('wrong-direction settlement on a named transaction rejected',
    format('insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor) values (%L, %L, %L, ''out'', 1000)', u, pa, t));

  perform pg_temp.assert_raises('moving a transaction to another person rejected',
    format('update public.transactions set person_id = %L where id = %L', pb, t));

  perform pg_temp.assert_raises('deleting a person with history rejected',
    format('delete from public.people where id = %L', pa));

  -- Shrinking a transaction below what has already been settled against it.
  insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor)
  values (u, pa, t, 'in', 900000);
  perform pg_temp.assert_raises('shrinking a transaction below settled amount rejected',
    format('update public.transactions set amount_minor = 100 where id = %L', t));
  perform pg_temp.assert_raises('voiding a transaction that is already settled rejected',
    format('update public.transactions set is_void = true where id = %L', t));
end $$;

do $$ begin raise notice E'\n=== ALL ACCOUNTING TESTS PASSED ===\n'; end $$;

rollback;
