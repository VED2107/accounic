-- =============================================================================
-- 0008_activity.sql
-- Paginated workspace activity (context.md §16, §23, §30).
--
-- activity_feed is a UNION view, so PostgREST cannot embed people through it —
-- a view carries no foreign key metadata. Rather than make the client issue an
-- N+1 of name lookups, the join happens here and the page ships in one call.
-- =============================================================================

create or replace function public.activity_page(
  p_limit    int  default 40,
  p_offset   int  default 0,
  p_kind     text default null,   -- 'transaction' | 'settlement' | null for both
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
           a.amount_minor, a.entry_date, a.note, a.created_at
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

  return jsonb_build_object(
    'items', v_rows,
    'total', v_total,
    'has_more', (p_offset + p_limit) < v_total
  );
end;
$$;

grant execute on function public.activity_page(int, int, text, date, date) to authenticated;

-- -----------------------------------------------------------------------------
-- Activity totals by period (context.md §30 "daily / weekly / monthly").
-- Deliberately the whole of v1 reporting: three numbers per bucket, nothing more.
-- -----------------------------------------------------------------------------

create or replace function public.activity_summary(
  p_bucket text default 'day',   -- 'day' | 'week' | 'month'
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
             coalesce(sum(a.amount_minor) filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0) as credit,
             coalesce(sum(a.amount_minor) filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)  as debit,
             coalesce(sum(a.amount_minor) filter (where a.entry_kind = 'settlement'), 0)                              as settled,
             count(*) as entries
      from public.activity_feed a
      where a.owner_id = v_owner
        and not a.is_void
        and a.entry_date >= current_date - p_days
      group by 1
    ) r
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.activity_summary(text, int) to authenticated;
