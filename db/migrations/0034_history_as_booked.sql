-- =============================================================================
-- 0034_history_as_booked.sql
-- A historical row is never re-priced at today's exchange rate.
--
-- THE BUG
--
-- `activity_entries.amount_base_minor` is
--   convert_for_owner(owner, amount_minor, ledger_currency, base_currency)
-- — the row's ledger figure converted into the workspace currency at the rate
-- cached TODAY. Every row list handed it to the clients as that row's
-- workspace-currency equivalent: the person timeline, settlement and opening
-- activity, the Activity page, exports and the dashboard's recent activity.
-- A dirham entry booked at ₹23 read ₹24.50 the day the rate moved, and the
-- history stopped adding up to anything the ledger recorded.
--
-- THE FIX
--
-- A new column, `amount_base_booked_minor`: the row in the workspace currency
-- as it was BOOKED, from what was stored when it was entered.
--
--   * account kept in the workspace currency -> amount_minor (the ledger froze
--     any foreign entry at its own historical or manual rate);
--   * entered in the workspace currency      -> what was typed, at face;
--   * otherwise                              -> NULL. No rate into the
--     workspace currency was ever recorded for that row, and one is not
--     invented: the clients show the ledger figure and no workspace figure.
--
-- `amount_base_minor` itself is unchanged, because dashboard() SUMS it for its
-- "today" figures and the dashboard's totals are not changed here. The row
-- lists below hand the booked column out under the old key, so both clients
-- keep their field and already read null as "no equivalent".
--
-- Additive and read-only: no table is touched, no stored amount or rate is
-- rewritten. The view gains one trailing column (allowed by CREATE OR REPLACE
-- VIEW); security_invoker is restated and grants survive a replace.
--
-- The four functions are transcribed from the live catalogue
-- (pg_get_functiondef) and edited ONLY at that one select item each; every
-- returned key is otherwise byte-identical. dashboard()'s totals
-- (summary, cash_in_hand, opening, today, totals_by_currency) are untouched —
-- only its recent_activity rows change.
-- =============================================================================

CREATE OR REPLACE VIEW public.activity_entries WITH (security_invoker = true) AS
SELECT a.id,
    a.owner_id,
    a.person_id,
    a.entry_kind,
    a.entry_type,
    a.money_direction,
    a.amount_minor,
    a.entry_date,
    a.note,
    a.is_void,
    a.is_opening,
    a.entered_amount_minor,
    a.entered_currency,
    a.exchange_rate_e9,
    a.exchange_rate_at,
    a.exchange_rate_source,
    a.conversion_mode,
    a.auto_converted_amount_minor,
    a.related_transaction_id,
    a.created_at,
    a.transfer_id,
    a.transfer_role,
    a.transfer_counterparty_id,
    a.opening_role,
    a.opening_scope,
    COALESCE(pe.ledger_currency, pe.currency, owner_base_currency(a.owner_id)) AS ledger_currency,
    COALESCE(a.entered_amount_minor, a.amount_minor) AS entry_amount_minor,
    COALESCE(a.entered_currency, pe.ledger_currency, pe.currency, owner_base_currency(a.owner_id)) AS entry_currency,
    owner_base_currency(a.owner_id) AS base_currency,
    convert_for_owner(a.owner_id, a.amount_minor, COALESCE(pe.ledger_currency, pe.currency, owner_base_currency(a.owner_id)), owner_base_currency(a.owner_id)) AS amount_base_minor,
    -- 0034: the row in the workspace currency AS BOOKED. No rate is applied.
    CASE
        WHEN COALESCE(pe.ledger_currency, pe.currency, owner_base_currency(a.owner_id)) = owner_base_currency(a.owner_id) THEN a.amount_minor
        WHEN COALESCE(a.entered_currency, pe.ledger_currency, pe.currency, owner_base_currency(a.owner_id)) = owner_base_currency(a.owner_id) THEN COALESCE(a.entered_amount_minor, a.amount_minor)
        ELSE NULL::bigint
    END AS amount_base_booked_minor
   FROM activity_feed a
     JOIN people pe ON pe.id = a.person_id;

