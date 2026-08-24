-- =============================================================================
-- 0010_currency.sql
-- Per-person currency, opening balances, and recorded currency conversion.
--
-- ADDITIVE ONLY. Nothing here drops, truncates or rewrites a ledger row:
--   * every new column is nullable or carries a default that reproduces today's
--     behaviour exactly,
--   * `people.currency` NULL means "the owner's base currency", which is what
--     every person created before today already meant implicitly,
--   * `amount_minor` keeps its meaning to the last digit — the amount, in minor
--     units, in the account's currency. Every balance that computed to a number
--     before this file ran computes to the same number after it.
--
-- The three things it adds:
--
--   1. A currency per person (`people.currency`), falling back to the owner's
--      base currency (`profiles.currency`) when unset.
--   2. Conversion provenance on every financial row: what the user actually
--      typed, in which currency, at what rate, when, and from which source.
--      The stored `amount_minor` is the account-currency amount derived from
--      those, computed here and never by a client.
--   3. Opening balances: a transaction flagged `is_opening`, so it flows
--      through the existing engine — and is therefore correct by construction —
--      while still being presentable as "Opening Balance" rather than as
--      something that happened today.
--
-- Money rule (context.md §7) still holds: integers everywhere. `numeric`
-- appears only inside the conversion helpers, between an integer input and an
-- integer output, because a rate is not money and rounding it once at the end
-- is the correct treatment.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Currency reference data (upgrade §19)
--
-- Generated from shared/currencies.json, which is also the source of
-- web/src/lib/currencies.ts and app/lib/core/currencies.dart. A test on each
-- side pins them together, so a currency cannot exist on one client and not
-- another. Regenerate the block below with:
--
--     node db/tools/sync-currencies.mjs
--
-- `decimals` is the ISO 4217 minor-unit exponent. It is not decoration: it is
-- what an integer `amount_minor` *means*. ¥1,000 is 1000 minor units and
-- ₹1,000 is 100000, and a conversion between the two has to know that.
-- -----------------------------------------------------------------------------

create table if not exists public.currencies (
  code      text     primary key,
  name      text     not null,
  symbol    text     not null,
  decimals  smallint not null default 2,
  is_active boolean  not null default true,

  constraint currencies_code_fmt check (code ~ '^[A-Z]{3}$'),
  constraint currencies_decimals check (decimals between 0 and 4)
);

comment on table public.currencies is
  'Supported currencies. Reference data, identical on every client (upgrade §19).';

-- @@CURRENCY_SEED_START@@
insert into public.currencies (code, name, symbol, decimals) values
  ('INR', 'Indian Rupee', '₹', 2),
  ('AED', 'UAE Dirham', 'د.إ', 2),
  ('USD', 'US Dollar', '$', 2),
  ('EUR', 'Euro', '€', 2),
  ('GBP', 'British Pound', '£', 2),
  ('JPY', 'Japanese Yen', '¥', 0),
  ('AUD', 'Australian Dollar', 'A$', 2),
  ('CAD', 'Canadian Dollar', 'C$', 2),
  ('SGD', 'Singapore Dollar', 'S$', 2),
  ('CHF', 'Swiss Franc', 'CHF', 2),
  ('CNY', 'Chinese Yuan', '¥', 2),
  ('HKD', 'Hong Kong Dollar', 'HK$', 2),
  ('NZD', 'New Zealand Dollar', 'NZ$', 2),
  ('SAR', 'Saudi Riyal', '﷼', 2),
  ('QAR', 'Qatari Riyal', '﷼', 2),
  ('KWD', 'Kuwaiti Dinar', 'د.ك', 3),
  ('BHD', 'Bahraini Dinar', '.د.ب', 3),
  ('OMR', 'Omani Rial', '﷼', 3),
  ('JOD', 'Jordanian Dinar', 'د.ا', 3),
  ('LKR', 'Sri Lankan Rupee', 'Rs', 2),
  ('NPR', 'Nepalese Rupee', 'रू', 2),
  ('PKR', 'Pakistani Rupee', '₨', 2),
  ('BDT', 'Bangladeshi Taka', '৳', 2),
  ('MYR', 'Malaysian Ringgit', 'RM', 2),
  ('THB', 'Thai Baht', '฿', 2),
  ('IDR', 'Indonesian Rupiah', 'Rp', 2),
  ('PHP', 'Philippine Peso', '₱', 2),
  ('VND', 'Vietnamese Dong', '₫', 0),
  ('KRW', 'South Korean Won', '₩', 0),
  ('ZAR', 'South African Rand', 'R', 2),
  ('NGN', 'Nigerian Naira', '₦', 2),
  ('KES', 'Kenyan Shilling', 'KSh', 2),
  ('EGP', 'Egyptian Pound', 'E£', 2),
  ('TRY', 'Turkish Lira', '₺', 2),
  ('RUB', 'Russian Ruble', '₽', 2),
  ('BRL', 'Brazilian Real', 'R$', 2),
  ('MXN', 'Mexican Peso', 'Mex$', 2),
  ('SEK', 'Swedish Krona', 'kr', 2),
  ('NOK', 'Norwegian Krone', 'kr', 2),
  ('DKK', 'Danish Krone', 'kr', 2),
  ('PLN', 'Polish Zloty', 'zł', 2),
  ('CZK', 'Czech Koruna', 'Kč', 2),
  ('HUF', 'Hungarian Forint', 'Ft', 2),
  ('RON', 'Romanian Leu', 'lei', 2),
  ('ILS', 'Israeli Shekel', '₪', 2),
  ('TWD', 'New Taiwan Dollar', 'NT$', 2)
