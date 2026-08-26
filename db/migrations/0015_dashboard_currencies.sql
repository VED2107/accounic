-- =============================================================================
-- 0015 — the dashboard stops pretending there is only one currency
--
-- The dashboard already converted everything into the workspace's base currency
-- and said so. That is the right headline: one number that answers "how am I
-- doing", and it can only exist if the dirhams are turned into rupees first.
--
-- What it could not do is show the dirhams. A workspace with four currencies in
-- it had exactly one figure per statistic, and no way to ask what the AED half
-- of it was without opening each account. Adding raw AED to raw INR is not an
-- option — that is arithmetic on two different things — so the answer is not one
-- more total but one total per currency, kept apart.
--
-- Two new keys on dashboard(), both additive:
--
--   * `totals_by_currency`  — receivable / payable / net / settled per currency,
--     in that currency, never converted, never summed across currencies.
--   * `today_by_currency`   — the same split for today's movement.
--
-- Everything that was there before is byte-identical, `summary` and `today`
-- included, so a client that ignores the new keys renders what it rendered
-- before. There is no second conversion system here: these figures are the
-- untouched ledger amounts, and convert_for_owner() remains the only converter.
--
-- Only currencies that actually carry entries appear. A person created in EUR
-- who has never been transacted with is not a EUR total of zero; they are not a
-- EUR row at all.
-- =============================================================================

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
    -- Today's totals are converted to the base currency: adding a dirham to a
    -- rupee because both happened today would be arithmetic on two different
    -- things. Entries whose currency has no cached rate are left out rather
    -- than counted at par.
    'today', (
      select jsonb_build_object(
        'credit',  coalesce(sum(public.convert_for_owner(v_owner, a.amount_minor, pc.currency, v_base))
                     filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0)::bigint,
        'debit',   coalesce(sum(public.convert_for_owner(v_owner, a.amount_minor, pc.currency, v_base))
                     filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)::bigint,
        'settled', coalesce(sum(public.convert_for_owner(v_owner, a.amount_minor, pc.currency, v_base))
                     filter (where a.entry_kind = 'settlement'), 0)::bigint,
        'count',   count(*)::bigint
      )
      from public.activity_feed a
      join public.people pe on pe.id = a.person_id
      cross join lateral (
        select coalesce(pe.ledger_currency, pe.currency, v_base) as currency
      ) pc
      where a.owner_id = v_owner and not a.is_void and a.entry_date = current_date
    ),
    -- The same movement, unconverted and kept apart. `today` above is the base
    -- currency answer; this is the per-currency one, and the two are the same
    -- data read two ways rather than two different sums.
    'today_by_currency', coalesce((
      select jsonb_agg(to_jsonb(r) order by (r.currency = v_base) desc, r.currency)
      from (
        select pc.currency,
               coalesce(sum(a.amount_minor)
                 filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0)::bigint as credit,
               coalesce(sum(a.amount_minor)
                 filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)::bigint  as debit,
               coalesce(sum(a.amount_minor)
                 filter (where a.entry_kind = 'settlement'), 0)::bigint                              as settled,
               count(*)::bigint                                                                      as count
        from public.activity_feed a
        join public.people pe on pe.id = a.person_id
        cross join lateral (
          select coalesce(pe.ledger_currency, pe.currency, v_base) as currency
        ) pc
        where a.owner_id = v_owner and not a.is_void and a.entry_date = current_date
        group by pc.currency
      ) r
    ), '[]'::jsonb),
    -- Standing position per currency. Denominated in each currency, summed only
    -- within it. The base currency is one row here like any other, so a purely
    -- INR workspace reads the same way a four-currency one does.
    'totals_by_currency', coalesce((
      select jsonb_agg(to_jsonb(r) order by (r.currency = v_base) desc, r.currency)
      from (
        select pb.currency,
               coalesce(sum(pb.net_balance) filter (where pb.net_balance > 0), 0)::bigint  as total_receivable,
               coalesce(-sum(pb.net_balance) filter (where pb.net_balance < 0), 0)::bigint as total_payable,
               coalesce(sum(pb.net_balance), 0)::bigint                                    as net_position,
               coalesce(sum(pb.total_credit), 0)::bigint                                   as gross_credit,
               coalesce(sum(pb.total_debit), 0)::bigint                                    as gross_debit,
               coalesce(sum(pb.total_settled), 0)::bigint                                  as gross_settled,
               count(*) filter (where pb.net_balance <> 0)::bigint                         as people_with_balance,
               count(*)::bigint                                                            as people_count
        from public.person_balances pb
        where pb.owner_id = v_owner and not pb.is_archived
        group by pb.currency
        -- A currency with no entries behind it is not a zero; it is absent.
        having count(*) filter (where pb.transaction_count > 0 or pb.total_settled > 0) > 0
      ) r
    ), '[]'::jsonb),
    'recent_activity', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.person_id, pe.name as person_name, a.entry_kind, a.entry_type,
               a.amount_minor, a.entry_date, a.note, a.created_at, a.is_opening,
               coalesce(pe.ledger_currency, pe.currency, v_base) as currency,
               a.entered_amount_minor, a.entered_currency, a.exchange_rate_e9,
               a.conversion_mode, a.auto_converted_amount_minor
        from public.activity_feed a
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

grant execute on function public.dashboard(int, int) to authenticated;

comment on function public.dashboard(int, int) is
  'Whole dashboard in one call. summary/today are base-currency totals; totals_by_currency '
  'and today_by_currency are the same positions kept in their own currencies, never summed '
  'across them, and only for currencies that carry entries.';
