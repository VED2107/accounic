-- =============================================================================
-- 0020 — money moves between two people as ONE transaction
--
-- THE FEATURE
--
--     Ved  ₹10,000        transfer ₹3,000        Ved   ₹7,000
--     Dhruv ₹2,000        Ved → Dhruv            Dhruv ₹5,000
--
-- and the workspace total does not move, because nothing entered or left it.
--
-- THE MODEL
--
-- A transfer is one logical record (`public.transfers`) realised as exactly two
-- linked ledger entries — ordinary rows in `public.transactions`, carrying
-- `transfer_id` and `transfer_role`:
--
--     source      type 'debit'   on the FROM person   net decreases
--     destination type 'credit'  on the TO   person   net increases
--
-- Ordinary rows on purpose. `person_balances`, `owner_summary`, the FIFO
-- settlement allocator, the activity feed, the per-currency dashboard totals
-- and every index already know what a transaction is, and a transfer that is
-- made of them is correct in all of those by construction rather than by a
-- second implementation that has to be kept in step. This is the same device
-- 0010 used for the opening balance, and for the same reason.
--
-- What makes the pair one thing rather than two coincidences:
--
--   * both legs carry the same `transfer_id`,
--   * `(transfer_id, transfer_role)` is unique, so there is exactly one source
--     and one destination and a third leg cannot exist,
--   * a DEFERRED constraint trigger (§4) checks, at every commit, that the two
--     legs still agree with their transfer row about person, direction, amount
--     and void state. One side can never survive without the other, whatever
--     writes to the table — RPC, PostgREST, or psql.
--
-- RECONCILIATION
--
--   * same currency both sides: `from_amount_minor = to_amount_minor` is a
--     CHECK constraint, so source impact + destination impact = 0 exactly, in
--     every currency, always.
--   * different currencies: `to_amount_minor` is what the STORED rate says
--     `from_amount_minor` is worth, which `transfer_integrity` (§8) verifies.
--     The two sides therefore cancel exactly at the transfer's own rate. The
--     dashboard's base-currency figure converts each person's position at
--     today's cached rate, as it has since 0010, so a cross-currency transfer
--     can move that display total when the market moves. That is a property of
--     the display conversion and not of the transfer: nothing settles against
--     it, and no stored figure is ever recomputed.
--
-- BACKWARD COMPATIBILITY
--
-- Purely additive. One new table, two nullable columns on `transactions`, and
-- read payloads that gain keys. Every existing row has `transfer_id` NULL,
-- which reads as "not part of a transfer" — which is true. No amount, currency,
-- rate, date or id is touched anywhere in this file.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The transfer record
--
-- Three amounts, and all three are needed:
--
--   entry_amount_minor / entry_currency  what the user typed
--   from_amount_minor  / from_currency   what left the source, in the source's
--                                        ledger denomination
--   to_amount_minor    / to_currency     what arrived at the destination, in
--                                        the destination's denomination
--
-- For the ordinary case — one currency, both sides — all three are the same
-- number and the same code, and the CHECK constraints say so rather than
-- leaving it to trust.
-- -----------------------------------------------------------------------------

create table if not exists public.transfers (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null references public.profiles (id) on delete cascade,
  from_person_id uuid not null,
  to_person_id   uuid not null,
  transfer_date  date not null default current_date,
  note           text,

  entry_amount_minor bigint not null,
  entry_currency     text   not null,
  from_amount_minor  bigint not null,
  from_currency      text   not null,
  to_amount_minor    bigint not null,
  to_currency        text   not null,

  -- entry currency -> source ledger currency. NULL when they are the same.
  entry_rate_e9        bigint,
  -- source ledger currency -> destination ledger currency. NULL when the same.
  exchange_rate_e9     bigint,
  exchange_rate_at     timestamptz,
  exchange_rate_source text,
  conversion_mode      text,
  auto_converted_amount_minor bigint,

  -- Idempotency key, supplied by the client. Two submissions of one form carry
  -- one token and produce one transfer.
  client_token text,

  is_void     boolean not null default false,
  void_reason text,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint transfers_distinct_people check (from_person_id <> to_person_id),
  constraint transfers_amounts_positive check (
    entry_amount_minor > 0 and from_amount_minor > 0 and to_amount_minor > 0
  ),
  constraint transfers_amounts_sane check (
    entry_amount_minor <= 9223372036854
    and from_amount_minor <= 9223372036854
    and to_amount_minor   <= 9223372036854
  ),
  constraint transfers_currency_fmt check (
    entry_currency ~ '^[A-Z]{3}$' and from_currency ~ '^[A-Z]{3}$' and to_currency ~ '^[A-Z]{3}$'
  ),
  constraint transfers_note_len check (note is null or char_length(note) <= 500),
  constraint transfers_void_reason check (is_void or void_reason is null),
  constraint transfers_token_len check (
    client_token is null or char_length(client_token) between 8 and 100
  ),
  constraint transfers_source_len check (
    exchange_rate_source is null or char_length(exchange_rate_source) <= 60
  ),
  -- A conversion needs a rate, and a same-currency pair must not carry one.
  constraint transfers_entry_rate check (
    (entry_currency = from_currency and entry_rate_e9 is null)
    or (entry_currency <> from_currency and entry_rate_e9 is not null and entry_rate_e9 > 0)
  ),
  constraint transfers_exchange_rate check (
    (from_currency = to_currency and exchange_rate_e9 is null)
    or (from_currency <> to_currency and exchange_rate_e9 is not null and exchange_rate_e9 > 0)
  ),
  -- THE reconciliation invariant, as a constraint rather than a convention:
  -- one currency on both sides means the same integer on both sides.
  constraint transfers_same_currency_equal check (
    from_currency <> to_currency or from_amount_minor = to_amount_minor
  ),
  constraint transfers_mode_valid check (
    (conversion_mode is null or conversion_mode in ('automatic', 'manual'))
    and (conversion_mode is null or from_currency <> to_currency)
    and ((coalesce(conversion_mode, 'automatic') = 'manual')
         = (auto_converted_amount_minor is not null))
    and (auto_converted_amount_minor is null or auto_converted_amount_minor > 0)
  ),

  -- Both people must belong to the same owner as the transfer. A composite
  -- foreign key rather than a trigger, so it holds for every writer including
  -- the service role — the same rule 0002 applied to transactions.
  constraint transfers_from_same_owner
    foreign key (owner_id, from_person_id)
    references public.people (owner_id, id) on delete restrict,
  constraint transfers_to_same_owner
    foreign key (owner_id, to_person_id)
    references public.people (owner_id, id) on delete restrict,

  constraint transfers_owner_id_uniq unique (owner_id, id)
);

