-- =============================================================================
-- 0013_person_currency.sql
-- Currency, genuinely per person: a default that can change, and a ledger
-- denomination that cannot.
--
-- 0010-0012 gave each person a currency, but conflated two things under one
-- column. `people.currency` was simultaneously
--
--   (a) the currency new entries for that person are entered in, and
--   (b) the currency `transactions.amount_minor` is denominated in.
--
-- While the two are the same that conflation is invisible. It becomes visible
-- the moment a person's currency changes: (a) wants to change, (b) must not,
-- because every historical row is already written in it. 0011 resolved that by
-- restating -- rewriting `amount_minor` on every row at a confirmed rate. This
-- migration resolves it the other way, which is what the product actually
-- wants: history is left exactly as it was recorded, and only future entries
-- follow the new currency.
--
-- So the two meanings are split:
--
--   people.currency         the person's DEFAULT ENTRY currency. Free to
--                           change at any time. NULL = the owner's base
--                           currency. Unchanged in meaning from 0010 for every
--                           person who has never switched.
--
--   people.ledger_currency  the currency `amount_minor` is denominated in for
--                           this person, frozen the first time the default
--                           moves away from it. NULL = "has never diverged",
--                           i.e. follow `currency`. Never rewritten once set.
--
-- ADDITIVE ONLY. One nullable column, NULL on every existing row, and NULL
-- reproduces 0010's behaviour exactly:
--
--     coalesce(ledger_currency, currency, base)  ==  coalesce(currency, base)
--
-- Not one ledger row is read, written, moved or deleted by this file. Every
-- balance that computed to a number before it runs computes to the same number
-- after it. `db/tools/snapshot.mjs` proves that rather than asserting it.
--
-- What a person who switches currency looks like afterwards:
--
--     Ahmed   default AED   ledger INR (frozen)
--       opening   Rs 1,000 INR                 <- untouched
--       new       AED 20 -> Rs 452.30 INR stored, AED 20 + rate kept on the row
--       balance   Rs 1,452.30 INR  (~ AED 64.20 for display)
--
-- The engine is untouched: `amount_minor` still means "minor units, in this
-- person's ledger currency", one currency per person, one integer per balance.
-- No view gained a row per currency, `settle_account()` and the
-- over-settlement guards are as they were, and nothing here needs a rate to
-- succeed.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The frozen denomination
-- -----------------------------------------------------------------------------

alter table public.people
  add column if not exists ledger_currency text;

do $$ begin
  alter table public.people
    add constraint people_ledger_currency_fmt
    check (ledger_currency is null or ledger_currency ~ '^[A-Z]{3}$');
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.people
    add constraint people_ledger_currency_known
    foreign key (ledger_currency) references public.currencies (code);
exception when duplicate_object then null; end $$;

comment on column public.people.currency is
  'Default entry currency for new transactions with this person. NULL = the owner''s base currency. Changing it never rewrites history.';
comment on column public.people.ledger_currency is
  'Currency this person''s amount_minor figures are denominated in. NULL = never diverged, follow currency. Frozen on the first currency change; never rewritten.';

-- The denomination of every stored figure for this person.
--
-- Deliberately NOT the same function as person_currency(): that one answers
-- "what should a new amount default to", this one answers "what is the number
-- already in the database in". Using the wrong one is exactly the bug this
-- migration exists to fix, so they are named for what they mean.
create or replace function public.person_ledger_currency(p_person_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p.ledger_currency, p.currency, public.owner_base_currency(p.owner_id))
  from public.people p
  where p.id = p_person_id;
$$;

comment on function public.person_ledger_currency(uuid) is
  'The currency this person''s amount_minor figures are denominated in. Use this to interpret a stored amount; use person_currency() to default a new entry.';

comment on function public.person_currency(uuid) is
  'The currency a new entry for this person should default to. Use person_ledger_currency() to interpret an amount already stored.';

