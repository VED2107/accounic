-- =============================================================================
-- 0012_currency_reads.sql
-- The read path, made currency-aware.
--
-- Each screen still ships in one round trip (context.md §23). What changes is
-- that every figure now travels with the currency it is denominated in, and the
-- aggregate screens also carry the base-currency equivalent, so no client has
-- to guess — or worse, assume — which currency a number is in.
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
      cross join lateral (select coalesce(pe.currency, v_base) as currency) pc
      where a.owner_id = v_owner and not a.is_void and a.entry_date = current_date
    ),
    'recent_activity', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.person_id, pe.name as person_name, a.entry_kind, a.entry_type,
               a.amount_minor, a.entry_date, a.note, a.created_at, a.is_opening,
               coalesce(pe.currency, v_base) as currency,
               a.entered_amount_minor, a.entered_currency, a.exchange_rate_e9
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
               pb.currency, pb.base_currency,
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
    'currency', public.person_currency(p_person_id),
    'base_currency', public.owner_base_currency(v_owner),
    'timeline', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.entry_kind, a.entry_type, a.money_direction, a.amount_minor,
               a.entry_date, a.note, a.is_void, a.related_transaction_id, a.created_at,
               a.is_opening, a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_at, a.exchange_rate_source,
               st.settled_minor, st.remaining_minor, st.status
        from public.activity_feed a
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

-- -----------------------------------------------------------------------------

create or replace function public.search_all(p_query text, p_limit int default 12)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.current_owner();
  v_q     text := btrim(coalesce(p_query, ''));
  v_like  text;
begin
  if v_owner is null then
    raise exception 'Not authorised.' using errcode = 'insufficient_privilege';
  end if;
  if char_length(v_q) = 0 then
    return jsonb_build_object('people', '[]'::jsonb, 'transactions', '[]'::jsonb);
  end if;

  p_limit := least(greatest(coalesce(p_limit, 12), 1), 50);
  v_like  := '%' || replace(replace(v_q, '\', '\\'), '%', '\%') || '%';

  return jsonb_build_object(
    'people', coalesce((
      select jsonb_agg(to_jsonb(r))
      from (
        select pb.person_id, pb.name, pb.type, pb.phone, pb.net_balance,
               pb.net_balance_base, pb.currency, pb.base_currency, pb.is_archived
        from public.person_balances pb
        where pb.owner_id = v_owner
          and (pb.name ilike v_like or pb.phone ilike v_like or pb.email::text ilike v_like)
        order by pb.is_archived, (pb.name ilike (v_q || '%')) desc, pb.name
        limit p_limit
      ) r
    ), '[]'::jsonb),
    'transactions', coalesce((
      select jsonb_agg(to_jsonb(r))
      from (
        select t.id, t.person_id, pe.name as person_name, t.type, t.amount_minor,
               t.transaction_date, t.description,
               coalesce(pe.currency, public.owner_base_currency(v_owner)) as currency
        from public.transactions t
        join public.people pe on pe.id = t.person_id
        where t.owner_id = v_owner
          and not t.is_void
          and t.description ilike v_like
        order by t.transaction_date desc, t.created_at desc
        limit p_limit
      ) r
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.search_all(text, int) to authenticated;

-- -----------------------------------------------------------------------------
-- Activity feed pages carry each entry's own currency, because a workspace-wide
-- list is exactly where two currencies sit next to each other.
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
           coalesce(pe.currency, v_base) as currency,
           a.entered_amount_minor, a.entered_currency, a.exchange_rate_e9
    from public.activity_feed a
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

grant execute on function public.activity_page(int, int, text, date, date) to authenticated;

-- -----------------------------------------------------------------------------
-- Activity totals, converted to the base currency for the same reason.
-- -----------------------------------------------------------------------------

create or replace function public.activity_summary(
  p_bucket text default 'day',
  p_days   int  default 30
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
  v_unit  text;
begin
  v_unit := case lower(coalesce(p_bucket, 'day'))
              when 'week'  then 'week'
              when 'month' then 'month'
              else 'day'
            end;
  p_days := least(greatest(coalesce(p_days, 30), 1), 730);

  return coalesce((
    select jsonb_agg(to_jsonb(r) order by r.bucket)
    from (
      select date_trunc(v_unit, a.entry_date::timestamp)::date as bucket,
             coalesce(sum(public.convert_for_owner(v_owner, a.amount_minor, coalesce(pe.currency, v_base), v_base))
               filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0) as credit,
             coalesce(sum(public.convert_for_owner(v_owner, a.amount_minor, coalesce(pe.currency, v_base), v_base))
               filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)  as debit,
             coalesce(sum(public.convert_for_owner(v_owner, a.amount_minor, coalesce(pe.currency, v_base), v_base))
               filter (where a.entry_kind = 'settlement'), 0)                              as settled,
             count(*) as entries
      from public.activity_feed a
      join public.people pe on pe.id = a.person_id
      where a.owner_id = v_owner
        and not a.is_void
        and a.entry_date >= current_date - p_days
      group by 1
    ) r
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.activity_summary(text, int) to authenticated;

-- -----------------------------------------------------------------------------
-- Admin: the user directory shows each user's base currency, which it already
-- did; nothing about administration changes here. Re-granted for completeness
-- after the view rebuild in 0010.
-- -----------------------------------------------------------------------------

grant select on public.person_balances, public.owner_summary, public.activity_feed to authenticated;
