-- =============================================================================
-- 0003_engine.sql
-- THE accounting engine (context.md §10, §21).
--
-- This file is the single authoritative definition of every balance in the
-- product. Web, Android and Desktop all read these views/functions. No client
-- re-derives a balance from raw rows.
--
-- Core identities:
--   total_credit           = Σ credit transactions        (not void)
--   total_debit            = Σ debit transactions         (not void)
--   settled_in             = Σ settlements direction 'in' (not void)
--   settled_out            = Σ settlements direction 'out'(not void)
--   outstanding_receivable = total_credit - settled_in
--   outstanding_payable    = total_debit  - settled_out
--   net_balance            = outstanding_receivable - outstanding_payable
--
--   net_balance > 0  -> the person owes the user   (receivable)
--   net_balance < 0  -> the user owes the person   (payable)
--
-- Every money expression is cast back to bigint. sum() over a bigint returns
-- numeric, and numeric would reach the clients as a decimal string — the exact
-- floating-point-shaped hazard context.md §7 forbids. Minor units are integers
-- at every layer, so the cast is part of the contract, not tidiness.
--
-- All views are security_invoker so RLS on the base tables governs every read.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Per-person balances
--
-- Dropped rather than replaced: CREATE OR REPLACE VIEW cannot change a column's
-- type, and re-running this file after a column type changes must succeed.
-- Grants are re-applied by 0005_rls.sql, which therefore has to run after this.
-- -----------------------------------------------------------------------------

drop view if exists public.owner_summary;
drop view if exists public.activity_feed;
drop view if exists public.person_balances;

create or replace view public.person_balances
with (security_invoker = true) as
select
  p.id                              as person_id,
  p.owner_id,
  p.name,
  p.type,
  p.phone,
  p.email,
  p.is_archived,
  coalesce(t.total_credit, 0)::bigint                                as total_credit,
  coalesce(t.total_debit, 0)::bigint                                 as total_debit,
  coalesce(s.settled_in, 0)::bigint                                  as settled_in,
  coalesce(s.settled_out, 0)::bigint                                 as settled_out,
  (coalesce(s.settled_in, 0) + coalesce(s.settled_out, 0))::bigint   as total_settled,
  (coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))::bigint  as outstanding_receivable,
  (coalesce(t.total_debit, 0)  - coalesce(s.settled_out, 0))::bigint as outstanding_payable,
  ((coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))
    - (coalesce(t.total_debit, 0) - coalesce(s.settled_out, 0)))::bigint as net_balance,
  coalesce(t.txn_count, 0)::bigint                                   as transaction_count,
  greatest(t.last_activity_at, s.last_activity_at)                   as last_activity_at
from public.people p
left join lateral (
  select
    sum(tr.amount_minor) filter (where tr.type = 'credit') as total_credit,
    sum(tr.amount_minor) filter (where tr.type = 'debit')  as total_debit,
    count(*)                                               as txn_count,
    max(tr.transaction_date)                               as last_activity_at
  from public.transactions tr
  where tr.person_id = p.id
    and not tr.is_void
) t on true
left join lateral (
  select
    sum(se.amount_minor) filter (where se.direction = 'in')  as settled_in,
    sum(se.amount_minor) filter (where se.direction = 'out') as settled_out,
    max(se.settlement_date)                                  as last_activity_at
  from public.settlements se
  where se.person_id = p.id
    and not se.is_void
) s on true;

comment on view public.person_balances is
  'Authoritative per-person accounting position. Amounts are integer minor units.';

-- -----------------------------------------------------------------------------
-- Whole-workspace totals (context.md §13, §30)
--
-- Global receivable/payable deliberately sum the PER-PERSON net positions
-- rather than the raw column totals, so a person you both owe and are owed by
-- is reported once, on the side they actually land. This is what a user means
-- by "how much am I owed".
-- -----------------------------------------------------------------------------