on conflict (code) do update
  set name      = excluded.name,
      symbol    = excluded.symbol,
      decimals  = excluded.decimals,
      is_active = true;
-- @@CURRENCY_SEED_END@@

-- Reference data: readable by anyone signed in, writable by nobody but the
-- service role — no policy grants a write.
alter table public.currencies enable row level security;

drop policy if exists currencies_read_all on public.currencies;
create policy currencies_read_all on public.currencies
  for select to authenticated using (true);

revoke all on public.currencies from anon, authenticated;
grant select on public.currencies to authenticated;

create or replace function public.currency_decimals(p_code text)
returns smallint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select c.decimals from public.currencies c where c.code = upper(p_code)),
    2::smallint
  );
$$;

create or replace function public.is_supported_currency(p_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.currencies c
    where c.code = upper(coalesce(p_code, '')) and c.is_active
  );
$$;

revoke all on function public.currency_decimals(text)     from public;
revoke all on function public.is_supported_currency(text) from public;
grant execute on function public.currency_decimals(text)     to authenticated, service_role;
grant execute on function public.is_supported_currency(text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. Per-person currency (upgrade §1)
--
-- NULL is deliberate and load-bearing: it means "whatever the owner's base
-- currency is", which is precisely what every person created before today
-- meant. Backfilling a literal would freeze those people to the base currency
-- as it stood at migration time, and would rewrite rows to say something the
-- database already knew.
-- -----------------------------------------------------------------------------

alter table public.people
  add column if not exists currency text;

do $$ begin
  alter table public.people
    add constraint people_currency_fmt check (currency is null or currency ~ '^[A-Z]{3}$');
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.people
    add constraint people_currency_known
    foreign key (currency) references public.currencies (code);
exception when duplicate_object then null; end $$;

comment on column public.people.currency is
  'Account currency for this person. NULL = the owner''s base currency (profiles.currency).';

-- The owner's base currency, without a join that RLS would also have to allow.
-- SECURITY DEFINER so a view can resolve it for rows the caller can already
-- see, and for nothing else: it returns one three-letter code.
create or replace function public.owner_base_currency(p_owner uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select p.currency from public.profiles p where p.id = p_owner), 'INR');
$$;

create or replace function public.person_currency(p_person_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p.currency, public.owner_base_currency(p.owner_id))
  from public.people p
  where p.id = p_person_id;
$$;

