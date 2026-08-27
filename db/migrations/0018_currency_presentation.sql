-- =============================================================================
-- 0018 — every screen can show the original amount, its base equivalent, and
--        where the rate came from
--
-- THE REPORTED PROBLEM
--
--     400 AED · displayed rate 1 AED = ₹25.9842 · displayed ₹10,393.69
--     400 × 25.9842 = ₹10,393.68
--
-- The conversion was never wrong. `convert_amount_minor()` multiplies by the
-- full 1e9-scaled integer rate and rounds once, at the end — 400 AED at the
-- stored 25.984225 really is ₹10,393.69. What was wrong is that the clients
-- printed the rate rounded to four decimals beside a figure computed from nine,
-- so the line did not reconcile on its face. That is a display fix and it lives
-- in the clients (lib/currencies.ts, core/currencies.dart).
--
-- WHAT THE DATABASE STILL OWES THE CLIENTS
--
-- To show the hierarchy the fix asks for —
--
--     400 AED                      the original, strongest
--     ≈ ₹10,393.69 INR             the base equivalent, secondary
--     1 AED = ₹25.984225 INR       the rate, tertiary
--
-- — a screen needs all three on every row. Two read paths were short:
--
--   * `person_page()` served its timeline from `activity_feed`, which carries
--     the ledger figure and the entered figure but not the base equivalent. A
--     person kept in AED on a rupee workspace therefore had no ₹ line at all.
--     It now reads `activity_entries` (0017), which resolves exactly that.
--
--   * `dashboard()` and `activity_page()` dropped `exchange_rate_source`, so a
--     client could not say whether a row's rate was live, cached, or typed in
--     by hand. It is now carried on every activity row.
--
-- NOTHING IS RECOMPUTED AND NO STORED FIGURE MOVES. Every amount, currency and
-- rate on every existing row is left exactly as written. This migration adds
-- columns to two JSON payloads and re-points one query at a view that was
-- already the answer. §3 verifies the historical rows rather than rewriting
-- them, and is safe to run any number of times.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. person_page() — the timeline gains what was entered and what it is worth
--
-- Identical to 0014's, with `activity_feed a` replaced by `activity_entries a`
-- and five of that view's columns added to the row. `amount_minor` keeps its
-- meaning to the letter: minor units of the person's LEDGER currency, the
-- figure every balance is computed from.
-- -----------------------------------------------------------------------------

create or replace function public.person_page(
  p_person_id uuid,
  p_limit     int default 30,
  p_offset    int default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_bal   jsonb;
begin
  p_limit  := least(greatest(coalesce(p_limit, 30), 1), 100);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  select to_jsonb(b) into v_bal
  from public.person_balances b
  where b.person_id = p_person_id and b.owner_id = v_owner;

  if v_bal is null then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  return jsonb_build_object(
    'person', (select to_jsonb(p) from public.people p
               where p.id = p_person_id and p.owner_id = v_owner),
    'balance', v_bal,
    -- What the figures on this page are in ...
    'currency', public.person_ledger_currency(p_person_id),
    -- ... and what the next entry should default to.
    'default_currency', public.person_currency(p_person_id),
    'base_currency', public.owner_base_currency(v_owner),
    'timeline', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.entry_kind, a.entry_type, a.money_direction, a.amount_minor,
               a.entry_date, a.note, a.is_void, a.related_transaction_id, a.created_at,
               a.is_opening, a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_at, a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor,
               -- What was actually entered, and what the ledger figure is worth
               -- in the workspace currency. Both resolved by activity_entries,
               -- which calls convert_for_owner() and invents nothing.
               a.entry_amount_minor, a.entry_currency,
               a.ledger_currency, a.amount_base_minor, a.base_currency,
               st.settled_minor, st.remaining_minor, st.status
        from public.activity_entries a
        left join public.transaction_settlement_status(p_person_id) st
               on st.transaction_id = a.id and a.entry_kind = 'transaction'
        where a.owner_id = v_owner and a.person_id = p_person_id
        order by a.entry_date desc, a.created_at desc
        limit p_limit offset p_offset
      ) r
    ), '[]'::jsonb),
    'timeline_total', (
      select count(*) from public.activity_feed a
      where a.owner_id = v_owner and a.person_id = p_person_id
    ),
    'open_transactions', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.transaction_date, r.created_at)
      from (
        select t.id, t.type, t.amount_minor, t.transaction_date, t.description,
               t.created_at, t.is_opening, st.remaining_minor, st.settled_minor
        from public.transactions t
        join public.transaction_settlement_status(p_person_id) st on st.transaction_id = t.id
        where t.owner_id = v_owner and t.person_id = p_person_id
          and not t.is_void and st.remaining_minor > 0
        order by t.transaction_date, t.created_at
      ) r
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.person_page(uuid, int, int) to authenticated;