create or replace view public.owner_summary
with (security_invoker = true) as
select
  pb.owner_id,
  coalesce(sum(pb.net_balance) filter (where pb.net_balance > 0), 0)::bigint  as total_receivable,
  coalesce(-sum(pb.net_balance) filter (where pb.net_balance < 0), 0)::bigint as total_payable,
  coalesce(sum(pb.net_balance), 0)::bigint                                    as net_position,
  count(*) filter (where pb.net_balance <> 0)::bigint                         as people_with_balance,
  count(*)::bigint                                                            as people_count,
  coalesce(sum(pb.total_credit), 0)::bigint                                   as gross_credit,
  coalesce(sum(pb.total_debit), 0)::bigint                                    as gross_debit,
  coalesce(sum(pb.total_settled), 0)::bigint                                  as gross_settled
from public.person_balances pb
where not pb.is_archived
group by pb.owner_id;

comment on view public.owner_summary is
  'Dashboard headline numbers for the calling user. Archived people are excluded.';

-- -----------------------------------------------------------------------------
-- Unified activity feed: transactions and settlements in one chronological
-- stream (context.md §13 recent activity, §16 person timeline).
-- -----------------------------------------------------------------------------

create or replace view public.activity_feed
with (security_invoker = true) as
select
  t.id,
  t.owner_id,
  t.person_id,
  'transaction'::text                                   as entry_kind,
  t.type::text                                          as entry_type,
  case t.type when 'credit' then 'in' else 'out' end    as money_direction,
  t.amount_minor,
  t.transaction_date                                    as entry_date,
  t.description                                         as note,
  t.is_void,
  null::uuid                                            as related_transaction_id,
  t.created_at
from public.transactions t
union all
select
  s.id,
  s.owner_id,
  s.person_id,
  'settlement'::text,
  s.direction::text,
  s.direction::text,
  s.amount_minor,
  s.settlement_date,
  s.note,
  s.is_void,
  s.transaction_id,
  s.created_at
from public.settlements s;

comment on view public.activity_feed is
  'Chronological union of transactions and settlements. Order by entry_date desc, created_at desc.';

-- -----------------------------------------------------------------------------
-- Per-transaction settlement status (context.md §16).
--
-- Balances never depend on this: it exists so the timeline can honestly show
-- "settled / partially settled / open" per row.
--
-- Allocation rule, per person and per direction:
--   1. A settlement that names a transaction is applied to that transaction
--      first (that is what the user pressed Settle on).
--   2. Any remainder spills onto the oldest still-open transaction of the same
--      direction (FIFO by transaction_date, then created_at).
-- Deterministic, and identical on every client because only this function
-- computes it.
-- -----------------------------------------------------------------------------

create or replace function public.transaction_settlement_status(p_person_id uuid)
returns table (
  transaction_id   uuid,
  amount_minor     bigint,
  settled_minor    bigint,
  remaining_minor  bigint,
  status           text
)
language plpgsql
stable
as $$
declare
  v_dir      public.settlement_direction;
  v_type     public.txn_type;
  v_ids      uuid[];
  v_amounts  bigint[];
  v_rem      bigint[];
  v_n        int;
  v_i        int;
  v_pos      int;
  v_left     bigint;
  v_take     bigint;
  r_settle   record;
