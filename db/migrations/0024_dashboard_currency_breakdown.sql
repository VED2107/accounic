-- =============================================================================
-- 0024 — the dashboard leads with the currency the money was entered in
--
-- WHAT WAS WRONG
--
-- 0015 added `totals_by_currency` and 0022 split it into a cash-in-hand half
-- and an opening half — but only the NET of each half was kept per currency
-- (`cash_net_position`, `opening_net_position`). The dashboard still printed the
-- base-currency total as the headline and the original currencies as a single
-- squashed "from 60 AED · $100" footnote, with receivable / payable / settled /
-- today available only after conversion to the base currency.
--
-- The user's requirement: the ORIGINAL amounts people actually entered are the
-- primary display, aggregated across every person, grouped by currency, each
-- currency carrying its own receivable / payable / settled / today / count for
-- BOTH halves independently. The base-currency figure stays, as secondary
-- reference only. Net position is untouched.
--
-- WHAT THIS FILE ADDS
--
--   * `totals_by_currency[i].cash` and `.opening` — nested objects, per entry
--     currency, each with credit / debit / settled / receivable / payable / net
--     / today / today_count / entry_count / people_count, in that currency.
--     `net_base_minor` on each is the base-currency equivalent for reference.
--   * `person_page()` gains `regular_by_currency` and `opening_by_currency` —
--     the same breakdown scoped to one person.
--
-- Every key that `totals_by_currency` and `person_page()` carried before is
-- still there, byte-for-byte, so a client on the old shape renders exactly what
-- it did. `summary`, `today`, `cash_in_hand`, `opening`, `net_position` are not
-- touched.
--
-- WHAT IT DOES NOT CHANGE
--
-- No amount, currency, rate, date or id. No view. No write path. The accounting
-- engine, settlement allocation, transfers and the opening/cash split from 0022
-- are all exactly as they were. This file only regroups what is already stored
-- for display.
--
-- HOW THE PER-CURRENCY SETTLED FIGURE IS DERIVED
--
-- `transaction_settlement_status()` allocates settlement per transaction in the
-- person's LEDGER currency (the denomination of `amount_minor`). To state the
-- settled/outstanding portion in the currency the row was ENTERED in, the
-- ledger figure is scaled by `entered_amount_minor / amount_minor` — exact for a
-- fully settled row, proportional for a partly settled foreign-currency row.
-- The unscaled net (credit − debit) per currency is kept as it was and stays
-- exact.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- dashboard() — 0022's function, with the `totals_by_currency` block rewritten
-- to carry the two nested per-currency breakdowns. Everything else is 0022.
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
  v_sum   jsonb;
  v_result jsonb;