comment on table public.transfers is
  'One movement of money between two people in the same workspace, realised as two linked rows in public.transactions (0020).';
comment on column public.transfers.from_amount_minor is
  'What left the source, in the source person''s ledger currency. Equals the source leg''s amount_minor exactly.';
comment on column public.transfers.to_amount_minor is
  'What arrived at the destination, in the destination''s ledger currency. Equals the destination leg''s amount_minor exactly.';
comment on column public.transfers.client_token is
  'Idempotency key. A second submission carrying a token already seen returns the first transfer instead of creating a second.';

drop trigger if exists transfers_touch on public.transfers;
create trigger transfers_touch
  before update on public.transfers
  for each row execute function public.touch_updated_at();

-- One token, one transfer. This is what makes a double-submitted form safe.
create unique index if not exists transfers_owner_token_uniq
  on public.transfers (owner_id, client_token)
  where client_token is not null;

create index if not exists transfers_owner_date_idx
  on public.transfers (owner_id, transfer_date desc, created_at desc);
create index if not exists transfers_from_person_idx on public.transfers (from_person_id);
create index if not exists transfers_to_person_idx   on public.transfers (to_person_id);

-- -----------------------------------------------------------------------------
-- 2. The two legs
--
-- Nullable, defaulted to nothing, so every row already in the table means
-- exactly what it always meant.
-- -----------------------------------------------------------------------------

alter table public.transactions
  add column if not exists transfer_id   uuid,
  add column if not exists transfer_role text;

do $$ begin
  alter table public.transactions add constraint transactions_transfer_pair check (
    (transfer_id is null) = (transfer_role is null)
    and (transfer_role is null or transfer_role in ('source', 'destination'))
    -- An opening balance is what an account started with; a transfer is
    -- something that happened. A row cannot be both.
    and not (is_opening and transfer_id is not null)
  );
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.transactions add constraint transactions_transfer_same_owner
    foreign key (owner_id, transfer_id)
    references public.transfers (owner_id, id) on delete restrict;
exception when duplicate_object then null; end $$;

-- Exactly one source and one destination per transfer. A duplicate leg is
-- impossible rather than merely discouraged.
create unique index if not exists transactions_transfer_role_uniq
  on public.transactions (transfer_id, transfer_role)
  where transfer_id is not null;

create index if not exists transactions_transfer_idx
  on public.transactions (transfer_id)
  where transfer_id is not null;

comment on column public.transactions.transfer_id is
  'The transfer this row is one half of. NULL on an ordinary entry.';
comment on column public.transactions.transfer_role is
  'source (money left this person) | destination (money arrived). NULL on an ordinary entry.';

-- -----------------------------------------------------------------------------
-- 3. A leg cannot be re-pointed at another transfer
--
-- 0013's guard, with two more immutable keys. Changing `transfer_id` on a live
-- row would let one transfer's leg be donated to another, which no amount of
-- checking at the RPC layer could then detect.
-- -----------------------------------------------------------------------------

create or replace function public.guard_ledger_immutable_keys()
returns trigger
language plpgsql
as $$
begin
  if new.owner_id is distinct from old.owner_id then
    raise exception 'owner_id is immutable.' using errcode = 'insufficient_privilege';
  end if;
  if new.person_id is distinct from old.person_id then
    raise exception 'A financial record cannot be moved to another person. Void it and create a new one.'
      using errcode = 'check_violation';
  end if;
  if old.is_void and new.is_void then
    raise exception 'A voided record cannot be edited.' using errcode = 'check_violation';
  end if;
  if to_jsonb(new) ? 'transfer_id' then
    if (to_jsonb(new) -> 'transfer_id') is distinct from (to_jsonb(old) -> 'transfer_id')
       or (to_jsonb(new) -> 'transfer_role') is distinct from (to_jsonb(old) -> 'transfer_role') then
      raise exception 'A transfer leg cannot be moved to another transfer.'
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. The pair is checked at every commit
--
-- A DEFERRED constraint trigger, so the RPCs in §6 can write the transfer row
-- and its two legs in any order inside one statement sequence and be judged on
-- the final state. What it enforces cannot be worked around by writing to the
-- tables directly:
--
--   * a transfer has exactly two live legs, one of each role;
--   * the source leg is a debit on `from_person_id` for `from_amount_minor`;
--   * the destination leg is a credit on `to_person_id` for `to_amount_minor`;
--   * both legs' `is_void` equals the transfer's.
--
-- The last one is what makes "one side can never remain without the other"
-- true. Voiding one leg by hand fails the commit.
-- -----------------------------------------------------------------------------

create or replace function public.assert_transfer_intact()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id     uuid;
  v_tr     public.transfers%rowtype;
  v_src    public.transactions%rowtype;
  v_dst    public.transactions%rowtype;
  v_legs   int;