begin
  foreach v_dir in array array['in', 'out']::public.settlement_direction[] loop
    v_type := case v_dir when 'in' then 'credit'::public.txn_type
                         else 'debit'::public.txn_type end;

    select array_agg(t.id order by t.transaction_date, t.created_at, t.id),
           array_agg(t.amount_minor order by t.transaction_date, t.created_at, t.id)
      into v_ids, v_amounts
    from public.transactions t
    where t.person_id = p_person_id
      and t.type = v_type
      and not t.is_void;

    if v_ids is null then
      continue;
    end if;

    v_n   := array_length(v_ids, 1);
    v_rem := v_amounts;

    for r_settle in
      select s.amount_minor, s.transaction_id
      from public.settlements s
      where s.person_id = p_person_id
        and s.direction = v_dir
        and not s.is_void
      order by s.settlement_date, s.created_at, s.id
    loop
      v_left := r_settle.amount_minor;

      -- 1. targeted allocation
      if r_settle.transaction_id is not null then
        v_pos := array_position(v_ids, r_settle.transaction_id);
        if v_pos is not null and v_rem[v_pos] > 0 then
          v_take        := least(v_left, v_rem[v_pos]);
          v_rem[v_pos]  := v_rem[v_pos] - v_take;
          v_left        := v_left - v_take;
        end if;
      end if;

      -- 2. FIFO spill
      v_i := 1;
      while v_left > 0 and v_i <= v_n loop
        if v_rem[v_i] > 0 then
          v_take      := least(v_left, v_rem[v_i]);
          v_rem[v_i]  := v_rem[v_i] - v_take;
          v_left      := v_left - v_take;
        end if;
        v_i := v_i + 1;
      end loop;
      -- Any v_left still > 0 means an over-settlement, which the constraint
      -- trigger in 0002 prevents. Nothing to do here.
    end loop;

    for v_i in 1 .. v_n loop
      transaction_id  := v_ids[v_i];
      amount_minor    := v_amounts[v_i];
      remaining_minor := v_rem[v_i];
      settled_minor   := v_amounts[v_i] - v_rem[v_i];
      status := case
                  when v_rem[v_i] = 0             then 'settled'
                  when v_rem[v_i] = v_amounts[v_i] then 'open'
                  else 'partial'
                end;
      return next;
    end loop;
  end loop;
end;
$$;

grant execute on function public.transaction_settlement_status(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Dashboard payload in one round trip (context.md §13, §23 "no N+1").
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
  v_owner   uuid := public.current_owner();
  v_result  jsonb;
begin
  if v_owner is null then
    raise exception 'Not authorised.' using errcode = 'insufficient_privilege';
  end if;

  p_activity_limit := least(greatest(coalesce(p_activity_limit, 10), 1), 50);
  p_people_limit   := least(greatest(coalesce(p_people_limit, 8), 1), 50);

  select jsonb_build_object(
    'profile', (
      select to_jsonb(x) from (
        select p.id, p.name, p.email, p.phone, p.business_name, p.avatar_url, p.currency
        from public.profiles p where p.id = v_owner
      ) x
    ),
    'summary', coalesce(
      (select to_jsonb(s) from public.owner_summary s where s.owner_id = v_owner),
      jsonb_build_object(
        'owner_id', v_owner,
        'total_receivable', 0, 'total_payable', 0, 'net_position', 0,
        'people_with_balance', 0, 'people_count', 0,
        'gross_credit', 0, 'gross_debit', 0, 'gross_settled', 0
      )
    ),
    'today', (
      select jsonb_build_object(
        'credit',  coalesce(sum(a.amount_minor) filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0)::bigint,
        'debit',   coalesce(sum(a.amount_minor) filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)::bigint,
        'settled', coalesce(sum(a.amount_minor) filter (where a.entry_kind = 'settlement'), 0)::bigint,
        'count',   count(*)::bigint
      )
      from public.activity_feed a
      where a.owner_id = v_owner and not a.is_void and a.entry_date = current_date
    ),
    'recent_activity', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.person_id, pe.name as person_name, a.entry_kind, a.entry_type,
               a.amount_minor, a.entry_date, a.note, a.created_at
        from public.activity_feed a
        join public.people pe on pe.id = a.person_id
        where a.owner_id = v_owner and not a.is_void
        order by a.entry_date desc, a.created_at desc
        limit p_activity_limit
      ) r
    ), '[]'::jsonb),
    'people_with_balance', coalesce((
      select jsonb_agg(to_jsonb(r) order by abs(r.net_balance) desc)
      from (
        select pb.person_id, pb.name, pb.type, pb.net_balance,
               pb.outstanding_receivable, pb.outstanding_payable, pb.last_activity_at
        from public.person_balances pb
        where pb.owner_id = v_owner and not pb.is_archived and pb.net_balance <> 0
        order by abs(pb.net_balance) desc
        limit p_people_limit
      ) r
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.dashboard(int, int) to authenticated;

-- -----------------------------------------------------------------------------
-- Global search (context.md §15). People first, then transaction notes.
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
        select pb.person_id, pb.name, pb.type, pb.phone, pb.net_balance, pb.is_archived
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
               t.transaction_date, t.description
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
