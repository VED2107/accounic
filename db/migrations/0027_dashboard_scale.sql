-- =============================================================================
-- 0027_dashboard_scale.sql
-- The dashboard at 20,000 entries (milestone 1.9.0, Phase 8).
--
-- docs/performance.md said what had not been measured: the engine at realistic
-- scale, where "the person_balances lateral joins and the FIFO loop in
-- transaction_settlement_status() are the two things most likely to bend
-- first". They bent, and the measurement is in docs/performance.md:
--
--     dashboard()   9.8 ms at demo size  ->  98,235 ms at 20,000 entries
--     person_page() 5.2 ms               ->   2,104 ms
--
-- One cause, in both. 0024's per-currency breakdown joined the allocator
-- LATERALLY against activity_entries:
--
--     left join lateral public.transaction_settlement_status(a.person_id) st
--            on st.transaction_id = a.id
--
-- so it ran once per ENTRY, and each run walked that person's entire ledger to
-- allocate it FIFO. 20,000 entries x ~400 rows each is the 98 seconds.
--
-- This migration changes nothing but where that call sits: the allocator is now
-- asked once per PERSON, into a CTE the rows join against. Same allocator, same
-- FIFO rule, same numbers — db/tests/12 asserts them byte for byte and passes
-- unchanged, and db/tools/snapshot.mjs reports no balance moved.
--
-- Nothing else in either function is touched: the definitions below were taken
-- from the live catalogue and edited in exactly the two places above.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.person_currency_breakdown(p_person_id uuid, p_owner uuid, p_opening boolean)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with alloc as (
    -- One call for this person, not one per row of theirs (Phase 8).
    select s.transaction_id, s.settled_minor
    from public.transaction_settlement_status(p_person_id) s
  ),
  cbc as (
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
    left join alloc st on st.transaction_id = a.id
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
$function$;


CREATE OR REPLACE FUNCTION public.dashboard(p_activity_limit integer DEFAULT 10, p_people_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
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
      with alloc as (
        -- The FIFO allocator, asked once PER PERSON rather than once per row.
        -- It was a LATERAL on activity_entries, so a workspace with 20,000
        -- entries called it 20,000 times and each call walked that person's
        -- whole ledger: 98 seconds for one dashboard at that size (Phase 8).
        select s.transaction_id, s.settled_minor
        from (
          select distinct a.person_id
          from public.activity_entries a
          where a.owner_id = v_owner and not a.is_void
            and a.entry_kind = 'transaction'
        ) p
        cross join lateral public.transaction_settlement_status(p.person_id) s
      ),
      cbc as (
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
        left join alloc st on st.transaction_id = a.id
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
$function$;