comment on function public.person_page(uuid, int, int) is
  'One person''s whole screen. Timeline rows carry the ledger figure (amount_minor), what was entered (entry_amount_minor/entry_currency), the base equivalent (amount_base_minor) and the rate with its source (0018).';

-- -----------------------------------------------------------------------------
-- 2. dashboard() and activity_page() — carry where the rate came from
--
-- Byte-identical to 0017's apart from one added column in each row list. A
-- client that does not read it sees no change.
-- -----------------------------------------------------------------------------

create or replace function public.dashboard(
  p_activity_limit int default 10,
  p_people_limit   int default 8
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.current_owner();
  v_base  text;
  v_result jsonb;
begin
  if v_owner is null then
    raise exception 'Not authorised.' using errcode = 'insufficient_privilege';
  end if;

  v_base := public.owner_base_currency(v_owner);
  p_activity_limit := least(greatest(coalesce(p_activity_limit, 10), 1), 50);
  p_people_limit   := least(greatest(coalesce(p_people_limit, 8), 1), 50);

  select jsonb_build_object(
    'profile', (
      select to_jsonb(x) from (
        select p.id, p.name, p.email, p.phone, p.business_name, p.avatar_url, p.currency
        from public.profiles p where p.id = v_owner
      ) x
    ),
    'base_currency', v_base,
    -- The consolidated position, always in the workspace currency: every
    -- person's net converted once, then summed. Amounts in different
    -- currencies are never added together anywhere in this object.
    'summary', coalesce(
      (select to_jsonb(s) from public.owner_summary s where s.owner_id = v_owner),
      jsonb_build_object(
        'owner_id', v_owner, 'base_currency', v_base,
        'total_receivable', 0, 'total_payable', 0, 'net_position', 0,
        'people_with_balance', 0, 'people_count', 0, 'unconverted_people', 0,
        'currency_count', 0,
        'gross_credit', 0, 'gross_debit', 0, 'gross_settled', 0
      )
    ),
    'today', (
      select jsonb_build_object(
        'credit',  coalesce(sum(a.amount_base_minor)
                     filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0)::bigint,
        'debit',   coalesce(sum(a.amount_base_minor)
                     filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)::bigint,
        'settled', coalesce(sum(a.amount_base_minor)
                     filter (where a.entry_kind = 'settlement'), 0)::bigint,
        'count',   count(*)::bigint
      )
      from public.activity_entries a
      where a.owner_id = v_owner and not a.is_void and a.entry_date = current_date
    ),
    'today_by_currency', coalesce((
      select jsonb_agg(to_jsonb(r) order by (r.currency = v_base) desc, r.currency)
      from (
        select a.entry_currency as currency,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0)::bigint as credit,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)::bigint  as debit,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'settlement'), 0)::bigint                              as settled,
               count(*)::bigint                                                                      as count,
               v_base                                                                                as base_currency,
               public.convert_for_owner(v_owner, coalesce(sum(a.entry_amount_minor), 0)::bigint,
                                        a.entry_currency, v_base)                                    as moved_base_minor
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void and a.entry_date = current_date
        group by a.entry_currency
      ) r
    ), '[]'::jsonb),
    'totals_by_currency', coalesce((
      select jsonb_agg(to_jsonb(r) order by (r.currency = v_base) desc, r.currency)
      from (
        select a.entry_currency as currency,
               v_base as base_currency,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0)::bigint as gross_credit,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)::bigint  as gross_debit,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'settlement'), 0)::bigint                              as gross_settled,
               count(*) filter (where a.entry_kind = 'transaction')::bigint                          as entry_count,
               count(distinct a.person_id)::bigint                                                   as people_count,
               public.convert_for_owner(
                 v_owner,
                 (coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='credit'), 0)
                  - coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='debit'), 0))::bigint,
                 a.entry_currency, v_base)                                                           as net_base_minor,
               (coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='credit'), 0)
                - coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='debit'), 0))::bigint as net_position
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
        group by a.entry_currency
      ) r
    ), '[]'::jsonb),
    'recent_activity', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.person_id, pe.name as person_name, a.entry_kind, a.entry_type,
               a.amount_minor, a.entry_date, a.note, a.created_at, a.is_opening,
               a.ledger_currency as currency,
               a.entry_amount_minor, a.entry_currency,
               a.amount_base_minor, a.base_currency,
               a.entered_amount_minor, a.entered_currency, a.exchange_rate_e9,
               -- Where that rate came from: 'live', a cache label, or the
               -- manual marker a user typed. The row can say so now (0018).
               a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor
        from public.activity_entries a
        join public.people pe on pe.id = a.person_id
        where a.owner_id = v_owner and not a.is_void
        order by a.entry_date desc, a.created_at desc
        limit p_activity_limit
      ) r
    ), '[]'::jsonb),
    'people_with_balance', coalesce((
      select jsonb_agg(to_jsonb(r) order by abs(coalesce(r.net_balance_base, r.net_balance)) desc)
      from (
        select pb.person_id, pb.name, pb.type, pb.net_balance, pb.net_balance_base,
               pb.currency, pb.default_currency, pb.base_currency,
               pb.outstanding_receivable, pb.outstanding_payable, pb.last_activity_at
        from public.person_balances pb
        where pb.owner_id = v_owner and not pb.is_archived and pb.net_balance <> 0
        order by abs(coalesce(pb.net_balance_base, pb.net_balance)) desc
        limit p_people_limit
      ) r
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.dashboard(int, int) from public, anon;
grant execute on function public.dashboard(int, int) to authenticated;

comment on function public.dashboard(int, int) is
  'Whole dashboard in one call. summary/today are the consolidated base-currency position; activity rows carry the entered figure, its base equivalent and the rate with its source; totals_by_currency groups by entry currency and never sums across them (0018).';

create or replace function public.activity_page(
  p_limit    int  default 40,
  p_offset   int  default 0,
  p_kind     text default null,
  p_from     date default null,
  p_to       date default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_base  text := public.owner_base_currency(v_owner);
  v_rows  jsonb;
  v_total bigint;
begin
  p_limit  := least(greatest(coalesce(p_limit, 40), 1), 100);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  select count(*) into v_total
  from public.activity_feed a
  where a.owner_id = v_owner
    and not a.is_void
    and (p_kind is null or a.entry_kind = p_kind)
    and (p_from is null or a.entry_date >= p_from)
    and (p_to   is null or a.entry_date <= p_to);

  select coalesce(jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select a.id, a.person_id, pe.name as person_name, a.entry_kind, a.entry_type,
           a.amount_minor, a.entry_date, a.note, a.created_at, a.is_opening,
           a.ledger_currency as currency,
           a.entry_amount_minor, a.entry_currency,
           a.amount_base_minor, a.base_currency,
           a.entered_amount_minor, a.entered_currency, a.exchange_rate_e9,
           a.exchange_rate_source,
           a.conversion_mode, a.auto_converted_amount_minor
    from public.activity_entries a
    join public.people pe on pe.id = a.person_id
    where a.owner_id = v_owner
      and not a.is_void
      and (p_kind is null or a.entry_kind = p_kind)
      and (p_from is null or a.entry_date >= p_from)
      and (p_to   is null or a.entry_date <= p_to)
    order by a.entry_date desc, a.created_at desc
    limit p_limit offset p_offset
  ) r;

  return jsonb_build_object('items', v_rows, 'total', v_total,
                            'has_more', (p_offset + p_limit) < v_total);
end;
$$;

revoke all on function public.activity_page(int, int, text, date, date) from public, anon;
grant execute on function public.activity_page(int, int, text, date, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. The historical rows, verified rather than rewritten
--
-- Every transaction and settlement written before today either has all three
-- conversion columns or none of them — the 0010 CHECK constraints
-- (`transactions_conversion_complete`) have enforced that since the day
-- currency existed, so there is no row with an entered currency and no rate to
-- back it, and nothing to backfill.
--
-- This block asserts that instead of assuming it. It reads; it writes only in
-- the one case it can repair without inventing anything — a row whose
-- `exchange_rate_source` was lost while its rate survived, which is provenance
-- and not money. A rate, an amount and a currency are never touched: if a row
-- ever did lack a rate, the correct answer is a human deciding what rate
-- applied on that date, not this migration guessing with today's.
--
-- Idempotent: run it twice and the second run finds nothing and writes nothing.
-- -----------------------------------------------------------------------------

do $$
declare
  v_txn_missing_rate bigint;
  v_set_missing_rate bigint;
  v_source_filled    bigint := 0;
  v_rows             bigint;
begin
  select count(*) into v_txn_missing_rate
  from public.transactions
  where entered_currency is not null and exchange_rate_e9 is null;

  select count(*) into v_set_missing_rate
  from public.settlements
  where entered_currency is not null and exchange_rate_e9 is null;

  if v_txn_missing_rate > 0 or v_set_missing_rate > 0 then
    raise exception
      '0018: % transaction(s) and % settlement(s) carry a foreign currency with no stored rate. '
      'These predate the conversion-complete constraint and must be corrected by hand with the '
      'rate that actually applied on their date — this migration will not guess one.',
      v_txn_missing_rate, v_set_missing_rate
      using errcode = 'data_exception';
  end if;

  -- Provenance only. The rate itself is already on the row and is not read,
  -- recomputed or replaced here.
  update public.transactions
     set exchange_rate_source = 'unrecorded'
   where entered_currency is not null
     and exchange_rate_e9 is not null
     and (exchange_rate_source is null or btrim(exchange_rate_source) = '');
  get diagnostics v_rows = row_count;
  v_source_filled := v_source_filled + v_rows;

  update public.settlements
     set exchange_rate_source = 'unrecorded'
   where entered_currency is not null
     and exchange_rate_e9 is not null
     and (exchange_rate_source is null or btrim(exchange_rate_source) = '');
  get diagnostics v_rows = row_count;
  v_source_filled := v_source_filled + v_rows;

  raise notice '0018: conversion data verified. % row(s) had a missing rate source filled in; no amount, currency or rate was altered.',
    v_source_filled;
end $$;

-- -----------------------------------------------------------------------------
-- 4. What a manually typed rate looks like on a row
--
-- No schema change: a user-entered rate is an ordinary rate. It is stored in
-- `exchange_rate_e9` like any other, it is frozen on the row like any other,
-- and every later automatic rate change leaves it exactly where it is — no read
-- path re-derives a stored ledger amount from a current rate.
--
-- What distinguishes it is its provenance: `exchange_rate_source = 'manual-rate'`,
-- which is why that column now travels to the clients (§2).
--
-- The marker is 'manual-rate' and not 'manual' for a reason worth writing down.
-- 0011's write RPCs default a missing source to the literal 'manual', so rows
-- written by a client that sent no source at all already carry that word
-- without a human having typed anything. Reusing it would relabel history.
-- 'manual-rate' has never been written by any version of this product, so it
-- means exactly one thing and can never mean it retroactively.
--
-- This function is the single definition of that test, so that no screen and no
-- client invents its own spelling of it.
-- -----------------------------------------------------------------------------

create or replace function public.rate_is_manual(p_source text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(btrim(coalesce(p_source, ''))) = 'manual-rate';
$$;

revoke all on function public.rate_is_manual(text) from public;
grant execute on function public.rate_is_manual(text) to authenticated, service_role;

comment on function public.rate_is_manual(text) is
  'True when a row''s exchange_rate_source says a human typed the rate itself. The one definition of that test (0018).';