begin
  -- Written as four separate statements rather than two CASE expressions, and
  -- that is not a style choice. A CASE is one SQL expression, so PL/pgSQL
  -- resolves EVERY field reference in it — `new.transfer_id` included — even on
  -- the branch that is not taken, and the transfers table has no such column.
  -- The compact version raises `record "new" has no field "transfer_id"` on
  -- every transfer written, and because this trigger is deferred it does so at
  -- commit rather than at the insert that caused it.
  --
  -- NEW is likewise unassigned on DELETE and OLD on INSERT, so neither may be
  -- read outside the branch that owns it.
  if tg_table_name = 'transfers' then
    if tg_op = 'DELETE' then v_id := old.id; else v_id := new.id; end if;
  else
    if tg_op = 'DELETE' then v_id := old.transfer_id; else v_id := new.transfer_id; end if;
  end if;

  if v_id is null then
    return null;
  end if;

  select * into v_tr from public.transfers where id = v_id;
  if not found then
    -- The transfer is gone. Legs may not outlive it.
    select count(*) into v_legs from public.transactions where transfer_id = v_id;
    if v_legs > 0 then
      raise exception 'A transfer leg cannot exist without its transfer.'
        using errcode = 'check_violation';
    end if;
    return null;
  end if;

  select count(*) into v_legs from public.transactions where transfer_id = v_id;
  if v_legs <> 2 then
    raise exception 'A transfer must have exactly two legs; this one has %.', v_legs
      using errcode = 'check_violation',
            hint    = 'Use create_transfer(), update_transfer() or void_transfer(); a transfer is never edited one side at a time.';
  end if;

  select * into v_src from public.transactions
   where transfer_id = v_id and transfer_role = 'source';
  select * into v_dst from public.transactions
   where transfer_id = v_id and transfer_role = 'destination';

  if v_src.id is null or v_dst.id is null then
    raise exception 'A transfer needs one source leg and one destination leg.'
      using errcode = 'check_violation';
  end if;

  if v_src.owner_id <> v_tr.owner_id or v_dst.owner_id <> v_tr.owner_id then
    raise exception 'A transfer and its legs must belong to one workspace.'
      using errcode = 'insufficient_privilege';
  end if;

  if v_src.person_id <> v_tr.from_person_id or v_dst.person_id <> v_tr.to_person_id then
    raise exception 'A transfer leg is recorded against the wrong person.'
      using errcode = 'check_violation';
  end if;

  if v_src.type <> 'debit' or v_dst.type <> 'credit' then
    raise exception 'A transfer must debit the source and credit the destination.'
      using errcode = 'check_violation';
  end if;

  if v_src.amount_minor <> v_tr.from_amount_minor
     or v_dst.amount_minor <> v_tr.to_amount_minor then
    raise exception
      'A transfer''s legs must carry the transfer''s own amounts (% out, % in).',
      v_tr.from_amount_minor, v_tr.to_amount_minor
      using errcode = 'check_violation';
  end if;

  if v_src.is_void <> v_tr.is_void or v_dst.is_void <> v_tr.is_void then
    raise exception 'Both sides of a transfer are voided together or not at all.'
      using errcode = 'check_violation',
            hint    = 'Use void_transfer() so the money cannot vanish from one account and stay in the other.';
  end if;

  return null;
end;
$$;

drop trigger if exists transfers_intact on public.transfers;
create constraint trigger transfers_intact
  after insert or update on public.transfers
  deferrable initially deferred
  for each row execute function public.assert_transfer_intact();

drop trigger if exists transactions_transfer_intact on public.transactions;
create constraint trigger transactions_transfer_intact
  after insert or update or delete on public.transactions
  deferrable initially deferred
  for each row execute function public.assert_transfer_intact();

-- -----------------------------------------------------------------------------
-- 5. Row Level Security
--
-- The same shape as every other tenant table: owner-scoped, forced, and with no
-- delete policy at all — financial history is voided, never removed. A user
-- cannot read, create or change a transfer in another workspace, and the
-- composite foreign keys in §1 mean they cannot name a person in one either.
-- -----------------------------------------------------------------------------

alter table public.transfers enable row level security;
alter table public.transfers force row level security;

revoke all on public.transfers from anon, authenticated;
grant select, insert, update on public.transfers to authenticated;

drop policy if exists transfers_select_own on public.transfers;
create policy transfers_select_own on public.transfers
  for select to authenticated using (owner_id = public.current_owner());

drop policy if exists transfers_insert_own on public.transfers;
create policy transfers_insert_own on public.transfers
  for insert to authenticated with check (owner_id = public.current_owner());

drop policy if exists transfers_update_own on public.transfers;
create policy transfers_update_own on public.transfers
  for update to authenticated
  using (owner_id = public.current_owner())
  with check (owner_id = public.current_owner());

-- -----------------------------------------------------------------------------
-- 6. The feed carries the transfer
--
-- `activity_feed` gains three columns; `activity_entries` is rebuilt on top of
-- it because it selects `a.*` and would otherwise keep the old column list.
-- Nothing else about either view changes.
-- -----------------------------------------------------------------------------

-- `person_opening` (0019) reads `activity_entries`, which reads `activity_feed`.
-- Both are rebuilt below, unchanged apart from the three added columns.
drop view if exists public.person_opening;
drop view if exists public.activity_entries;

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
  t.conversion_mode,
  t.auto_converted_amount_minor,
  null::uuid                                            as related_transaction_id,
  t.created_at,
  t.transfer_id,
  t.transfer_role,
  case t.transfer_role
    when 'source'      then tf.to_person_id
    when 'destination' then tf.from_person_id
  end                                                   as transfer_counterparty_id
from public.transactions t
left join public.transfers tf on tf.id = t.transfer_id
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
  s.conversion_mode,
  s.auto_converted_amount_minor,
  s.transaction_id,
  s.created_at,
  null::uuid,
  null::text,
  null::uuid
from public.settlements s;

comment on view public.activity_feed is
  'Chronological union of transactions and settlements, carrying conversion provenance and — since 0020 — the transfer a row is one leg of. Order by entry_date desc, created_at desc.';

create or replace view public.activity_entries
with (security_invoker = true) as
select
  a.*,
  coalesce(pe.ledger_currency, pe.currency, public.owner_base_currency(a.owner_id))
                                                          as ledger_currency,
  coalesce(a.entered_amount_minor, a.amount_minor)         as entry_amount_minor,
  coalesce(
    a.entered_currency,
    pe.ledger_currency, pe.currency, public.owner_base_currency(a.owner_id)
  )                                                        as entry_currency,
  public.owner_base_currency(a.owner_id)                   as base_currency,
  public.convert_for_owner(
    a.owner_id,
    a.amount_minor,
    coalesce(pe.ledger_currency, pe.currency, public.owner_base_currency(a.owner_id)),
    public.owner_base_currency(a.owner_id)
  )                                                        as amount_base_minor
