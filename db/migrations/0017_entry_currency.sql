-- =============================================================================
-- 0017 — the dashboard reports what was actually entered
--
-- THE PROBLEM, stated exactly
--
-- `transactions.amount_minor` is denominated in the PERSON's ledger currency.
-- When an entry is made in another currency the original is kept —
-- `entered_amount_minor` + `entered_currency` — and `amount_minor` holds the
-- converted figure. That is the right way round for accounting: a person's
-- balance has to be summable, so it lives in one denomination.
--
-- It is the wrong way round for reporting. On a rupee-denominated account, a
-- USD 40 entry is stored as ₹3,817.11, and every read path handed the client
-- `amount_minor` as THE amount. The original was carried too, but only as
-- provenance, so the dashboard said ₹3,817.11 where the user had typed $40.
-- Two things followed from that:
--
--   * Activity showed conversions, not entries. The figure a user recognises —
--     the one they typed — was a footnote under the one they did not.
--   * 0016's `totals_by_currency` grouped by the PERSON's currency, so a USD
--     entry against a rupee account was counted as INR. The card said "by
--     currency" and meant "by account denomination".
--
-- WHAT THIS ADDS
--
-- Nothing is recomputed and no stored figure moves. Two things are exposed that
-- the database already knew:
--
--   1. Every activity row gains `entry_amount_minor` / `entry_currency` — what
--      was actually entered, falling back to the ledger figure when the two are
--      the same — plus `amount_base_minor`, the base-currency equivalent, so a
--      client never has to convert anything itself.
--
--   2. `totals_by_currency` is regrouped by ENTRY currency, and each row now
--      carries both its own total and the base-currency equivalent of it.
--
-- `convert_for_owner()` remains the only converter in the system; this calls it
-- and invents nothing. Amounts in different currencies are never added: every
-- sum here is within one currency, and the base equivalent is a conversion of
-- that single-currency sum, not a mixture.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. One place that answers "what was entered, and what is that in base?"
--
-- A view rather than repeated CASE expressions in four RPCs. `activity_feed`
-- already unions transactions and settlements and already carries the entered
-- columns for both; this adds the resolution rule on top, once.
-- -----------------------------------------------------------------------------

create or replace view public.activity_entries
with (security_invoker = true) as
select
  a.*,
  -- The person's denomination: what `amount_minor` is in.
  coalesce(pe.ledger_currency, pe.currency, public.owner_base_currency(a.owner_id))
                                                          as ledger_currency,
  -- What was actually handed over. When the entry was made in the account's own
  -- currency there is no separate original, and these equal the ledger figures.
  coalesce(a.entered_amount_minor, a.amount_minor)         as entry_amount_minor,
  coalesce(
    a.entered_currency,
    pe.ledger_currency, pe.currency, public.owner_base_currency(a.owner_id)
  )                                                        as entry_currency,
  public.owner_base_currency(a.owner_id)                   as base_currency,
  -- The base-currency equivalent of the ledger figure. Converting the ledger
  -- amount rather than the entered one keeps this consistent with every other
  -- total on the dashboard, which are all built from ledger amounts. NULL when
  -- no rate is cached — "not known", never zero.
  public.convert_for_owner(
    a.owner_id,
    a.amount_minor,
    coalesce(pe.ledger_currency, pe.currency, public.owner_base_currency(a.owner_id)),
    public.owner_base_currency(a.owner_id)
  )                                                        as amount_base_minor
from public.activity_feed a
join public.people pe on pe.id = a.person_id;

comment on view public.activity_entries is
  'activity_feed plus the entry-currency resolution: entry_amount_minor/entry_currency are what was actually entered, amount_minor stays the ledger figure, and amount_base_minor is the base-currency equivalent (0017).';

grant select on public.activity_entries to authenticated;
revoke all on public.activity_entries from anon;

-- -----------------------------------------------------------------------------
-- 2. dashboard() — activity keeps its own currency, totals group by entry
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
    -- Today's movement per ENTRY currency, plus what each is worth in base.
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
               -- The base equivalent of THIS currency's own total. One
               -- conversion of one single-currency sum; nothing is mixed.
               public.convert_for_owner(v_owner, coalesce(sum(a.entry_amount_minor), 0)::bigint,
                                        a.entry_currency, v_base)                                    as moved_base_minor
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void and a.entry_date = current_date
        group by a.entry_currency
      ) r
    ), '[]'::jsonb),
    -- Standing position per ENTRY currency: what was actually transacted in
    -- each, and the base equivalent of that total.
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
               -- What the user actually entered: the primary figure to show.
               a.entry_amount_minor, a.entry_currency,
               -- And what it is worth in the workspace currency.
               a.amount_base_minor, a.base_currency,
               a.entered_amount_minor, a.entered_currency, a.exchange_rate_e9,
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
  'Whole dashboard in one call. Activity rows carry BOTH what was entered (entry_amount_minor/entry_currency) and its base-currency equivalent (amount_base_minor); totals_by_currency groups by entry currency. summary/today remain base-currency figures (0017).';

-- -----------------------------------------------------------------------------
-- 3. activity_page() — the same rule, so the Activity screen agrees
-- -----------------------------------------------------------------------------

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