revoke all on function public.owner_base_currency(uuid) from public;
revoke all on function public.person_currency(uuid)     from public;
grant execute on function public.owner_base_currency(uuid) to authenticated, service_role;
grant execute on function public.person_currency(uuid)     to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. Conversion provenance on the ledger rows (upgrade §2, §8)
--
-- `amount_minor` remains the account-currency amount, and remains the only
-- thing any balance is computed from. These columns record what the user
-- actually handed over, so the conversion can be reproduced and audited years
-- later. They are NULL on every existing row, which reads as "entered in the
-- account currency" — which is true.
-- -----------------------------------------------------------------------------

alter table public.transactions
  add column if not exists is_opening           boolean not null default false,
  add column if not exists entered_amount_minor bigint,
  add column if not exists entered_currency     text,
  add column if not exists exchange_rate_e9     bigint,
  add column if not exists exchange_rate_at     timestamptz,
  add column if not exists exchange_rate_source text;

alter table public.settlements
  add column if not exists entered_amount_minor bigint,
  add column if not exists entered_currency     text,
  add column if not exists exchange_rate_e9     bigint,
  add column if not exists exchange_rate_at     timestamptz,
  add column if not exists exchange_rate_source text;

do $$ begin
  alter table public.transactions add constraint transactions_conversion_complete check (
    (entered_amount_minor is null and entered_currency is null and exchange_rate_e9 is null)
    or (entered_amount_minor is not null and entered_currency is not null and exchange_rate_e9 is not null)
  );
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.transactions add constraint transactions_entered_sane check (
    (entered_amount_minor is null or (entered_amount_minor > 0 and entered_amount_minor <= 9223372036854))
    and (entered_currency is null or entered_currency ~ '^[A-Z]{3}$')
    and (exchange_rate_e9 is null or exchange_rate_e9 > 0)
    and (exchange_rate_source is null or char_length(exchange_rate_source) <= 60)
  );
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.settlements add constraint settlements_conversion_complete check (
    (entered_amount_minor is null and entered_currency is null and exchange_rate_e9 is null)
    or (entered_amount_minor is not null and entered_currency is not null and exchange_rate_e9 is not null)
  );
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.settlements add constraint settlements_entered_sane check (
    (entered_amount_minor is null or (entered_amount_minor > 0 and entered_amount_minor <= 9223372036854))
    and (entered_currency is null or entered_currency ~ '^[A-Z]{3}$')
    and (exchange_rate_e9 is null or exchange_rate_e9 > 0)
    and (exchange_rate_source is null or char_length(exchange_rate_source) <= 60)
  );
exception when duplicate_object then null; end $$;

comment on column public.transactions.entered_amount_minor is
  'What the user actually typed, in minor units of entered_currency. NULL = entered in the account currency.';
comment on column public.transactions.exchange_rate_e9 is
  'Rate used, x1e9: one unit of entered_currency = exchange_rate_e9/1e9 units of the account currency. Frozen at entry.';
comment on column public.transactions.is_opening is
  'A balance carried in from before the account existed, not something that happened that day (upgrade §3).';

-- One opening balance per person. Voided ones do not count, so a mistaken
-- opening balance can be retracted and re-entered.
create unique index if not exists transactions_one_opening_per_person
  on public.transactions (person_id)
  where is_opening and not is_void;

-- -----------------------------------------------------------------------------
-- 4. Exchange-rate cache (upgrade §6, §7)
--
-- Per owner, not global. A shared table would let any signed-in user poison the
-- rate every other user's conversions are computed from. Scoped to the owner it
-- is still shared across that user's web, Windows and Android clients, which is
-- what makes a rate fetched on one device available offline on another.
--
-- A row means: one unit of `base` costs rate_e9/1e9 units of `quote`.
-- -----------------------------------------------------------------------------

create table if not exists public.exchange_rates (
  owner_id   uuid   not null references public.profiles (id) on delete cascade,
  base       text   not null,
  quote      text   not null,
  rate_e9    bigint not null,
  as_of      date   not null,
  source     text   not null,
  fetched_at timestamptz not null default now(),

  primary key (owner_id, base, quote),
  constraint exchange_rates_base_fmt   check (base  ~ '^[A-Z]{3}$'),
  constraint exchange_rates_quote_fmt  check (quote ~ '^[A-Z]{3}$'),
  constraint exchange_rates_distinct   check (base <> quote),
  constraint exchange_rates_positive   check (rate_e9 > 0),
  constraint exchange_rates_source_len check (char_length(source) between 1 and 60)
);