from public.activity_feed a
join public.people pe on pe.id = a.person_id;

comment on view public.activity_entries is
  'activity_feed plus the entry-currency resolution: entry_amount_minor/entry_currency are what was actually entered, amount_minor stays the ledger figure, and amount_base_minor is the base-currency equivalent (0017, extended 0020).';

grant select on public.activity_feed, public.activity_entries to authenticated;
revoke all on public.activity_feed    from anon;
revoke all on public.activity_entries from anon;

-- `person_opening` (0019) selected from activity_entries and was dropped with
-- it. Rebuilt here, unchanged.
create or replace view public.person_opening
with (security_invoker = true) as
select
  a.person_id,
  a.owner_id,
  a.id                                      as transaction_id,
  a.entry_type,
  case when a.entry_type = 'credit' then a.amount_minor else -a.amount_minor end
                                            as signed_minor,
  a.amount_minor,
  a.ledger_currency,
  a.entry_amount_minor,
  a.entry_currency,
  a.amount_base_minor,
  a.base_currency,
  a.entered_amount_minor,
  a.entered_currency,
  a.exchange_rate_e9,
  a.exchange_rate_at,
  a.exchange_rate_source,
  public.rate_is_manual(a.exchange_rate_source) as rate_is_manual,
  a.conversion_mode,
  a.auto_converted_amount_minor,
  a.entry_date,
  a.note,
  a.created_at
from public.activity_entries a
where a.entry_kind = 'transaction'
  and a.is_opening
  and not a.is_void;

grant select on public.person_opening to authenticated;
revoke all on public.person_opening from anon;

-- -----------------------------------------------------------------------------
-- 7. The write path
-- -----------------------------------------------------------------------------