revoke all on function public.person_ledger_currency(uuid) from public;
grant execute on function public.person_ledger_currency(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. Changing a person's currency no longer touches their history
--
-- The confirmation stays -- the user is entitled to know what will and will not
-- happen -- but it now promises the opposite of what 0011 promised, because the
-- behaviour is the opposite. The database still refuses the first attempt and
-- explains; nothing has been written when the user sees that message, and the
-- clients turn that refusal into the confirmation step.
--
-- `p_restate_rate_e9` is kept in the signature and ignored. A v1.1.0 client
-- still sends a rate, and it costs nothing to accept and discard it; dropping
-- the parameter would break that client's call outright.
--
-- The parameter is being renamed, and Postgres identifies a function by its
-- argument types -- which have not changed -- so `create or replace` would
-- refuse the rename. The old one is dropped first.
-- -----------------------------------------------------------------------------

drop function if exists public.update_person(
  uuid, text, public.party_type, text, text, text, text, text, boolean, bigint
);

create or replace function public.update_person(
  p_person_id uuid,
  p_name      text,
  p_type      public.party_type,
  p_phone     text default null,
  p_email     text default null,
  p_address   text default null,
  p_notes     text default null,
  p_currency  text default null,
  -- Changing the currency of an account that already holds entries changes what
  -- future entries are entered in, and nothing else.
  p_currency_change_confirmed boolean default false,
  p_restate_rate_e9           bigint  default null   -- accepted and ignored (v1.1.0 compatibility)
)
returns public.people
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner   uuid := public.assert_caller();
  v_row     public.people;
  v_current public.people;
  v_old_ccy text;
  v_ledger  text;
  v_new_ccy text := upper(nullif(btrim(coalesce(p_currency, '')), ''));
  v_entries int;
  v_freeze  text := null;
begin
  if btrim(coalesce(p_name, '')) = '' then
    raise exception 'Name is required.' using errcode = 'check_violation';
  end if;

  select * into v_current
  from public.people p
  where p.id = p_person_id and p.owner_id = v_owner;

  if not found then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  v_old_ccy := coalesce(v_current.currency, public.owner_base_currency(v_owner));
  v_ledger  := coalesce(v_current.ledger_currency, v_old_ccy);

  if v_new_ccy is not null and v_new_ccy <> v_old_ccy then
    if not public.is_supported_currency(v_new_ccy) then
      raise exception 'Unsupported currency %.', v_new_ccy using errcode = 'check_violation';
    end if;

    -- Voided rows count. They are still shown on the timeline and they are
    -- still written in the ledger currency, so the denomination has to be
    -- frozen on their account too.
    select count(*) into v_entries
    from public.transactions t
    where t.person_id = p_person_id and t.owner_id = v_owner;

    select v_entries + count(*) into v_entries
    from public.settlements s
    where s.person_id = p_person_id and s.owner_id = v_owner;

    if v_entries > 0 then
      if not coalesce(p_currency_change_confirmed, false) then
        raise exception
          'Changing this person''s currency affects future transactions only. Existing transactions will remain unchanged.'
          using errcode = 'check_violation',
                hint    = 'Confirm the change to continue.',
                detail  = v_old_ccy || '->' || v_new_ccy;
      end if;

      -- Freeze the denomination on the first divergence, and only then. Once
      -- set it is never touched again: a second currency change moves the
      -- default again, but the stored figures stay where they have always been.
      if v_current.ledger_currency is null then
        v_freeze := v_ledger;
      end if;
    end if;
    -- No entries: nothing is denominated in anything yet, so the ledger simply
    -- follows the new default and ledger_currency stays NULL.
  end if;

  update public.people set
    name            = btrim(p_name),
    type            = coalesce(p_type, type),
    phone           = nullif(btrim(coalesce(p_phone, '')), ''),
    email           = nullif(btrim(coalesce(p_email, '')), ''),
    address         = nullif(btrim(coalesce(p_address, '')), ''),
    notes           = nullif(btrim(coalesce(p_notes, '')), ''),
    currency        = coalesce(v_new_ccy, currency),
    ledger_currency = coalesce(v_freeze, ledger_currency)
  where id = p_person_id and owner_id = v_owner
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.update_person(
  uuid, text, public.party_type, text, text, text, text, text, boolean, bigint
) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Restatement is gone
--
-- Nothing calls restate_person_currency() any more, and leaving a granted RPC
-- that rewrites every amount on an account would leave the exact behaviour this
-- migration removes reachable from any client. It goes, and with it the
-- transaction-local escape hatch it needed in the immutability guard -- which
-- restores 0005's rule that a voided row cannot be edited, by anyone, ever.
-- -----------------------------------------------------------------------------

drop function if exists public.restate_person_currency(uuid, text, text, bigint);

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
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. The write path denominates in the LEDGER currency
--
-- This is the correction proper. Every one of these functions asked
-- person_currency() what to denominate a stored amount in; each now asks
-- person_ledger_currency(). For a person who has never switched the two return
-- the same string and the behaviour is byte-identical to 0011. For a person who
-- has switched, this is the difference between recording AED 20 as
-- "20 dirhams in an account whose history is rupees" -- which would silently
-- corrupt the balance -- and recording it as its rupee equivalent with the
-- dirhams kept on the row.
--
-- What the user typed is still preserved verbatim in entered_amount_minor /
-- entered_currency / exchange_rate_e9 / exchange_rate_at / exchange_rate_source,
-- and is still never overwritten by the converted figure.
-- -----------------------------------------------------------------------------

create or replace function public.set_person_opening_balance(
  p_person_id            uuid,
  p_direction            text,                     -- 'they_owe_me' | 'i_owe_them' | 'none'
  p_amount_minor         bigint      default null,
  p_date                 date        default null,
  p_entered_amount_minor bigint      default null,
  p_entered_currency     text        default null,
  p_rate_e9              bigint      default null,
  p_rate_at              timestamptz default null,
  p_rate_source          text        default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner    uuid := public.assert_caller();
  v_person   public.people;
  v_currency text;
  v_entered  text := upper(nullif(btrim(coalesce(p_entered_currency, '')), ''));
  v_type     public.txn_type;
  v_amount   bigint;
  v_existing uuid;
  v_row      public.transactions;
begin
  select * into v_person
  from public.people p
  where p.id = p_person_id and p.owner_id = v_owner;

  if not found then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  -- The denomination, not the default. An opening balance entered in the
  -- person's new default currency is converted into the ledger like any other
  -- entry (upgrade §5).
  v_currency := coalesce(v_person.ledger_currency, v_person.currency,
                         public.owner_base_currency(v_owner));

  -- Replacing an opening balance retracts the old one rather than editing it,
  -- so the correction is visible in the history instead of silently rewriting
  -- what the account was opened with.
  select t.id into v_existing
  from public.transactions t
  where t.person_id = p_person_id and t.owner_id = v_owner
    and t.is_opening and not t.is_void
  limit 1;

  if v_existing is not null then
    update public.transactions
      set is_void = true, void_reason = 'Opening balance replaced'
    where id = v_existing;
  end if;

  if coalesce(p_direction, 'none') = 'none'
     or coalesce(p_amount_minor, p_entered_amount_minor, 0) <= 0 then
    return jsonb_build_object(
      'transaction', null,
      'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
    );
  end if;

  v_type := case p_direction
              when 'they_owe_me' then 'credit'::public.txn_type
              when 'i_owe_them'  then 'debit'::public.txn_type
              else null
            end;

  if v_type is null then
    raise exception 'Say who owes whom before entering an opening balance.'
      using errcode = 'check_violation';
  end if;

  v_amount := public.resolve_amount_minor(
    v_currency, p_amount_minor, p_entered_amount_minor, v_entered, p_rate_e9
  );

  insert into public.transactions (
    owner_id, person_id, type, amount_minor, transaction_date, description,
    is_opening, entered_amount_minor, entered_currency,
    exchange_rate_e9, exchange_rate_at, exchange_rate_source, created_by
  )
  values (
    v_owner, p_person_id, v_type, v_amount,
    coalesce(p_date, v_person.created_at::date, current_date),
    'Opening balance',
    true,
    case when v_entered is null or v_entered = v_currency then null else p_entered_amount_minor end,
    case when v_entered is null or v_entered = v_currency then null else v_entered end,
    case when v_entered is null or v_entered = v_currency then null else p_rate_e9 end,
    case when v_entered is null or v_entered = v_currency then null else coalesce(p_rate_at, now()) end,
    case when v_entered is null or v_entered = v_currency then null else left(coalesce(p_rate_source, 'manual'), 60) end,
    auth.uid()
  )
  returning * into v_row;

  return jsonb_build_object(
    'transaction', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
  );
end;
$$;

create or replace function public.create_transaction(
  p_person_id    uuid,
  p_type         public.txn_type,
  p_amount_minor bigint default null,
  p_date         date default current_date,
  p_description  text default null,
  p_entered_amount_minor bigint      default null,
  p_entered_currency     text        default null,
  p_exchange_rate_e9     bigint      default null,
  p_rate_at              timestamptz default null,
  p_rate_source          text        default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner    uuid := public.assert_caller();
  v_currency text;
  v_entered  text := upper(nullif(btrim(coalesce(p_entered_currency, '')), ''));
  v_amount   bigint;
  v_row      public.transactions;
begin
  -- The ledger denomination. A NULL p_entered_currency still means "this amount
  -- is already in the account's currency", exactly as in 0011, which is what
  -- keeps a v1.1.0 client working against a person who has never switched.
  v_currency := public.person_ledger_currency(p_person_id);
  if v_currency is null then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;
  if p_date > current_date + interval '1 day' then
    raise exception 'Transaction date cannot be in the future.' using errcode = 'check_violation';
  end if;

  v_amount := public.resolve_amount_minor(
    v_currency, p_amount_minor, p_entered_amount_minor, v_entered, p_exchange_rate_e9
  );

  insert into public.transactions (
    owner_id, person_id, type, amount_minor, transaction_date, description,
    entered_amount_minor, entered_currency, exchange_rate_e9,
    exchange_rate_at, exchange_rate_source, created_by
  )
  values (
    v_owner, p_person_id, p_type, v_amount, coalesce(p_date, current_date),
    nullif(btrim(coalesce(p_description, '')), ''),
    case when v_entered is null or v_entered = v_currency then null else p_entered_amount_minor end,
    case when v_entered is null or v_entered = v_currency then null else v_entered end,
    case when v_entered is null or v_entered = v_currency then null else p_exchange_rate_e9 end,
    case when v_entered is null or v_entered = v_currency then null else coalesce(p_rate_at, now()) end,
    case when v_entered is null or v_entered = v_currency then null else left(coalesce(p_rate_source, 'manual'), 60) end,
    auth.uid()
  )
  returning * into v_row;

  return jsonb_build_object(
    'transaction', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
  );
end;
$$;

create or replace function public.update_transaction(
  p_transaction_id uuid,
  p_type           public.txn_type,
  p_amount_minor   bigint default null,
  p_date           date default null,
  p_description    text default null,
  p_entered_amount_minor bigint      default null,
  p_entered_currency     text        default null,
  p_exchange_rate_e9     bigint      default null,
  p_rate_at              timestamptz default null,
  p_rate_source          text        default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner    uuid := public.assert_caller();
  v_existing public.transactions;
  v_currency text;
  v_entered  text := upper(nullif(btrim(coalesce(p_entered_currency, '')), ''));
  v_amount   bigint;
  v_row      public.transactions;
begin
  select * into v_existing
  from public.transactions t
  where t.id = p_transaction_id and t.owner_id = v_owner and not t.is_void;

  if not found then
    raise exception 'Transaction not found, or it has been voided.'
      using errcode = 'no_data_found';
  end if;

  -- Editing a row denominates it the way it has always been denominated. This
  -- is the call that would otherwise silently re-denominate every historical
  -- row the moment its owner touched the description.
  v_currency := public.person_ledger_currency(v_existing.person_id);

  -- An edit that says nothing about currency keeps whatever the row already
  -- carried, so editing a note on a converted transaction cannot quietly
  -- restate it into the account currency.
  if v_entered is null and p_entered_amount_minor is null and p_exchange_rate_e9 is null then
    v_entered              := v_existing.entered_currency;
    p_entered_amount_minor := v_existing.entered_amount_minor;
    p_exchange_rate_e9     := v_existing.exchange_rate_e9;
    p_rate_at              := coalesce(p_rate_at, v_existing.exchange_rate_at);
    p_rate_source          := coalesce(p_rate_source, v_existing.exchange_rate_source);

    -- The amount was given in the account currency: the entered figure it was
    -- converted from is no longer what was entered, so drop the provenance
    -- rather than keep a rate that no longer explains the number.
    if p_amount_minor is not null and v_entered is not null then
      v_entered              := null;
      p_entered_amount_minor := null;
      p_exchange_rate_e9     := null;
    end if;
  end if;

  v_amount := public.resolve_amount_minor(
    v_currency, p_amount_minor, p_entered_amount_minor, v_entered, p_exchange_rate_e9
  );

  update public.transactions set
    type                 = coalesce(p_type, type),
    amount_minor         = v_amount,
    transaction_date     = coalesce(p_date, transaction_date),
    description          = nullif(btrim(coalesce(p_description, '')), ''),
    entered_amount_minor = case when v_entered is null or v_entered = v_currency then null else p_entered_amount_minor end,
    entered_currency     = case when v_entered is null or v_entered = v_currency then null else v_entered end,
    exchange_rate_e9     = case when v_entered is null or v_entered = v_currency then null else p_exchange_rate_e9 end,
    exchange_rate_at     = case when v_entered is null or v_entered = v_currency then null else coalesce(p_rate_at, now()) end,
    exchange_rate_source = case when v_entered is null or v_entered = v_currency then null else left(coalesce(p_rate_source, 'manual'), 60) end
  where id = p_transaction_id and owner_id = v_owner and not is_void
  returning * into v_row;

  return jsonb_build_object(
    'transaction', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = v_row.person_id)
  );
end;
$$;

create or replace function public.create_settlement(
  p_person_id      uuid,
  p_amount_minor   bigint default null,
  p_direction      public.settlement_direction default null,
  p_transaction_id uuid default null,
  p_date           date default current_date,
  p_note           text default null,
  p_entered_amount_minor bigint      default null,
  p_entered_currency     text        default null,
  p_exchange_rate_e9     bigint      default null,
  p_rate_at              timestamptz default null,
  p_rate_source          text        default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner     uuid := public.assert_caller();
  v_direction public.settlement_direction := p_direction;
  v_txn_type  public.txn_type;
  v_currency  text;
  v_entered   text := upper(nullif(btrim(coalesce(p_entered_currency, '')), ''));
  v_amount    bigint;
  v_remaining bigint;
  v_row       public.settlements;
begin
  -- A settlement is checked against an outstanding figure that is in the ledger
  -- currency, so it has to be converted into the ledger currency before the
  -- comparison. Using the default currency here would compare dirhams against
  -- rupees and let the over-settlement guard through.
  v_currency := public.person_ledger_currency(p_person_id);
  if v_currency is null then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  v_amount := public.resolve_amount_minor(
    v_currency, p_amount_minor, p_entered_amount_minor, v_entered, p_exchange_rate_e9
  );

  if p_transaction_id is not null then
    select t.type into v_txn_type
    from public.transactions t
    where t.id = p_transaction_id and t.owner_id = v_owner and not t.is_void;

    if v_txn_type is null then
      raise exception 'Transaction not found.' using errcode = 'no_data_found';
    end if;

    v_direction := case v_txn_type when 'credit' then 'in'::public.settlement_direction
                                   else 'out'::public.settlement_direction end;
  end if;

  if v_direction is null then
    raise exception 'Settlement direction is required.' using errcode = 'check_violation';
  end if;

  select case v_direction
           when 'in'  then b.outstanding_receivable
           else            b.outstanding_payable
         end
    into v_remaining
  from public.person_balances b
  where b.person_id = p_person_id and b.owner_id = v_owner;

  if v_remaining is null then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  if v_amount > v_remaining then
    raise exception 'Settlement of % exceeds the outstanding amount of %.',
      v_amount, v_remaining
      using errcode = 'check_violation';
  end if;

  insert into public.settlements (
    owner_id, person_id, transaction_id, direction, amount_minor, settlement_date, note,
    entered_amount_minor, entered_currency, exchange_rate_e9,
    exchange_rate_at, exchange_rate_source, created_by
  )
  values (
    v_owner, p_person_id, p_transaction_id, v_direction, v_amount,
    coalesce(p_date, current_date), nullif(btrim(coalesce(p_note, '')), ''),
    case when v_entered is null or v_entered = v_currency then null else p_entered_amount_minor end,
    case when v_entered is null or v_entered = v_currency then null else v_entered end,
    case when v_entered is null or v_entered = v_currency then null else p_exchange_rate_e9 end,
    case when v_entered is null or v_entered = v_currency then null else coalesce(p_rate_at, now()) end,
    case when v_entered is null or v_entered = v_currency then null else left(coalesce(p_rate_source, 'manual'), 60) end,
    auth.uid()
  )
  returning * into v_row;

  return jsonb_build_object(
    'settlement', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. The read path reports both currencies
--
-- `currency` keeps its meaning to the letter: the currency the figures beside
-- it are denominated in. That is now the ledger currency, which for every
-- person who has never switched is the same string 0010 returned -- so no
-- existing consumer of these views changes behaviour.
--
-- `default_currency` is new: what a new entry for this person should default
-- to. The two differ only for a person who has switched, and a client that
-- shows the difference is telling the truth about the account rather than
-- picking one and being wrong half the time.
-- -----------------------------------------------------------------------------

drop view if exists public.owner_summary;
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
  -- What every figure in this row is denominated in.
  coalesce(p.ledger_currency, p.currency, public.owner_base_currency(p.owner_id)) as currency,
  -- What the next entry for this person should default to.
  coalesce(p.currency, public.owner_base_currency(p.owner_id))                    as default_currency,
  public.owner_base_currency(p.owner_id)                                          as base_currency,
  coalesce(t.total_credit, 0)::bigint                                as total_credit,
  coalesce(t.total_debit, 0)::bigint                                 as total_debit,
  coalesce(s.settled_in, 0)::bigint                                  as settled_in,
  coalesce(s.settled_out, 0)::bigint                                 as settled_out,
  (coalesce(s.settled_in, 0) + coalesce(s.settled_out, 0))::bigint   as total_settled,
  (coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))::bigint  as outstanding_receivable,
  (coalesce(t.total_debit, 0)  - coalesce(s.settled_out, 0))::bigint as outstanding_payable,
  ((coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))
    - (coalesce(t.total_debit, 0) - coalesce(s.settled_out, 0)))::bigint as net_balance,
  -- The same net position in the owner's base currency, or NULL when no rate
  -- has ever been cached for that pair. NULL means "not known", and every
  -- consumer treats it as such rather than as zero.
  public.convert_for_owner(
    p.owner_id,
    ((coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))
      - (coalesce(t.total_debit, 0) - coalesce(s.settled_out, 0)))::bigint,
    coalesce(p.ledger_currency, p.currency, public.owner_base_currency(p.owner_id)),
    public.owner_base_currency(p.owner_id)
  )                                                                  as net_balance_base,
  -- And in the person's own default currency, for an account that has switched
  -- and whose owner thinks of it in the new currency. Display only: it moves
  -- when rates move, nothing settles against it, and it is equal to
  -- net_balance whenever the person has never switched.
  public.convert_for_owner(
    p.owner_id,
    ((coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))
      - (coalesce(t.total_debit, 0) - coalesce(s.settled_out, 0)))::bigint,
    coalesce(p.ledger_currency, p.currency, public.owner_base_currency(p.owner_id)),
    coalesce(p.currency, public.owner_base_currency(p.owner_id))
  )                                                                  as net_balance_default,
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
left join lateral (
  select sum(case when op.type = 'credit' then op.amount_minor else -op.amount_minor end) as opening_minor
  from public.transactions op
  where op.person_id = p.id and op.is_opening and not op.is_void
) o on true;

comment on view public.person_balances is
  'Authoritative per-person accounting position, denominated in that person''s ledger currency. '
  'default_currency is what new entries default to and may differ. net_balance_base and '
  'net_balance_default are display conversions at today''s cached rate and may be NULL.';

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

grant select on public.person_balances, public.owner_summary, public.activity_feed to authenticated;
revoke all on public.person_balances from anon;
revoke all on public.owner_summary   from anon;

-- -----------------------------------------------------------------------------
-- 6. The page RPCs, corrected the same way
--
-- Each of these carried `coalesce(pe.currency, base)` inline as "the currency
-- this amount is in". That expression is the bug, repeated: it names the
-- default where it means the denomination. Every one of them becomes
-- `coalesce(pe.ledger_currency, pe.currency, base)`, which is the same string
-- for every person who has never switched.
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
    'recent_activity', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.person_id, pe.name as person_name, a.entry_kind, a.entry_type,
               a.amount_minor, a.entry_date, a.note, a.created_at, a.is_opening,
               coalesce(pe.ledger_currency, pe.currency, v_base) as currency,
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
    -- What the figures on this page are in ...
    'currency', public.person_ledger_currency(p_person_id),
    -- ... and what the next entry should default to.
    'default_currency', public.person_currency(p_person_id),
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
               pb.net_balance_base, pb.currency, pb.default_currency,
               pb.base_currency, pb.is_archived
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
               coalesce(pe.ledger_currency, pe.currency,
                        public.owner_base_currency(v_owner)) as currency
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
           coalesce(pe.ledger_currency, pe.currency, v_base) as currency,
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
             coalesce(sum(public.convert_for_owner(v_owner, a.amount_minor, pc.currency, v_base))
               filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0) as credit,
             coalesce(sum(public.convert_for_owner(v_owner, a.amount_minor, pc.currency, v_base))
               filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)  as debit,
             coalesce(sum(public.convert_for_owner(v_owner, a.amount_minor, pc.currency, v_base))
               filter (where a.entry_kind = 'settlement'), 0)                              as settled,
             count(*) as entries
      from public.activity_feed a
      join public.people pe on pe.id = a.person_id
      cross join lateral (
        select coalesce(pe.ledger_currency, pe.currency, v_base) as currency
      ) pc
      where a.owner_id = v_owner
        and not a.is_void
        and a.entry_date >= current_date - p_days
      group by 1
    ) r
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.activity_summary(text, int) to authenticated;
