-- =============================================================================
-- 0033_person_breakdown_as_booked.sql
-- Each per-currency row on the person page also states what it is worth in
-- the ACCOUNT's own currency, as booked — the frozen ledger figure, never a
-- rate applied today.
--
-- THE BUG
--
-- A rupee account holding a dirham entry booked at 1 AED = ₹22.50 showed, in
-- its "cash in hand by currency" block, that dirham balance re-converted at
-- today's ₹26.32. The rupees the ledger actually recorded for it were right
-- there in `amount_minor`; the block simply had no way to say so, because the
-- only equivalent it carried was `net_base_minor`, a conversion at today's
-- rate. On one screen the headline read ₹10,000 and the block beneath it added
-- up to ₹14,239.74 for the same money.
--
-- THE FIX
--
-- `net_ledger_minor`: the row's outstanding figure summed from the ledger
-- amounts themselves — Σ ±(amount_minor − settled_minor). No rate is applied
-- anywhere in it, so it is exactly the money the ledger booked. Summed across
-- the rows, it IS the headline (`regular.position` / `opening_position.position`).
--
-- Additive: every existing key is byte-identical. dashboard() does not call
-- this function (it inlines the same CTEs over the whole workspace) and is not
-- touched — its figures are unchanged by construction.
--
-- Transcribed from the live catalogue (pg_get_functiondef), which is 0027's
-- version, and edited in two places: the `ledger_open` column in `cbc`, and the
-- `net_ledger_minor` key.
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
      )::bigint                                           as settled_orig,
      -- 0033: what is still open on this row, in the ACCOUNT's currency, as
      -- booked. Straight from the ledger; no rate.
      (case when a.entry_type = 'credit' then 1 else -1 end)
        * (a.amount_minor - coalesce(st.settled_minor, 0))  as ledger_open
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
      coalesce(sum(ledger_open), 0)::bigint as net_ledger_minor,
      coalesce(sum(orig_minor) filter (where entry_date = current_date), 0)::bigint as today,
      count(*) filter (where entry_date = current_date)::bigint as today_count,
      count(*)::bigint as entry_count
    from cbc
    group by currency
  ) r
$function$;

-- PostgREST reads function return shapes at schema load; the signature is
-- unchanged, but reload anyway so no cached plan outlives the new key.
notify pgrst, 'reload schema';
