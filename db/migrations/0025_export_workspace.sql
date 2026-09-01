-- =============================================================================
-- 0025_export_workspace.sql
-- Data portability (milestone 1.9.0, Phases 4–6).
--
-- The product could already print one person's statement. It could not answer
-- "give me my books" — which is the question a user asks before they trust an
-- accounting app with years of entries, and the question a backup answers.
--
-- Two functions, because the two halves scale differently:
--
--   export_workspace()  — the header: who, when, which filters, which
--                         currencies, every person and their balances, and the
--                         counts. Bounded by the number of people.
--   export_entries()    — the ledger itself, paged. Unbounded in principle,
--                         so it is never returned in one lump.
--
-- Both are SECURITY INVOKER and start at assert_caller(), exactly like
-- person_page() and dashboard(). That is the whole authorization story: RLS is
-- in force for the caller's own role, so an export cannot reach another
-- workspace even if a person id from one is passed in by hand. Nothing here
-- runs as the definer, and nothing here reads a table the caller could not
-- already select from.
--
-- Additive: no existing object is altered, and the statement PDF path
-- (person_page) is untouched.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- The filter contract, stated once.
--
-- Every filter is optional and every one is applied identically by both
-- functions, so a header and its pages always describe the same slice:
--
--   p_from / p_to     entry_date bounds, inclusive
--   p_person_id       one account
--   p_currency        the currency the entry was MADE in, not the base one —
--                     an export must not silently restate money
--   p_kinds           any of credit, debit, settlement
--   p_scope           all | regular | opening
--   p_include_void    voided history is excluded unless it is asked for
-- -----------------------------------------------------------------------------

create or replace function public.export_filters(
  p_from         date,
  p_to           date,
  p_person_id    uuid,
  p_currency     text,
  p_kinds        text[],
  p_scope        text,
  p_include_void boolean
)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object(
    'from',         p_from,
    'to',           p_to,
    'person_id',    p_person_id,
    'currency',     nullif(upper(coalesce(p_currency, '')), ''),
    'kinds',        case
                      when p_kinds is null or cardinality(p_kinds) = 0 then null
                      else to_jsonb(p_kinds)
                    end,
    'scope',        coalesce(nullif(lower(coalesce(p_scope, '')), ''), 'all'),
    'include_void', coalesce(p_include_void, false)
  )
$$;

comment on function public.export_filters(date, date, uuid, text, text[], text, boolean) is
  'Normalises the export filter set. Echoed back in every export so a file says what it contains.';

-- -----------------------------------------------------------------------------
-- export_workspace() — the header of an export.
-- -----------------------------------------------------------------------------