CREATE OR REPLACE FUNCTION public.person_page(p_person_id uuid, p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
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
               a.amount_base_booked_minor as amount_base_minor, a.base_currency,
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
               a.ledger_currency, a.amount_base_booked_minor as amount_base_minor, a.base_currency,
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
               a.ledger_currency, a.amount_base_booked_minor as amount_base_minor, a.base_currency,
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
$function$;

CREATE OR REPLACE FUNCTION public.activity_page(p_limit integer DEFAULT 40, p_offset integer DEFAULT 0, p_kind text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
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
           a.amount_base_booked_minor as amount_base_minor, a.base_currency,
           a.entered_amount_minor, a.entered_currency, a.exchange_rate_e9,
           a.exchange_rate_source,
           a.conversion_mode, a.auto_converted_amount_minor,
           a.transfer_id, a.transfer_role, a.transfer_counterparty_id,
           cp.name as transfer_counterparty_name
    from public.activity_entries a
    join public.people pe on pe.id = a.person_id
    left join public.people cp on cp.id = a.transfer_counterparty_id
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
$function$;

CREATE OR REPLACE FUNCTION public.export_entries(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_person_id uuid DEFAULT NULL::uuid, p_currency text DEFAULT NULL::text, p_kinds text[] DEFAULT NULL::text[], p_scope text DEFAULT 'all'::text, p_include_void boolean DEFAULT false, p_limit integer DEFAULT 1000, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_owner    uuid := public.assert_caller();
  v_currency text := nullif(upper(coalesce(p_currency, '')), '');
  v_scope    text := coalesce(nullif(lower(coalesce(p_scope, '')), ''), 'all');
  v_void     boolean := coalesce(p_include_void, false);
  v_kinds    text[] := case
                         when p_kinds is null or cardinality(p_kinds) = 0 then null
                         else p_kinds
                       end;
  v_total    bigint;
  v_rows     jsonb;
begin
  if v_scope not in ('all', 'regular', 'opening') then
    raise exception 'Unknown export scope: %', v_scope using errcode = 'invalid_parameter_value';
  end if;

  -- A page is capped like every other paged RPC here. An export of a hundred
  -- thousand entries is a hundred pages, not one request that times out.
  p_limit  := least(greatest(coalesce(p_limit, 1000), 1), 5000);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  with filtered as (
    select e.*
    from public.activity_entries e
    where e.owner_id = v_owner
      and (p_person_id is null or e.person_id = p_person_id)
      and (p_from     is null or e.entry_date >= p_from)
      and (p_to       is null or e.entry_date <= p_to)
      and (v_currency is null or e.entry_currency = v_currency)
      and (v_kinds    is null or
           (case when e.entry_kind = 'settlement' then 'settlement' else e.entry_type end) = any (v_kinds))
      and (v_scope = 'all'
           or (v_scope = 'opening' and e.opening_scope)
           or (v_scope = 'regular' and not e.opening_scope))
      and (v_void or not e.is_void)
  ),
  counted as (select count(*) as total from filtered),
  page as (
    -- Deterministic to the last tie-break, so the same filters always produce
    -- the same file — which is what makes an export diffable and debuggable.
    select * from filtered
    order by entry_date, created_at, id
    limit p_limit offset p_offset
  ),
  -- The FIFO allocator is per person, so it is asked once per person on the
  -- page rather than once per row.
  people_on_page as (select distinct person_id from page),
  status as (
    select s.transaction_id, s.settled_minor, s.remaining_minor, s.status
    from people_on_page pp
    cross join lateral public.transaction_settlement_status(pp.person_id) s
  ),
  assembled as (
    select
      (select total from counted) as total,
      jsonb_agg(jsonb_build_object(
        'id',                    g.id,
        'kind',                  g.entry_kind,
        'type',                  g.entry_type,
        'direction',             g.money_direction,
        'date',                  g.entry_date,
        'person_id',             g.person_id,
        'person_name',           pe.name,
        'note',                  g.note,
        'is_void',               g.is_void,
        'scope',                 case when g.opening_scope then 'opening' else 'regular' end,
        'opening_role',          g.opening_role,
        'transfer_id',           g.transfer_id,
        'transfer_role',         g.transfer_role,
        'transfer_counterparty_id', g.transfer_counterparty_id,
        'related_transaction_id',   g.related_transaction_id,

        -- The money, three ways: as entered, as recorded in the account's
        -- ledger currency, and in the workspace's base currency.
        'entry_amount_minor',    g.entry_amount_minor,
        'entry_currency',        g.entry_currency,
        'amount_minor',          g.amount_minor,
        'ledger_currency',       g.ledger_currency,
        'amount_base_minor',     g.amount_base_booked_minor,
        'base_currency',         g.base_currency,

        'exchange_rate_e9',      g.exchange_rate_e9,
        'exchange_rate_source',  g.exchange_rate_source,
        'exchange_rate_at',      g.exchange_rate_at,
        'conversion_mode',       g.conversion_mode,

        'settled_minor',         st.settled_minor,
        'remaining_minor',       st.remaining_minor,
        'settlement_status',     case when g.entry_kind = 'transaction' then st.status end,

        'created_at',            g.created_at
      ) order by g.entry_date, g.created_at, g.id) as rows
    from page g
    left join public.people pe on pe.id = g.person_id and pe.owner_id = v_owner
    left join status st on st.transaction_id = g.id and g.entry_kind = 'transaction'
  )
  select total, rows into v_total, v_rows from assembled;

  return jsonb_build_object(
    'schema_version', 1,
    'filters',   public.export_filters(p_from, p_to, p_person_id, p_currency,
                                       p_kinds, p_scope, p_include_void),
    'limit',     p_limit,
    'offset',    p_offset,
    'total',     coalesce(v_total, 0),
    'has_more',  p_offset + p_limit < coalesce(v_total, 0),
    'entries',   coalesce(v_rows, '[]'::jsonb)
  );
end;
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
               a.amount_base_booked_minor as amount_base_minor, a.base_currency,
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

notify pgrst, 'reload schema';