-- The payload every transfer RPC returns: the transfer, and both balances, so a
-- client can reconcile two screens from one round trip.
create or replace function public.transfer_payload(p_transfer_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_build_object(
    'transfer', to_jsonb(t),
    'from_person', (select to_jsonb(p) from public.people p where p.id = t.from_person_id),
    'to_person',   (select to_jsonb(p) from public.people p where p.id = t.to_person_id),
    'from_balance', (select to_jsonb(b) from public.person_balances b
                      where b.person_id = t.from_person_id),
    'to_balance',   (select to_jsonb(b) from public.person_balances b
                      where b.person_id = t.to_person_id)
  )
  from public.transfers t
  where t.id = p_transfer_id;
$$;

revoke all on function public.transfer_payload(uuid) from public, anon;
grant execute on function public.transfer_payload(uuid) to authenticated;

/**
 * create_transfer — move money from one person to another.
 *
 * The amount is entered in `p_currency`, which defaults to the source person's
 * ledger currency, and reaches the destination in two documented steps:
 *
 *     entry  --p_entry_rate_e9-->  source ledger  --p_exchange_rate_e9-->  destination ledger
 *
 * Each step is skipped when its two currencies are the same, which is the
 * ordinary case and costs nothing. Every rate used is stored on the transfer
 * and frozen there: a later market move never rewrites it, and nothing on any
 * read path re-derives a stored amount from a current rate.
 *
 * `p_converted_amount_minor` + `p_conversion_mode = 'manual'` record what
 * actually arrived when that differs from what the rate said — the same
 * override 0014 added to every other money RPC, and it applies to the second
 * step only, because that is the one where a counter's spread lives.
 *
 * `p_client_token` makes the call idempotent: a token already seen returns the
 * transfer it created instead of creating a second one.
 */
create or replace function public.create_transfer(
  p_from_person_id uuid,
  p_to_person_id   uuid,
  p_amount_minor   bigint,
  p_currency       text        default null,
  p_date           date        default current_date,
  p_note           text        default null,
  p_entry_rate_e9  bigint      default null,
  p_exchange_rate_e9 bigint    default null,
  p_rate_at        timestamptz default null,
  p_rate_source    text        default null,
  p_converted_amount_minor bigint default null,
  p_conversion_mode text       default null,
  p_client_token   text        default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner   uuid := public.assert_caller();
  v_from    public.people;
  v_to      public.people;
  v_from_cy text;
  v_to_cy   text;
  v_entry   text;
  v_token   text := nullif(btrim(coalesce(p_client_token, '')), '');
  v_note    text := nullif(btrim(coalesce(p_note, '')), '');
  v_src_minor bigint;
  v_conv    record;
  v_id      uuid;
  v_existing uuid;
begin
  if p_from_person_id is null or p_to_person_id is null then
    raise exception 'Choose who the money is coming from and who it is going to.'
      using errcode = 'check_violation';
  end if;

  if p_from_person_id = p_to_person_id then
    raise exception 'A transfer needs two different people.'
      using errcode = 'check_violation',
            hint    = 'Money cannot be transferred to the same account it came from.';
  end if;

  -- Both people, read through RLS. A person in another workspace is simply not
  -- found here, and the composite foreign keys refuse the write besides.
  select * into v_from from public.people p
   where p.id = p_from_person_id and p.owner_id = v_owner;
  if not found then
    raise exception 'The person the money is coming from could not be found.'
      using errcode = 'no_data_found';
  end if;

  select * into v_to from public.people p
   where p.id = p_to_person_id and p.owner_id = v_owner;
  if not found then
    raise exception 'The person the money is going to could not be found.'
      using errcode = 'no_data_found';
  end if;

  if coalesce(p_amount_minor, 0) <= 0 then
    raise exception 'Enter an amount greater than zero.' using errcode = 'check_violation';
  end if;

  if coalesce(p_date, current_date) > current_date + 1 then
    raise exception 'A transfer cannot be dated in the future.' using errcode = 'check_violation';
  end if;

  -- Idempotency. Checked before anything is written, and again by the unique
  -- index if two requests race: the loser's insert fails and it re-reads.
  if v_token is not null then
    select t.id into v_existing
    from public.transfers t
    where t.owner_id = v_owner and t.client_token = v_token;
    if v_existing is not null then
      return public.transfer_payload(v_existing);
    end if;
  end if;

  v_from_cy := public.person_ledger_currency(p_from_person_id);
  v_to_cy   := public.person_ledger_currency(p_to_person_id);
  v_entry   := upper(coalesce(nullif(btrim(coalesce(p_currency, '')), ''), v_from_cy));

  if not public.is_supported_currency(v_entry) then
    raise exception 'Unsupported currency %.', v_entry using errcode = 'check_violation';
  end if;

  -- Step one: what actually leaves the source account.
  v_src_minor := public.resolve_amount_minor(
    v_from_cy,
    case when v_entry = v_from_cy then p_amount_minor end,
    case when v_entry <> v_from_cy then p_amount_minor end,
    nullif(v_entry, v_from_cy),
    p_entry_rate_e9
  );

  -- Step two: what arrives, and whether the rate or the user decided it.
  v_conv := public.resolve_conversion(
    v_to_cy,
    case when v_from_cy = v_to_cy then v_src_minor end,
    case when v_from_cy <> v_to_cy then v_src_minor end,
    nullif(v_from_cy, v_to_cy),
    p_exchange_rate_e9,
    p_converted_amount_minor,
    p_conversion_mode
  );

  insert into public.transfers (
    owner_id, from_person_id, to_person_id, transfer_date, note,
    entry_amount_minor, entry_currency,
    from_amount_minor, from_currency,
    to_amount_minor, to_currency,
    entry_rate_e9, exchange_rate_e9, exchange_rate_at, exchange_rate_source,
    conversion_mode, auto_converted_amount_minor,
    client_token, created_by
  )
  values (
    v_owner, p_from_person_id, p_to_person_id, coalesce(p_date, current_date), v_note,
    p_amount_minor, v_entry,
    v_src_minor, v_from_cy,
    v_conv.o_amount_minor, v_to_cy,
    case when v_entry <> v_from_cy then p_entry_rate_e9 end,
    case when v_from_cy <> v_to_cy then p_exchange_rate_e9 end,
    case when v_from_cy <> v_to_cy then coalesce(p_rate_at, now()) end,
    case when v_from_cy <> v_to_cy then left(coalesce(p_rate_source, 'manual'), 60) end,
    v_conv.o_mode, v_conv.o_auto_minor,
    v_token, auth.uid()
  )
  returning id into v_id;

  -- The source leg: a debit, so the person's net position falls by exactly what
  -- left them. Its conversion provenance is the entry step, because that is the
  -- conversion this row underwent.
  insert into public.transactions (
    owner_id, person_id, type, amount_minor, transaction_date, description,
    entered_amount_minor, entered_currency, exchange_rate_e9, exchange_rate_at,
    exchange_rate_source, transfer_id, transfer_role, created_by
  )
  values (
    v_owner, p_from_person_id, 'debit', v_src_minor, coalesce(p_date, current_date), v_note,
    case when v_entry <> v_from_cy then p_amount_minor end,
    case when v_entry <> v_from_cy then v_entry end,
    case when v_entry <> v_from_cy then p_entry_rate_e9 end,
    case when v_entry <> v_from_cy then coalesce(p_rate_at, now()) end,
    case when v_entry <> v_from_cy then left(coalesce(p_rate_source, 'manual'), 60) end,
    v_id, 'source', auth.uid()
  );

  -- The destination leg: a credit for what arrived. What was "entered" against
  -- this account is the figure that left the source, so the row can say
  -- "$100 USD → ₹9,542.76 INR" without any client working it out.
  insert into public.transactions (
    owner_id, person_id, type, amount_minor, transaction_date, description,
    entered_amount_minor, entered_currency, exchange_rate_e9, exchange_rate_at,
    exchange_rate_source, conversion_mode, auto_converted_amount_minor,
    transfer_id, transfer_role, created_by
  )
  values (
    v_owner, p_to_person_id, 'credit', v_conv.o_amount_minor,
    coalesce(p_date, current_date), v_note,
    case when v_from_cy <> v_to_cy then v_src_minor end,
    case when v_from_cy <> v_to_cy then v_from_cy end,
    case when v_from_cy <> v_to_cy then p_exchange_rate_e9 end,
    case when v_from_cy <> v_to_cy then coalesce(p_rate_at, now()) end,
    case when v_from_cy <> v_to_cy then left(coalesce(p_rate_source, 'manual'), 60) end,
    v_conv.o_mode, v_conv.o_auto_minor,
    v_id, 'destination', auth.uid()
  );

  return public.transfer_payload(v_id);
end;
$$;

revoke all on function public.create_transfer(
  uuid, uuid, bigint, text, date, text, bigint, bigint, timestamptz, text, bigint, text, text
) from public, anon;
grant execute on function public.create_transfer(
  uuid, uuid, bigint, text, date, text, bigint, bigint, timestamptz, text, bigint, text, text
) to authenticated;

/**
 * void_transfer — retract both sides at once.
 *
 * A void, not a delete: every row keeps its amount, date and rate, the two
 * accounts return to where they were, and the entries stay on both timelines
 * marked as retracted. Both legs are voided in one statement sequence, and the
 * deferred trigger in §4 refuses the commit if either survives the other.
 */
create or replace function public.void_transfer(
  p_transfer_id uuid,
  p_reason      text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner  uuid := public.assert_caller();
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_id     uuid;
begin
  update public.transfers set is_void = true, void_reason = v_reason
   where id = p_transfer_id and owner_id = v_owner and not is_void
  returning id into v_id;

  if v_id is null then
    raise exception 'Transfer not found, or it is already retracted.'
      using errcode = 'no_data_found';
  end if;

  update public.transactions set is_void = true, void_reason = v_reason
   where transfer_id = v_id and owner_id = v_owner and not is_void;

  return public.transfer_payload(v_id);
end;
$$;

revoke all on function public.void_transfer(uuid, text) from public, anon;
grant execute on function public.void_transfer(uuid, text) to authenticated;

/**
 * update_transfer — edit the logical transfer, never one side of it.
 *
 * The people are not editable: moving a transfer to a different account is a
 * different transfer, and the honest way to record that is to retract this one
 * and make that one. What can change is the date, the note, the amount, the
 * currency it was entered in and the rates — and every one of those is applied
 * to the transfer row and both legs together, so the two sides cannot drift.
 */
create or replace function public.update_transfer(
  p_transfer_id    uuid,
  p_amount_minor   bigint      default null,
  p_currency       text        default null,
  p_date           date        default null,
  p_note           text        default null,
  p_entry_rate_e9  bigint      default null,
  p_exchange_rate_e9 bigint    default null,
  p_rate_at        timestamptz default null,
  p_rate_source    text        default null,
  p_converted_amount_minor bigint default null,
  p_conversion_mode text       default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner   uuid := public.assert_caller();
  v_tr      public.transfers;
  v_from_cy text;
  v_to_cy   text;
  v_entry   text;
  v_amount  bigint;
  v_date    date;
  v_note    text;
  v_entry_rate bigint;
  v_rate    bigint;
  v_src_minor bigint;
  v_conv    record;
begin
  select * into v_tr from public.transfers t
   where t.id = p_transfer_id and t.owner_id = v_owner and not t.is_void;
  if not found then
    raise exception 'Transfer not found, or it has been retracted.'
      using errcode = 'no_data_found';
  end if;

  v_from_cy := v_tr.from_currency;
  v_to_cy   := v_tr.to_currency;
  v_entry   := upper(coalesce(nullif(btrim(coalesce(p_currency, '')), ''), v_tr.entry_currency));
  v_amount  := coalesce(p_amount_minor, v_tr.entry_amount_minor);
  v_date    := coalesce(p_date, v_tr.transfer_date);
  v_note    := nullif(btrim(coalesce(p_note, '')), '');

  if coalesce(v_amount, 0) <= 0 then
    raise exception 'Enter an amount greater than zero.' using errcode = 'check_violation';
  end if;
  if v_date > current_date + 1 then
    raise exception 'A transfer cannot be dated in the future.' using errcode = 'check_violation';
  end if;
  if not public.is_supported_currency(v_entry) then
    raise exception 'Unsupported currency %.', v_entry using errcode = 'check_violation';
  end if;

  -- An edit that says nothing about a rate keeps the one the transfer was
  -- written at. A hand-typed rate therefore survives a change of note, which is
  -- the whole of "never rewrite a historical transfer rate".
  v_entry_rate := coalesce(p_entry_rate_e9,
                           case when v_entry = v_tr.entry_currency then v_tr.entry_rate_e9 end);
  v_rate       := coalesce(p_exchange_rate_e9, v_tr.exchange_rate_e9);

  v_src_minor := public.resolve_amount_minor(
    v_from_cy,
    case when v_entry = v_from_cy then v_amount end,
    case when v_entry <> v_from_cy then v_amount end,
    nullif(v_entry, v_from_cy),
    v_entry_rate
  );

  v_conv := public.resolve_conversion(
    v_to_cy,
    case when v_from_cy = v_to_cy then v_src_minor end,
    case when v_from_cy <> v_to_cy then v_src_minor end,
    nullif(v_from_cy, v_to_cy),
    v_rate,
    p_converted_amount_minor,
    coalesce(p_conversion_mode,
             case when p_converted_amount_minor is null then v_tr.conversion_mode end)
  );

  update public.transfers set
    transfer_date        = v_date,
    note                 = v_note,
    entry_amount_minor   = v_amount,
    entry_currency       = v_entry,
    from_amount_minor    = v_src_minor,
    to_amount_minor      = v_conv.o_amount_minor,
    entry_rate_e9        = case when v_entry <> v_from_cy then v_entry_rate end,
    exchange_rate_e9     = case when v_from_cy <> v_to_cy then v_rate end,
    exchange_rate_at     = case when v_from_cy <> v_to_cy
                                then coalesce(p_rate_at, v_tr.exchange_rate_at, now()) end,
    exchange_rate_source = case when v_from_cy <> v_to_cy
                                then left(coalesce(p_rate_source, v_tr.exchange_rate_source, 'manual'), 60) end,
    conversion_mode             = v_conv.o_mode,
    auto_converted_amount_minor = v_conv.o_auto_minor
  where id = p_transfer_id and owner_id = v_owner;

  update public.transactions set
    amount_minor         = v_src_minor,
    transaction_date     = v_date,
    description          = v_note,
    entered_amount_minor = case when v_entry <> v_from_cy then v_amount end,
    entered_currency     = case when v_entry <> v_from_cy then v_entry end,
    exchange_rate_e9     = case when v_entry <> v_from_cy then v_entry_rate end,
    exchange_rate_at     = case when v_entry <> v_from_cy
                                then coalesce(p_rate_at, exchange_rate_at, now()) end,
    exchange_rate_source = case when v_entry <> v_from_cy
                                then left(coalesce(p_rate_source, exchange_rate_source, 'manual'), 60) end
  where transfer_id = p_transfer_id and transfer_role = 'source' and owner_id = v_owner;

  update public.transactions set
    amount_minor         = v_conv.o_amount_minor,
    transaction_date     = v_date,
    description          = v_note,
    entered_amount_minor = case when v_from_cy <> v_to_cy then v_src_minor end,
    entered_currency     = case when v_from_cy <> v_to_cy then v_from_cy end,
    exchange_rate_e9     = case when v_from_cy <> v_to_cy then v_rate end,
    exchange_rate_at     = case when v_from_cy <> v_to_cy
                                then coalesce(p_rate_at, exchange_rate_at, now()) end,
    exchange_rate_source = case when v_from_cy <> v_to_cy
                                then left(coalesce(p_rate_source, exchange_rate_source, 'manual'), 60) end,
    conversion_mode             = v_conv.o_mode,
    auto_converted_amount_minor = v_conv.o_auto_minor
  where transfer_id = p_transfer_id and transfer_role = 'destination' and owner_id = v_owner;

  return public.transfer_payload(p_transfer_id);
end;
$$;

revoke all on function public.update_transfer(
  uuid, bigint, text, date, text, bigint, bigint, timestamptz, text, bigint, text
) from public, anon;
grant execute on function public.update_transfer(
  uuid, bigint, text, date, text, bigint, bigint, timestamptz, text, bigint, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. A transfer leg is never edited on its own
--
-- The trigger in §4 already makes a half-edit impossible at commit. These two
-- turn the resulting constraint violation into a sentence a user can act on,
-- and they are the only route any client actually takes.
-- -----------------------------------------------------------------------------

create or replace function public.assert_not_transfer_leg(p_transaction_id uuid)
returns void
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_transfer uuid;
begin
  select t.transfer_id into v_transfer
  from public.transactions t where t.id = p_transaction_id;

  if v_transfer is not null then
    raise exception 'This entry is one half of a transfer and cannot be changed on its own.'
      using errcode = 'check_violation',
            hint    = 'Edit or retract the transfer, and both sides move together.';
  end if;
end;
$$;

revoke all on function public.assert_not_transfer_leg(uuid) from public, anon;
grant execute on function public.assert_not_transfer_leg(uuid) to authenticated;

create or replace function public.void_transaction(p_transaction_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_row   public.transactions;
begin
  perform public.assert_not_transfer_leg(p_transaction_id);

  update public.transactions set
    is_void     = true,
    void_reason = nullif(btrim(coalesce(p_reason, '')), '')
  where id = p_transaction_id and owner_id = v_owner and not is_void
  returning * into v_row;

  if not found then
    raise exception 'Transaction not found, or it is already voided.'
      using errcode = 'no_data_found';
  end if;

  return jsonb_build_object(
    'transaction', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = v_row.person_id)
  );
end;
$$;

grant execute on function public.void_transaction(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 9. Retracting a person's whole history retracts their transfers whole
--
-- 0014's function voided every transaction on one account. With transfers that
-- would leave the counterparty holding half a transfer, which §4 refuses — so
-- the correct behaviour, and the only one that commits, is to retract the whole
-- transfer including the leg that sits in the other person's account.
-- -----------------------------------------------------------------------------

create or replace function public.void_person_history(
  p_person_id uuid,
  p_reason    text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner        uuid := public.assert_caller();
  v_reason       text := nullif(btrim(coalesce(p_reason, '')), '');
  v_person       public.people;
  v_settlements  int;
  v_transactions int;
  v_transfers    int;
begin
  select * into v_person
  from public.people
  where id = p_person_id and owner_id = v_owner;

  if not found then
    raise exception 'That person could not be found.'
      using errcode = 'no_data_found';
  end if;

  -- Transfers first, both sides, so no leg is left orphaned by the sweep below.
  with voided as (
    update public.transfers set is_void = true, void_reason = v_reason
    where owner_id = v_owner
      and not is_void
      and (from_person_id = p_person_id or to_person_id = p_person_id)
    returning id
  )
  select count(*) into v_transfers from voided;

  update public.transactions t set is_void = true, void_reason = v_reason
  from public.transfers tf
  where t.transfer_id = tf.id
    and t.owner_id = v_owner
    and tf.is_void
    and not t.is_void;

  with voided as (
    update public.settlements set
      is_void     = true,
      void_reason = v_reason
    where person_id = p_person_id
      and owner_id  = v_owner
      and not is_void
    returning 1
  )
  select count(*) into v_settlements from voided;

  with voided as (
    update public.transactions set
      is_void     = true,
      void_reason = v_reason
    where person_id = p_person_id
      and owner_id  = v_owner
      and not is_void
    returning 1
  )
  select count(*) into v_transactions from voided;

  return jsonb_build_object(
    'person_id', p_person_id,
    'transactions_voided', v_transactions,
    'settlements_voided', v_settlements,
    'transfers_voided', v_transfers,
    'balance', (
      select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id
    )
  );
end;
$$;

grant execute on function public.void_person_history(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 10. Reconciliation, as something the database can be asked
--
-- `transfer_integrity` lists every live transfer whose two sides do not cancel.
-- It should always be empty; a row in it is a bug, not a warning. Written as a
-- view rather than a test so it can be checked against production data at any
-- time, by the test suite and by a human.
-- -----------------------------------------------------------------------------

create or replace view public.transfer_integrity
with (security_invoker = true) as
select
  t.id            as transfer_id,
  t.owner_id,
  t.from_person_id,
  t.to_person_id,
  t.from_amount_minor,
  t.from_currency,
  t.to_amount_minor,
  t.to_currency,
  -- What the stored rate says the destination should have received.
  case
    when t.from_currency = t.to_currency then t.from_amount_minor
    else public.convert_amount_minor(
           t.from_amount_minor, t.from_currency, t.to_currency, t.exchange_rate_e9)
  end             as expected_to_minor,
  coalesce(t.conversion_mode, 'automatic') as conversion_mode,
  (select count(*) from public.transactions x
    where x.transfer_id = t.id)            as leg_count,
  (select coalesce(sum(case when x.type = 'credit' then x.amount_minor
                            else -x.amount_minor end), 0)
     from public.transactions x where x.transfer_id = t.id and not x.is_void)
                                           as signed_leg_sum
from public.transfers t
where not t.is_void
  and (
    -- Two live legs, always.
    (select count(*) from public.transactions x
      where x.transfer_id = t.id and not x.is_void) <> 2
    -- Same currency: the two sides are the same integer.
    or (t.from_currency = t.to_currency and t.from_amount_minor <> t.to_amount_minor)
    -- Different currencies, automatic: the destination is exactly what the
    -- stored rate says. A manual transfer is exempt by definition — the user
    -- told the ledger what actually arrived.
    or (t.from_currency <> t.to_currency
        and coalesce(t.conversion_mode, 'automatic') = 'automatic'
        and t.to_amount_minor is distinct from public.convert_amount_minor(
              t.from_amount_minor, t.from_currency, t.to_currency, t.exchange_rate_e9))
  );

comment on view public.transfer_integrity is
  'Every live transfer whose two sides fail to reconcile. Always empty; a row here is a defect (0020).';

grant select on public.transfer_integrity to authenticated;
revoke all on public.transfer_integrity from anon;

-- -----------------------------------------------------------------------------
-- 11. The read paths carry the transfer
--
-- person_page(), dashboard() and activity_page() are 0019's and 0018's, with
-- `transfer_id`, `transfer_role` and the counterparty's name added to the row
-- lists. A client that does not read those keys sees no change at all.
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
    'currency', public.person_ledger_currency(p_person_id),
    'default_currency', public.person_currency(p_person_id),
    'base_currency', public.owner_base_currency(v_owner),

    'opening', (
      select to_jsonb(o) from public.person_opening o
      where o.person_id = p_person_id and o.owner_id = v_owner
    ),

    'opening_history', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from (
        select a.id, a.amount_minor, a.entry_type, a.entry_date, a.created_at,
               a.entry_amount_minor, a.entry_currency, a.ledger_currency,
               a.amount_base_minor, a.base_currency,
               a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor
        from public.activity_entries a
        where a.owner_id = v_owner and a.person_id = p_person_id
          and a.entry_kind = 'transaction' and a.is_opening and a.is_void
        order by a.created_at desc
        limit 20
      ) r
    ), '[]'::jsonb),

    'timeline', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.entry_kind, a.entry_type, a.money_direction, a.amount_minor,
               a.entry_date, a.note, a.is_void, a.related_transaction_id, a.created_at,
               a.is_opening, a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_at, a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor,
               a.entry_amount_minor, a.entry_currency,
               a.ledger_currency, a.amount_base_minor, a.base_currency,
               a.transfer_id, a.transfer_role, a.transfer_counterparty_id,
               cp.name as transfer_counterparty_name,
               st.settled_minor, st.remaining_minor, st.status
        from public.activity_entries a
        left join public.transaction_settlement_status(p_person_id) st
               on st.transaction_id = a.id and a.entry_kind = 'transaction'
        left join public.people cp on cp.id = a.transfer_counterparty_id
        where a.owner_id = v_owner and a.person_id = p_person_id
          and not a.is_opening
        order by a.entry_date desc, a.created_at desc
        limit p_limit offset p_offset
      ) r
    ), '[]'::jsonb),

    'timeline_total', (
      select count(*) from public.activity_feed a
      where a.owner_id = v_owner and a.person_id = p_person_id
        and not a.is_opening
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
$$;

grant execute on function public.person_page(uuid, int, int) to authenticated;

comment on function public.person_page(uuid, int, int) is
  'One person''s whole screen in sections: `opening` is what the account was carried in with, `timeline` is the regular activity — credits, debits, settlements and transfer legs, each carrying transfer_id/transfer_role and the counterparty''s name. `balance` includes every one of them (0020).';

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
$$;

revoke all on function public.activity_page(int, int, text, date, date) from public, anon;
grant execute on function public.activity_page(int, int, text, date, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 12. delete_person() must see a transfer as history
--
-- 0009 refuses to delete a person who has any transaction or settlement. A
-- transfer leg is a transaction, so that already holds; this adds the transfer
-- row itself to the same test so the message names the real reason.
-- -----------------------------------------------------------------------------

create or replace function public.delete_person(p_person_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner       uuid := public.assert_caller();
  v_txns        int;
  v_settlements int;
  v_transfers   int;
begin
  -- Live rows only. Voided ones are retractions, not history to protect.
  select count(*) into v_txns
  from public.transactions t
  where t.person_id = p_person_id
    and t.owner_id = v_owner
    and not t.is_void;

  if v_txns > 0 then
    raise exception 'This person has transactions and cannot be deleted. Archive them instead.'
      using errcode = 'check_violation';
  end if;

  select count(*) into v_settlements
  from public.settlements s
  where s.person_id = p_person_id
    and s.owner_id = v_owner
    and not s.is_void;

  if v_settlements > 0 then
    raise exception 'This person has settlements and cannot be deleted. Archive them instead.'
      using errcode = 'check_violation';
  end if;

  -- A live transfer is already a live transaction on this account, so the first
  -- test catches it. This names the real reason rather than the symptom.
  select count(*) into v_transfers
  from public.transfers tf
  where tf.owner_id = v_owner
    and not tf.is_void
    and (tf.from_person_id = p_person_id or tf.to_person_id = p_person_id);

  if v_transfers > 0 then
    raise exception 'This person has transfers and cannot be deleted. Archive them instead.'
      using errcode = 'check_violation';
  end if;

  -- Both foreign keys onto people are ON DELETE RESTRICT, so the retracted
  -- rows have to go first and in this order: settlements reference
  -- transactions, and transactions reference transfers.
  delete from public.settlements
  where person_id = p_person_id and owner_id = v_owner;

  -- BOTH legs of every retracted transfer this person was part of, including
  -- the one sitting in the counterparty's account: a leg may not outlive its
  -- transfer, and the transfer has to go with the person.
  delete from public.transactions t
  where t.owner_id = v_owner
    and t.transfer_id in (
      select tf.id from public.transfers tf
      where tf.owner_id = v_owner
        and (tf.from_person_id = p_person_id or tf.to_person_id = p_person_id)
    );

  delete from public.transactions
  where person_id = p_person_id and owner_id = v_owner;

  delete from public.transfers
  where owner_id = v_owner
    and (from_person_id = p_person_id or to_person_id = p_person_id);

  delete from public.people
  where id = p_person_id and owner_id = v_owner;

  if not found then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;
end;
$$;

revoke all on function public.delete_person(uuid) from public, anon;
grant execute on function public.delete_person(uuid) to authenticated, service_role;