begin
  if v_owner is null then
    raise exception 'Not authorised.' using errcode = 'insufficient_privilege';
  end if;

  v_base := public.owner_base_currency(v_owner);
  p_activity_limit := least(greatest(coalesce(p_activity_limit, 10), 1), 50);
  p_people_limit   := least(greatest(coalesce(p_people_limit, 8), 1), 50);

  select coalesce(
    (select to_jsonb(s) from public.owner_summary s where s.owner_id = v_owner),
    jsonb_build_object(
      'owner_id', v_owner, 'base_currency', v_base,
      'total_receivable', 0, 'total_payable', 0, 'net_position', 0,
      'people_with_balance', 0, 'people_count', 0, 'unconverted_people', 0,
      'currency_count', 0,
      'gross_credit', 0, 'gross_debit', 0, 'gross_settled', 0,
      'cash_in_hand', 0, 'cash_receivable', 0, 'cash_payable', 0,
      'cash_settled', 0, 'people_with_cash', 0,
      'opening_position', 0, 'opening_receivable', 0, 'opening_payable', 0,
      'opening_settled', 0, 'people_with_opening', 0
    )
  ) into v_sum;

  select jsonb_build_object(
    'profile', (
      select to_jsonb(x) from (
        select p.id, p.name, p.email, p.phone, p.business_name, p.avatar_url, p.currency
        from public.profiles p where p.id = v_owner
      ) x
    ),
    'base_currency', v_base,
    'summary', v_sum,

    -- The regular trading position. Never contains the opening book.
    'cash_in_hand', jsonb_build_object(
      'base_currency', v_base,
      'position',   (v_sum->>'cash_in_hand')::bigint,
      'receivable', (v_sum->>'cash_receivable')::bigint,
      'payable',    (v_sum->>'cash_payable')::bigint,
      'settled',    (v_sum->>'cash_settled')::bigint,
      'people_count', (v_sum->>'people_with_cash')::bigint,
      'today', (
        select coalesce(sum(a.amount_base_minor), 0)::bigint
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
          and not a.opening_scope
          and a.entry_date = current_date
      ),
      'today_count', (
        select count(*)::bigint
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
          and not a.opening_scope
          and a.entry_date = current_date
      )
    ),

    -- The opening book, on its own. Shown beside cash in hand, never inside it.
    'opening', jsonb_build_object(
      'base_currency', v_base,
      'position',   (v_sum->>'opening_position')::bigint,
      'receivable', (v_sum->>'opening_receivable')::bigint,
      'payable',    (v_sum->>'opening_payable')::bigint,
      'settled',    (v_sum->>'opening_settled')::bigint,
      'people_count', (v_sum->>'people_with_opening')::bigint,
      'today', (
        select coalesce(sum(a.amount_base_minor), 0)::bigint
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
          and a.opening_scope
          and a.entry_date = current_date
      ),
      'today_count', (
        select count(*)::bigint
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
          and a.opening_scope
          and a.entry_date = current_date
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

    -- ----------------------------------------------------------------------
    -- Per entry currency, and per half of the ledger. The ORIGINAL amounts,
    -- never summed across currencies. This is the primary display; the
    -- base-currency figures above are the reference view of the same money.
    --
    -- `cbc` (currency-by-currency) resolves each transaction row's entered
    -- figure and the portion of it that has been settled, then groups.
    -- ----------------------------------------------------------------------
    'totals_by_currency', coalesce((
      with cbc as (
        select
          a.entry_currency                                    as currency,
          a.opening_scope                                     as is_opening,
          a.entry_type,
          a.person_id,
          a.entry_date,
          a.entry_amount_minor                                as orig_minor,
          -- The entered figure's settled portion, scaled from the ledger
          -- figure the allocator returns. Exact when the row is settled in
          -- full; proportional while it is partly settled.
          round(
            coalesce(st.settled_minor, 0)::numeric
            * case when a.amount_minor <> 0
                   then a.entry_amount_minor::numeric / a.amount_minor
                   else 1 end
          )::bigint                                           as settled_orig
        from public.activity_entries a
        left join lateral public.transaction_settlement_status(a.person_id) st
               on st.transaction_id = a.id
        where a.owner_id = v_owner and not a.is_void
          and a.entry_kind = 'transaction'
      ),
      grp as (
        select
          currency,
          is_opening,
          coalesce(sum(orig_minor)   filter (where entry_type = 'credit'), 0)::bigint as credit,
          coalesce(sum(orig_minor)   filter (where entry_type = 'debit'),  0)::bigint as debit,
          coalesce(sum(settled_orig) filter (where entry_type = 'credit'), 0)::bigint as settled_in,
          coalesce(sum(settled_orig) filter (where entry_type = 'debit'),  0)::bigint as settled_out,
          coalesce(sum(orig_minor) filter (where entry_date = current_date), 0)::bigint as today,
          count(*) filter (where entry_date = current_date)::bigint                     as today_count,
          count(*)::bigint                                                              as entry_count,
          count(distinct person_id)::bigint                                             as people_count
        from cbc
        group by currency, is_opening
      ),
      -- Every currency that has ANY activity — transaction or settlement — so a
      -- currency that only ever appears on a settlement is still a row.
      curr as (
        select distinct a.entry_currency as currency
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
      )
      select jsonb_agg(
        to_jsonb(x) order by (x.currency = v_base) desc, x.currency
      )
      from (
        select
          c.currency,
          v_base as base_currency,
          -- Unchanged keys: gross totals and the net split from 0022.
          coalesce(gc.credit, 0) + coalesce(go.credit, 0)                              as gross_credit,
          coalesce(gc.debit,  0) + coalesce(go.debit,  0)                              as gross_debit,
          coalesce(gc.settled_in, 0) + coalesce(gc.settled_out, 0)
            + coalesce(go.settled_in, 0) + coalesce(go.settled_out, 0)                 as gross_settled,
          (coalesce(gc.credit, 0) + coalesce(go.credit, 0)
            - coalesce(gc.debit, 0) - coalesce(go.debit, 0))                           as net_position,
          (coalesce(gc.credit, 0) - coalesce(gc.debit, 0))                             as cash_net_position,
          (coalesce(go.credit, 0) - coalesce(go.debit, 0))                             as opening_net_position,
          public.convert_for_owner(
            v_owner,
            (coalesce(gc.credit, 0) + coalesce(go.credit, 0)
              - coalesce(gc.debit, 0) - coalesce(go.debit, 0))::bigint,
            c.currency, v_base)                                                        as net_base_minor,
          (coalesce(gc.entry_count, 0) + coalesce(go.entry_count, 0))                  as entry_count,
          greatest(coalesce(gc.people_count, 0), coalesce(go.people_count, 0))         as people_count,

          -- New: the cash-in-hand half in this currency, net of settlement.
          jsonb_build_object(
            'currency',    c.currency,
            'base_currency', v_base,
            'credit',      coalesce(gc.credit, 0),
            'debit',       coalesce(gc.debit, 0),
            'settled',     coalesce(gc.settled_in, 0) + coalesce(gc.settled_out, 0),
            'receivable',  greatest(coalesce(gc.credit, 0) - coalesce(gc.settled_in, 0), 0),
            'payable',     greatest(coalesce(gc.debit, 0)  - coalesce(gc.settled_out, 0), 0),
            'net',         (coalesce(gc.credit, 0) - coalesce(gc.settled_in, 0))
                             - (coalesce(gc.debit, 0) - coalesce(gc.settled_out, 0)),
            'net_base_minor', public.convert_for_owner(
              v_owner,
              ((coalesce(gc.credit, 0) - coalesce(gc.settled_in, 0))
                - (coalesce(gc.debit, 0) - coalesce(gc.settled_out, 0)))::bigint,
              c.currency, v_base),
            'today',       coalesce(gc.today, 0),
            'today_count', coalesce(gc.today_count, 0),
            'entry_count', coalesce(gc.entry_count, 0),
            'people_count', coalesce(gc.people_count, 0)
          )                                                                            as cash,

          -- New: the opening half in this currency, net of settlement.
          jsonb_build_object(
            'currency',    c.currency,
            'base_currency', v_base,
            'credit',      coalesce(go.credit, 0),
            'debit',       coalesce(go.debit, 0),
            'settled',     coalesce(go.settled_in, 0) + coalesce(go.settled_out, 0),
            'receivable',  greatest(coalesce(go.credit, 0) - coalesce(go.settled_in, 0), 0),
            'payable',     greatest(coalesce(go.debit, 0)  - coalesce(go.settled_out, 0), 0),
            'net',         (coalesce(go.credit, 0) - coalesce(go.settled_in, 0))
                             - (coalesce(go.debit, 0) - coalesce(go.settled_out, 0)),
            'net_base_minor', public.convert_for_owner(
              v_owner,
              ((coalesce(go.credit, 0) - coalesce(go.settled_in, 0))
                - (coalesce(go.debit, 0) - coalesce(go.settled_out, 0)))::bigint,
              c.currency, v_base),
            'today',       coalesce(go.today, 0),
            'today_count', coalesce(go.today_count, 0),
            'entry_count', coalesce(go.entry_count, 0),
            'people_count', coalesce(go.people_count, 0)
          )                                                                            as opening
        from curr c
        left join grp gc on gc.currency = c.currency and gc.is_opening = false
        left join grp go on go.currency = c.currency and go.is_opening = true
      ) x
    ), '[]'::jsonb),
    'recent_activity', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.person_id, pe.name as person_name, a.entry_kind, a.entry_type,
               a.amount_minor, a.entry_date, a.note, a.created_at, a.is_opening,
               a.opening_role, a.opening_scope,
               a.ledger_currency as currency,
               a.entry_amount_minor, a.entry_currency,
               a.amount_base_minor, a.base_currency,
               a.entered_amount_minor, a.entered_currency, a.exchange_rate_e9,
               a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor,
               a.transfer_id, a.transfer_role, a.transfer_counterparty_id,
               cp.name as transfer_counterparty_name
        from public.activity_entries a
        join public.people pe on pe.id = a.person_id
        left join public.people cp on cp.id = a.transfer_counterparty_id
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
               pb.outstanding_receivable, pb.outstanding_payable, pb.last_activity_at,
               pb.cash_in_hand_minor, pb.cash_in_hand_base,
               pb.opening_net_minor, pb.opening_net_base
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
  'Whole dashboard in one call. summary/today/cash_in_hand/opening are base-currency totals; '
  'totals_by_currency is the same positions kept in the currency each entry was made in, never '
  'summed across them — since 0024 each row carries `cash` and `opening` objects with '
  'receivable/payable/settled/today for that half in that currency.';

-- -----------------------------------------------------------------------------
-- person_page() — 0022's function, with `regular_by_currency` and
-- `opening_by_currency` added. Every other section is 0022, unchanged.
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
    'currency', public.person_ledger_currency(p_person_id),
    'default_currency', public.person_currency(p_person_id),
    'base_currency', public.owner_base_currency(v_owner),

    'opening', (
      select to_jsonb(o) from public.person_opening o
      where o.person_id = p_person_id and o.owner_id = v_owner
    ),

    'regular', jsonb_build_object(
      'currency',    v_bal->>'currency',
      'base_currency', v_bal->>'base_currency',
      'position',    (v_bal->>'cash_in_hand_minor')::bigint,
      'position_base', nullif(v_bal->>'cash_in_hand_base', '')::bigint,
      'receivable',  (v_bal->>'regular_receivable')::bigint,
      'payable',     (v_bal->>'regular_payable')::bigint,
      'settled',     (v_bal->>'regular_settled_total')::bigint,
      'credit',      (v_bal->>'regular_credit_minor')::bigint,
      'debit',       (v_bal->>'regular_debit_minor')::bigint
    ),
    'opening_position', jsonb_build_object(
      'currency',    v_bal->>'currency',
      'base_currency', v_bal->>'base_currency',
      'position',    (v_bal->>'opening_net_minor')::bigint,
      'position_base', nullif(v_bal->>'opening_net_base', '')::bigint,
      'receivable',  (v_bal->>'opening_receivable')::bigint,
      'payable',     (v_bal->>'opening_payable')::bigint,
      'settled',     (v_bal->>'opening_settled_total')::bigint,
      'credit',      (v_bal->>'opening_credit_minor')::bigint,
      'debit',       (v_bal->>'opening_debit_minor')::bigint,
      'entry_count', (v_bal->>'opening_entry_count')::bigint
    ),

    -- ----------------------------------------------------------------------
    -- The two halves broken out by the currency each row was entered in.
    -- Same shape and same rules as dashboard()'s `totals_by_currency[i].cash`
    -- / `.opening`, scoped to this person. `people_count` is omitted — it is
    -- always one here.
    -- ----------------------------------------------------------------------
    'regular_by_currency', public.person_currency_breakdown(p_person_id, v_owner, false),
    'opening_by_currency', public.person_currency_breakdown(p_person_id, v_owner, true),

    'opening_history', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from (
        select a.person_id,
               a.owner_id,
               a.id                    as transaction_id,
               a.id,
               a.amount_minor,
               case when a.entry_type = 'credit' then a.amount_minor else -a.amount_minor end
                                       as signed_minor,
               a.entry_type, a.entry_date, a.created_at,
               a.entry_amount_minor, a.entry_currency, a.ledger_currency,
               a.amount_base_minor, a.base_currency,
               a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_at, a.exchange_rate_source,
               public.rate_is_manual(a.exchange_rate_source) as rate_is_manual,
               a.conversion_mode, a.auto_converted_amount_minor,
               a.note,
               a.opening_role,
               0::bigint               as settled_minor,
               0::bigint               as remaining_minor,
               'void'::text            as status
        from public.activity_entries a
        where a.owner_id = v_owner and a.person_id = p_person_id
          and a.entry_kind = 'transaction' and a.is_opening
          and a.opening_role = 'balance' and a.is_void
        order by a.created_at desc
        limit 20
      ) r
    ), '[]'::jsonb),

    'opening_activity', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.entry_kind, a.entry_type, a.money_direction, a.amount_minor,
               a.entry_date, a.note, a.is_void, a.related_transaction_id, a.created_at,
               a.is_opening, a.opening_role, a.opening_scope,
               a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_at, a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor,
               a.entry_amount_minor, a.entry_currency,
               a.ledger_currency, a.amount_base_minor, a.base_currency,
               st.settled_minor, st.remaining_minor, st.status
        from public.activity_entries a
        left join public.transaction_settlement_status(p_person_id) st
               on st.transaction_id = a.id and a.entry_kind = 'transaction'
        where a.owner_id = v_owner and a.person_id = p_person_id
          and a.opening_scope
          and coalesce(a.opening_role, 'adjustment') <> 'balance'
        order by a.entry_date desc, a.created_at desc
        limit 100
      ) r
    ), '[]'::jsonb),

    'timeline', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.entry_kind, a.entry_type, a.money_direction, a.amount_minor,
               a.entry_date, a.note, a.is_void, a.related_transaction_id, a.created_at,
               a.is_opening, a.opening_role, a.opening_scope,
               a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_at, a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor,
               a.entry_amount_minor, a.entry_currency,
               a.ledger_currency, a.amount_base_minor, a.base_currency,
               a.transfer_id, a.transfer_role, a.transfer_counterparty_id,
               cp.name as transfer_counterparty_name,
               st.settled_minor, st.remaining_minor, st.status
        from public.activity_entries a
        left join public.transaction_settlement_status(p_person_id) st
               on st.transaction_id = a.id and a.entry_kind = 'transaction'
        left join public.people cp on cp.id = a.transfer_counterparty_id
        where a.owner_id = v_owner and a.person_id = p_person_id
          and not a.opening_scope
        order by a.entry_date desc, a.created_at desc
        limit p_limit offset p_offset
      ) r
    ), '[]'::jsonb),

    'timeline_total', (
      select count(*) from public.activity_feed a
      where a.owner_id = v_owner and a.person_id = p_person_id
        and not a.opening_scope
    ),

    'open_transactions', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.transaction_date, r.created_at)
      from (
        select t.id, t.type, t.amount_minor, t.transaction_date, t.description,
               t.created_at, t.is_opening, st.remaining_minor, st.settled_minor
        from public.transactions t
        join public.transaction_settlement_status(p_person_id) st on st.transaction_id = t.id
        where t.owner_id = v_owner and t.person_id = p_person_id
          and not t.is_void and not t.is_opening and t.transfer_id is null
          and st.remaining_minor > 0
        order by t.transaction_date, t.created_at
      ) r
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.person_page(uuid, int, int) to authenticated;