comment on table public.exchange_rates is
  'Cached reference rates, per owner. One row = one unit of base costs rate_e9/1e9 quote.';

alter table public.exchange_rates enable row level security;
alter table public.exchange_rates force row level security;

revoke all on public.exchange_rates from anon, authenticated;
grant select, insert, update, delete on public.exchange_rates to authenticated;

drop policy if exists exchange_rates_select_own on public.exchange_rates;
create policy exchange_rates_select_own on public.exchange_rates
  for select to authenticated using (owner_id = public.current_owner());

drop policy if exists exchange_rates_insert_own on public.exchange_rates;
create policy exchange_rates_insert_own on public.exchange_rates
  for insert to authenticated with check (owner_id = public.current_owner());

drop policy if exists exchange_rates_update_own on public.exchange_rates;
create policy exchange_rates_update_own on public.exchange_rates
  for update to authenticated
  using (owner_id = public.current_owner())
  with check (owner_id = public.current_owner());

drop policy if exists exchange_rates_delete_own on public.exchange_rates;
create policy exchange_rates_delete_own on public.exchange_rates
  for delete to authenticated using (owner_id = public.current_owner());

create index if not exists exchange_rates_owner_asof_idx
  on public.exchange_rates (owner_id, as_of desc);

-- -----------------------------------------------------------------------------
-- 5. Conversion helpers
--
-- The single source of truth for turning an amount in one currency into an
-- amount in another. Clients display conversions; only this computes them.
-- -----------------------------------------------------------------------------