create or replace function public.export_workspace(
  p_from         date    default null,
  p_to           date    default null,
  p_person_id    uuid    default null,
  p_currency     text    default null,
  p_kinds        text[]  default null,
  p_scope        text    default 'all',
  p_include_void boolean default false
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_owner    uuid := public.assert_caller();
  v_currency text := nullif(upper(coalesce(p_currency, '')), '');
  v_scope    text := coalesce(nullif(lower(coalesce(p_scope, '')), ''), 'all');
  v_void     boolean := coalesce(p_include_void, false);
  v_kinds    text[] := case
                         when p_kinds is null or cardinality(p_kinds) = 0 then null
                         else p_kinds
                       end;
begin
  if v_scope not in ('all', 'regular', 'opening') then
    raise exception 'Unknown export scope: %', v_scope using errcode = 'invalid_parameter_value';
  end if;

  return jsonb_build_object(
    'schema_version', 1,
    'generator',      'accounic',
    'exported_at',    to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'filters',        public.export_filters(p_from, p_to, p_person_id, p_currency,
                                            p_kinds, p_scope, p_include_void),

    'workspace', (
      select jsonb_build_object(
        'owner_id',      pr.id,
        'name',          pr.name,
        'business_name', pr.business_name,
        'email',         pr.email,
        'phone',         pr.phone,
        'base_currency', pr.currency,
        'member_since',  pr.created_at
      )
      from public.profiles pr
      where pr.id = v_owner
    ),

    -- The workspace position as the engine states it. Never recomputed here:
    -- an export that disagreed with the dashboard would be worse than none.
    'summary', (select to_jsonb(s) from public.owner_summary s where s.owner_id = v_owner),

    -- And the same position kept per entry currency, taken from dashboard()
    -- rather than re-derived, for the same reason. This is the WORKSPACE
    -- position: it is deliberately not narrowed by the export's filters, and
    -- every writer labels it as such.
    'totals_by_currency', coalesce(public.dashboard(1, 1) -> 'totals_by_currency', '[]'::jsonb),

    -- Only the currencies that carry entries, with their minor-unit exponent,
    -- so a reader of the file can interpret every integer in it without
    -- knowing anything about Accounic.
    'currencies', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code', c.code, 'name', c.name, 'symbol', c.symbol, 'decimals', c.decimals)
               order by c.code)
      from public.currencies c
      where c.code in (
        select e.entry_currency from public.activity_entries e where e.owner_id = v_owner
        union
        select p.ledger_currency from public.people p where p.owner_id = v_owner
        union
        select public.owner_base_currency(v_owner)
      )
    ), '[]'::jsonb),

    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id',              p.id,
               'name',            p.name,
               'type',            p.type,
               'phone',           p.phone,
               'email',           p.email,
               'address',         p.address,
               'notes',           p.notes,
               'is_archived',     p.is_archived,
               'currency',        p.currency,
               'ledger_currency', p.ledger_currency,
               'created_at',      p.created_at,
               'balance',         (select to_jsonb(b) from public.person_balances b
                                   where b.person_id = p.id and b.owner_id = v_owner),
               'opening',         (select to_jsonb(o) from public.person_opening o
                                   where o.person_id = p.id and o.owner_id = v_owner)
             ) order by p.name, p.id)
      from public.people p
      where p.owner_id = v_owner
        and (p_person_id is null or p.id = p_person_id)
    ), '[]'::jsonb),

    'counts', (
      select jsonb_build_object(
        'people',  (select count(*) from public.people p
                    where p.owner_id = v_owner
                      and (p_person_id is null or p.id = p_person_id)),
        'entries',      count(*),
        'transactions', count(*) filter (where e.entry_kind = 'transaction'),
        'settlements',  count(*) filter (where e.entry_kind = 'settlement'),
        'transfers',    count(*) filter (where e.transfer_id is not null),
        'opening',      count(*) filter (where e.opening_scope),
        'voided',       count(*) filter (where e.is_void)
      )
      from public.activity_entries e
      where e.owner_id = v_owner
        and (p_person_id is null or e.person_id = p_person_id)
        and (p_from     is null or e.entry_date >= p_from)
        and (p_to       is null or e.entry_date <= p_to)
        and (v_currency is null or e.entry_currency = v_currency)
        and (v_kinds    is null or
             (case when e.entry_kind = 'settlement' then 'settlement' else e.entry_type end) = any (v_kinds))
        -- opening_scope is the boolean the engine sets: true for every row of
        -- the opening book, transaction or settlement (0022).
        and (v_scope = 'all'
             or (v_scope = 'opening' and e.opening_scope)
             or (v_scope = 'regular' and not e.opening_scope))
        and (v_void or not e.is_void)
    )
  );
end;
$$;

comment on function public.export_workspace(date, date, uuid, text, text[], text, boolean) is
  'The header of a workspace export: profile, position, currencies in use, every person with balances, and the counts for the filtered slice. SECURITY INVOKER — RLS decides what is visible.';

-- -----------------------------------------------------------------------------
-- export_entries() — the ledger, one page at a time.
--
-- Every row carries the figure as ENTERED and its base equivalent, the rate and
-- where the rate came from, whether it belongs to the opening book or the
-- regular one, and — for a transaction — how much of it has been settled. That
-- is enough to rebuild a statement, or to reconcile the file against the app.
-- -----------------------------------------------------------------------------

create or replace function public.export_entries(
  p_from         date    default null,
  p_to           date    default null,
  p_person_id    uuid    default null,
  p_currency     text    default null,
  p_kinds        text[]  default null,
  p_scope        text    default 'all',
  p_include_void boolean default false,
  p_limit        int     default 1000,
  p_offset       int     default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
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
        'amount_base_minor',     g.amount_base_minor,
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
$$;

comment on function public.export_entries(date, date, uuid, text, text[], text, boolean, int, int) is
  'One page of the filtered ledger for an export: every entry with the figure as entered, its base equivalent, its rate provenance, its book, and its settled state. SECURITY INVOKER.';

revoke all on function public.export_filters(date, date, uuid, text, text[], text, boolean) from public;
revoke all on function public.export_workspace(date, date, uuid, text, text[], text, boolean) from public;
revoke all on function public.export_entries(date, date, uuid, text, text[], text, boolean, int, int) from public;

grant execute on function public.export_filters(date, date, uuid, text, text[], text, boolean) to authenticated;
grant execute on function public.export_workspace(date, date, uuid, text, text[], text, boolean) to authenticated;
grant execute on function public.export_entries(date, date, uuid, text, text[], text, boolean, int, int) to authenticated;