comment on function public.person_page(uuid, int, int) is
  'One person''s whole screen in sections. `regular` is the cash-in-hand position and `timeline` the activity behind it; `opening`, `opening_position` and `opening_activity` are the opening book. Since 0024, `regular_by_currency` and `opening_by_currency` break each half out by the currency its rows were entered in.';

-- -----------------------------------------------------------------------------
-- person_currency_breakdown() — one person, one half, grouped by entry currency
--
-- Extracted so person_page() stays readable and the rule lives in one place.
-- SECURITY INVOKER, and it takes the owner it was already resolved to rather
-- than re-deriving it, so it can never widen access.
-- -----------------------------------------------------------------------------

create or replace function public.person_currency_breakdown(
  p_person_id uuid,
  p_owner     uuid,
  p_opening   boolean
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with cbc as (
    select
      a.entry_currency                                    as currency,
      a.entry_type,
      a.entry_date,
      a.entry_amount_minor                                as orig_minor,
      round(
        coalesce(st.settled_minor, 0)::numeric
        * case when a.amount_minor <> 0
               then a.entry_amount_minor::numeric / a.amount_minor
               else 1 end
      )::bigint                                           as settled_orig
    from public.activity_entries a
    left join lateral public.transaction_settlement_status(a.person_id) st
           on st.transaction_id = a.id
    where a.owner_id = p_owner
      and a.person_id = p_person_id
      and not a.is_void
      and a.entry_kind = 'transaction'
      and a.opening_scope = p_opening
  )
  select coalesce(
    jsonb_agg(to_jsonb(r) order by r.currency),
    '[]'::jsonb
  )
  from (
    select
      currency,
      public.owner_base_currency(p_owner) as base_currency,
      coalesce(sum(orig_minor)   filter (where entry_type = 'credit'), 0)::bigint as credit,
      coalesce(sum(orig_minor)   filter (where entry_type = 'debit'),  0)::bigint as debit,
      (coalesce(sum(settled_orig) filter (where entry_type = 'credit'), 0)
        + coalesce(sum(settled_orig) filter (where entry_type = 'debit'), 0))::bigint as settled,
      greatest(coalesce(sum(orig_minor) filter (where entry_type = 'credit'), 0)
        - coalesce(sum(settled_orig) filter (where entry_type = 'credit'), 0), 0)::bigint as receivable,
      greatest(coalesce(sum(orig_minor) filter (where entry_type = 'debit'), 0)
        - coalesce(sum(settled_orig) filter (where entry_type = 'debit'), 0), 0)::bigint as payable,
      ((coalesce(sum(orig_minor) filter (where entry_type = 'credit'), 0)
         - coalesce(sum(settled_orig) filter (where entry_type = 'credit'), 0))
       - (coalesce(sum(orig_minor) filter (where entry_type = 'debit'), 0)
         - coalesce(sum(settled_orig) filter (where entry_type = 'debit'), 0)))::bigint as net,
      public.convert_for_owner(
        p_owner,
        ((coalesce(sum(orig_minor) filter (where entry_type = 'credit'), 0)
           - coalesce(sum(settled_orig) filter (where entry_type = 'credit'), 0))
         - (coalesce(sum(orig_minor) filter (where entry_type = 'debit'), 0)
           - coalesce(sum(settled_orig) filter (where entry_type = 'debit'), 0)))::bigint,
        currency, public.owner_base_currency(p_owner)) as net_base_minor,
      coalesce(sum(orig_minor) filter (where entry_date = current_date), 0)::bigint as today,
      count(*) filter (where entry_date = current_date)::bigint as today_count,
      count(*)::bigint as entry_count
    from cbc
    group by currency
  ) r
$$;

revoke all on function public.person_currency_breakdown(uuid, uuid, boolean) from public, anon;
grant execute on function public.person_currency_breakdown(uuid, uuid, boolean) to authenticated;

comment on function public.person_currency_breakdown(uuid, uuid, boolean) is
  'One person''s cash-in-hand half (p_opening false) or opening half (true), grouped by the currency each row was entered in, net of settlement. The per-person analogue of dashboard()''s totals_by_currency[i].cash / .opening (0024).';

-- -----------------------------------------------------------------------------
-- Migration-time checks against the data that exists right now
--
--   1. NOTHING DROPPED. Every currency that appears on any non-void activity
--      row for a workspace appears exactly once as a totals_by_currency row.
--   2. NO CROSS-CURRENCY SUM in the primary figures: the per-currency gross net
--      split (cash_net_position / opening_net_position, from 0022) is unchanged
--      and still adds to net_position within each row; and the new `cash.net` /
--      `opening.net` equal the frozen entered net for that currency and half,
--      to the minor unit, with no conversion in the path.
--   3. THE SCOPING RECONCILES WITH THE ENGINE. For every person, summed over
--      the FROZEN per-row ledger amounts, the cash half and the opening half
--      of the breakdown split the transactions the same way person_balances
--      does: net-of-settlement cash == cash_in_hand_minor and opening ==
--      opening_net_minor, exactly.
--
-- The breakdown's own figures are stated in the currency each row was entered
-- in and are NEVER re-converted here: a base-currency equivalent computed at
-- today's rate cannot equal a ledger figure frozen at entry-time rates, and
-- that is by design (a rate moving must not restate history).
-- -----------------------------------------------------------------------------

do $$
declare
  v_owner    uuid;
  v_dash     jsonb;
  v_row      jsonb;
  v_curr_in  bigint;
  v_curr_out bigint;
  v_person   uuid;
  v_got      bigint;
  v_expect   bigint;
begin
  for v_owner in
    select distinct owner_id from public.people
  loop
    -- dashboard() is SECURITY INVOKER and reads current_owner() from the JWT
    -- claim; become the owner for the length of the check, exactly as
    -- db/tests/11 does, then hand the role back below.
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
    set local role authenticated;

    v_dash := public.dashboard();

    -- 1. no currency dropped, none duplicated
    select count(distinct a.entry_currency) into v_curr_in
    from public.activity_entries a
    where a.owner_id = v_owner and not a.is_void;

    select count(*) into v_curr_out
    from jsonb_array_elements(v_dash -> 'totals_by_currency');

    if coalesce(v_curr_in, 0) <> coalesce(v_curr_out, 0) then
      raise exception
        '0024: workspace % — % currencies have activity but totals_by_currency has % rows.',
        v_owner, v_curr_in, v_curr_out;
    end if;

    -- 2. the gross net split still reconciles inside each row, and the new
    --    per-half net matches the frozen entered net for that currency.
    for v_row in select * from jsonb_array_elements(v_dash -> 'totals_by_currency')
    loop
      if (v_row->>'cash_net_position')::bigint + (v_row->>'opening_net_position')::bigint
         <> (v_row->>'net_position')::bigint then
        raise exception
          '0024: workspace % currency % — cash_net + opening_net <> net_position.',
          v_owner, v_row->>'currency';
      end if;

      -- `cash.net` net-of-settlement, checked against the frozen entered figures.
      select coalesce(sum(
        case when a.entry_type = 'credit' then a.entry_amount_minor else -a.entry_amount_minor end
        - case when a.entry_type = 'credit'
               then round(coalesce(st.settled_minor,0)::numeric
                          * case when a.amount_minor<>0 then a.entry_amount_minor::numeric/a.amount_minor else 1 end)
               else -round(coalesce(st.settled_minor,0)::numeric
                          * case when a.amount_minor<>0 then a.entry_amount_minor::numeric/a.amount_minor else 1 end)
          end
      ), 0)::bigint into v_expect
      from public.activity_entries a
      left join lateral public.transaction_settlement_status(a.person_id) st on st.transaction_id = a.id
      where a.owner_id = v_owner and not a.is_void and a.entry_kind = 'transaction'
        and a.entry_currency = v_row->>'currency' and not a.opening_scope;

      if (v_row->'cash'->>'net')::bigint <> v_expect then
        raise exception
          '0024: workspace % currency % — cash.net is % but the frozen entered net is %.',
          v_owner, v_row->>'currency', (v_row->'cash'->>'net')::bigint, v_expect;
      end if;
    end loop;

    -- 3. the scoping matches the engine, summed over frozen ledger amounts
    for v_person in
      select p.id from public.people p where p.owner_id = v_owner and not p.is_archived
    loop
      -- cash half: net of settlement, in the ledger denomination, frozen
      select coalesce(sum(
        case when st.transaction_id is not null then
          case when t.type = 'credit'
               then (t.amount_minor - coalesce(st.settled_minor,0))
               else -(t.amount_minor - coalesce(st.settled_minor,0)) end
        else 0 end
      ), 0)::bigint into v_got
      from public.transactions t
      join public.transaction_settlement_status(v_person) st on st.transaction_id = t.id
      where t.person_id = v_person and not t.is_void and not t.is_opening;

      select b.cash_in_hand_minor into v_expect
      from public.person_balances b where b.person_id = v_person;

      if v_got <> v_expect then
        raise exception
          '0024: person % — breakdown cash scoping sums to % but person_balances.cash_in_hand_minor is %.',
          v_person, v_got, v_expect;
      end if;
    end loop;
  end loop;

  reset role;
  perform set_config('request.jwt.claims', '', true);

  raise notice
    '0024: totals_by_currency carries the per-currency cash/opening breakdown for every workspace; no currency dropped, the scoping matches the engine, and nothing was rewritten.';
end $$;