-- The rate the caller has cached for from -> to, or its inverse, or 1 when the
-- two are the same currency. NULL when nothing is cached, which callers must
-- treat as "cannot convert" rather than as zero.
create or replace function public.owner_rate_e9(p_owner uuid, p_from text, p_to text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_from is null or p_to is null then null
    when upper(p_from) = upper(p_to) then 1000000000::bigint
    else coalesce(
      (select r.rate_e9
         from public.exchange_rates r
        where r.owner_id = p_owner and r.base = upper(p_from) and r.quote = upper(p_to)),
      (select round(1000000000000000000::numeric / r.rate_e9)::bigint
         from public.exchange_rates r
        where r.owner_id = p_owner and r.base = upper(p_to) and r.quote = upper(p_from))
    )
  end;
$$;

-- An amount in p_from, at p_rate_e9 (units of p_to per one p_from), as minor
-- units of p_to. Decimal exponents differ between currencies — the yen has
-- none, the Gulf dinars have three — so the scale factor is part of the
-- arithmetic rather than an afterthought.
create or replace function public.convert_amount_minor(
  p_amount_minor bigint,
  p_from         text,
  p_to           text,
  p_rate_e9      bigint
)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_amount_minor is null or p_from is null or p_to is null then null
    when upper(p_from) = upper(p_to) then p_amount_minor
    when p_rate_e9 is null or p_rate_e9 <= 0 then null
    else round(
      p_amount_minor::numeric
        * power(10::numeric, public.currency_decimals(p_to) - public.currency_decimals(p_from))
        * p_rate_e9::numeric / 1000000000::numeric
    )::bigint
  end;
$$;

-- The same conversion, using whatever rate the owner has cached.
create or replace function public.convert_for_owner(
  p_owner        uuid,
  p_amount_minor bigint,
  p_from         text,
  p_to           text
)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select public.convert_amount_minor(
    p_amount_minor, p_from, p_to, public.owner_rate_e9(p_owner, p_from, p_to)
  );
$$;

revoke all on function public.owner_rate_e9(uuid, text, text)                  from public;
revoke all on function public.convert_amount_minor(bigint, text, text, bigint) from public;
revoke all on function public.convert_for_owner(uuid, bigint, text, text)      from public;
grant execute on function public.owner_rate_e9(uuid, text, text)                  to authenticated, service_role;
grant execute on function public.convert_amount_minor(bigint, text, text, bigint) to authenticated, service_role;
grant execute on function public.convert_for_owner(uuid, bigint, text, text)      to authenticated, service_role;

-- Store a batch of rates fetched by a client (upgrade §6).
--
-- p_rates is {"INR": 24.0113, "USD": 0.2723}, read as: one p_base costs this
-- much of each quote. Unknown codes are skipped rather than rejected, because
-- the free APIs return more currencies than this product supports and a client
-- should not have to filter the payload to be allowed to cache any of it.
create or replace function public.upsert_exchange_rates(
  p_base   text,
  p_rates  jsonb,
  p_as_of  date default current_date,
  p_source text default 'unknown'
)
returns int
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_base  text := upper(btrim(coalesce(p_base, '')));
  v_count int  := 0;
  v_key   text;
  v_value numeric;
  v_rate  bigint;
begin
  if not public.is_supported_currency(v_base) then
    raise exception 'Unsupported currency %.', v_base using errcode = 'check_violation';
  end if;
  if p_rates is null or jsonb_typeof(p_rates) <> 'object' then
    raise exception 'Rates must be an object of currency code to rate.'
      using errcode = 'check_violation';
  end if;
  if coalesce(p_as_of, current_date) > current_date + 1 then
    raise exception 'A rate cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  for v_key in select jsonb_object_keys(p_rates) loop
    continue when upper(v_key) = v_base;
    continue when not public.is_supported_currency(v_key);

    begin
      v_value := (p_rates ->> v_key)::numeric;
    exception when others then
      v_value := null;
    end;
    continue when v_value is null or v_value <= 0;

    v_rate := round(v_value * 1000000000::numeric)::bigint;
    continue when v_rate <= 0;

    insert into public.exchange_rates (owner_id, base, quote, rate_e9, as_of, source, fetched_at)
    values (
      v_owner, v_base, upper(v_key), v_rate, coalesce(p_as_of, current_date),
      left(coalesce(nullif(btrim(p_source), ''), 'unknown'), 60), now()
    )
    on conflict (owner_id, base, quote) do update
      set rate_e9    = excluded.rate_e9,
          as_of      = excluded.as_of,
          source     = excluded.source,
          fetched_at = excluded.fetched_at
      -- Never let a stale payload overwrite a fresher one: a phone that has
      -- been offline for a week must not push last week's rate over the one the
      -- desktop fetched this morning.
      where excluded.as_of >= public.exchange_rates.as_of;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.upsert_exchange_rates(text, jsonb, date, text) to authenticated;

-- =============================================================================
-- 6. The engine, extended (context.md §10; upgrade §9, §10)
--
-- The identities are untouched. What is added is the currency each figure is
-- denominated in, and — for aggregation only — its value in the owner's base
-- currency at today's cached rate.
--
-- `net_balance_base` is explicitly a *display* conversion and is allowed to
-- move when rates move. Nothing settles against it and no transaction is
-- derived from it. Per-transaction history is frozen at entry time and is never
-- recomputed (upgrade §8).
-- =============================================================================

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
  coalesce(p.currency, public.owner_base_currency(p.owner_id))       as currency,
  public.owner_base_currency(p.owner_id)                             as base_currency,
  coalesce(t.total_credit, 0)::bigint                                as total_credit,
  coalesce(t.total_debit, 0)::bigint                                 as total_debit,
  coalesce(s.settled_in, 0)::bigint                                  as settled_in,
  coalesce(s.settled_out, 0)::bigint                                 as settled_out,
  (coalesce(s.settled_in, 0) + coalesce(s.settled_out, 0))::bigint   as total_settled,
  (coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))::bigint  as outstanding_receivable,
  (coalesce(t.total_debit, 0)  - coalesce(s.settled_out, 0))::bigint as outstanding_payable,
  ((coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))
    - (coalesce(t.total_debit, 0) - coalesce(s.settled_out, 0)))::bigint as net_balance,
  -- The same net position expressed in the owner's base currency, or NULL when
  -- no rate has ever been cached for that pair. NULL means "not known", and
  -- every consumer treats it as such rather than as zero.
  public.convert_for_owner(
    p.owner_id,
    ((coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))
      - (coalesce(t.total_debit, 0) - coalesce(s.settled_out, 0)))::bigint,
    coalesce(p.currency, public.owner_base_currency(p.owner_id)),
    public.owner_base_currency(p.owner_id)
  )                                                                  as net_balance_base,
  coalesce(t.txn_count, 0)::bigint                                   as transaction_count,
  coalesce(o.opening_minor, 0)::bigint                               as opening_minor,
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
) s on true
-- The opening balance as a signed figure: positive when they owe the user.
left join lateral (
  select sum(case when op.type = 'credit' then op.amount_minor else -op.amount_minor end) as opening_minor
  from public.transactions op
  where op.person_id = p.id and op.is_opening and not op.is_void
) o on true;

comment on view public.person_balances is
  'Authoritative per-person accounting position, in that person''s account currency. '
  'net_balance_base is a display conversion at today''s cached rate and may be NULL.';

-- -----------------------------------------------------------------------------
-- Whole-workspace totals, in the base currency (upgrade §9).
--
-- People whose currency has no cached rate are excluded from the totals and
-- counted in `unconverted_people`, so the dashboard can say so rather than
-- quietly under-reporting. For a single-currency workspace — every person on
-- the base currency, which is every workspace that existed before this
-- migration — the rate is 1 by definition and these numbers are identical to
-- the ones 0003 produced.
-- -----------------------------------------------------------------------------

create or replace view public.owner_summary
with (security_invoker = true) as
select
  pb.owner_id,
  max(pb.base_currency)                                                            as base_currency,
  coalesce(sum(pb.net_balance_base) filter (where pb.net_balance_base > 0), 0)::bigint  as total_receivable,
  coalesce(-sum(pb.net_balance_base) filter (where pb.net_balance_base < 0), 0)::bigint as total_payable,
  coalesce(sum(pb.net_balance_base), 0)::bigint                                    as net_position,
  count(*) filter (where coalesce(pb.net_balance_base, pb.net_balance) <> 0)::bigint as people_with_balance,
  count(*)::bigint                                                                 as people_count,
  count(*) filter (where pb.net_balance <> 0 and pb.net_balance_base is null)::bigint as unconverted_people,
  count(distinct pb.currency)::bigint                                              as currency_count,
  coalesce(sum(public.convert_for_owner(pb.owner_id, pb.total_credit,  pb.currency, pb.base_currency)), 0)::bigint as gross_credit,
  coalesce(sum(public.convert_for_owner(pb.owner_id, pb.total_debit,   pb.currency, pb.base_currency)), 0)::bigint as gross_debit,
  coalesce(sum(public.convert_for_owner(pb.owner_id, pb.total_settled, pb.currency, pb.base_currency)), 0)::bigint as gross_settled
from public.person_balances pb
where not pb.is_archived
group by pb.owner_id;

comment on view public.owner_summary is
  'Dashboard headline numbers for the calling user, converted to the base currency. '
  'Archived people are excluded; people with no usable rate are counted in unconverted_people.';

-- -----------------------------------------------------------------------------
-- Activity feed, now carrying the conversion provenance and the opening flag.
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
  t.is_opening,
  t.entered_amount_minor,
  t.entered_currency,
  t.exchange_rate_e9,
  t.exchange_rate_at,
  t.exchange_rate_source,
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
  false,
  s.entered_amount_minor,
  s.entered_currency,
  s.exchange_rate_e9,
  s.exchange_rate_at,
  s.exchange_rate_source,
  s.transaction_id,
  s.created_at
from public.settlements s;

comment on view public.activity_feed is
  'Chronological union of transactions and settlements. Order by entry_date desc, created_at desc.';

grant select on public.person_balances, public.owner_summary, public.activity_feed to authenticated;
revoke all on public.person_balances from anon;
revoke all on public.owner_summary   from anon;
revoke all on public.activity_feed   from anon;
