-- =============================================================================
-- 0014_manual_conversion.sql
-- The actual converted amount, when reality disagrees with the rate.
--
-- 0010-0013 built automatic conversion: the user types 1,000 in one currency,
-- the database converts it into the account's at a rate it records, and the
-- provenance of that rate stays on the row forever. That is right about the
-- market and sometimes wrong about the money.
--
-- A person handed AED 43 for 1,000 rupees. The rate said AED 44.20. Neither
-- figure is a mistake: the API reports what the market converts at, and the
-- manual figure reports what changed hands, after cash availability, the
-- counter's own spread, rounding and whatever was negotiated. A ledger that
-- can only record the first one is recording a number nobody exchanged.
--
-- So this migration adds a second concept beside the first, and never in place
-- of it:
--
--   * `auto_converted_amount_minor` -- what the recorded rate said the entry
--     was worth. Kept as the audit reference, never as the balance.
--   * `conversion_mode`             -- 'automatic' | 'manual'. Which of the two
--     figures `amount_minor` is.
--
-- `amount_minor` keeps its one meaning exactly: minor units in this person's
-- LEDGER currency, the canonical figure every balance is computed from. Under a
-- manual override it holds what actually changed hands, which is the correct
-- canonical answer -- the ledger records money moved, not money quoted.
--
-- WHAT THIS MIGRATION WRITES TO EXISTING ROWS: nothing.
--
-- NULL `conversion_mode` reads as 'automatic', which is exactly what every row
-- written before today was. That is the same device 0013 used for
-- `people.ledger_currency`, and it is the reason this migration touches no
-- historical amount, no historical rate and no historical id. Run
-- `node db/tools/snapshot.mjs before | after | diff` around it and every
-- fingerprint is unchanged.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The two columns
--
-- `auto_converted_amount_minor` is stored ONLY for a manual row. On an
-- automatic row it would equal `amount_minor` in every case, and a second copy
-- of a number is a second number to keep in step. Its presence is therefore
-- exactly the marker "this row was overridden", and the constraint below says
-- so rather than leaving it as folklore.
-- -----------------------------------------------------------------------------

alter table public.transactions
  add column if not exists conversion_mode             text,
  add column if not exists auto_converted_amount_minor bigint;

alter table public.settlements
  add column if not exists conversion_mode             text,
  add column if not exists auto_converted_amount_minor bigint;

do $$
begin
  alter table public.transactions drop constraint if exists transactions_conversion_mode_valid;
  alter table public.transactions add constraint transactions_conversion_mode_valid check (
    -- Only the two words mean anything.
    (conversion_mode is null or conversion_mode in ('automatic', 'manual'))
    -- A mode is a statement about a conversion, so there has to be one.
    and (conversion_mode is null or entered_currency is not null)
    -- Manual rows carry what the rate said; automatic rows do not, because on
    -- those it is amount_minor. coalesce, not a bare comparison: a NULL mode is
    -- an automatic row and has to answer this test rather than skip it.
    and ((coalesce(conversion_mode, 'automatic') = 'manual')
         = (auto_converted_amount_minor is not null))
    and (auto_converted_amount_minor is null or auto_converted_amount_minor > 0)
  );

  alter table public.settlements drop constraint if exists settlements_conversion_mode_valid;
  alter table public.settlements add constraint settlements_conversion_mode_valid check (
    (conversion_mode is null or conversion_mode in ('automatic', 'manual'))
    and (conversion_mode is null or entered_currency is not null)
    and ((coalesce(conversion_mode, 'automatic') = 'manual')
         = (auto_converted_amount_minor is not null))
    and (auto_converted_amount_minor is null or auto_converted_amount_minor > 0)
  );
end $$;

comment on column public.transactions.conversion_mode is
  'automatic | manual | NULL. NULL means automatic, which is what every row written before 0014 was. '
  'Manual means amount_minor is the figure the user says actually changed hands.';
comment on column public.transactions.auto_converted_amount_minor is
  'What exchange_rate_e9 said the entry was worth, in the ledger currency. Present only on a manual row, where it is the audit reference rather than the balance.';
comment on column public.settlements.conversion_mode is
  'automatic | manual | NULL. NULL means automatic. See transactions.conversion_mode.';
comment on column public.settlements.auto_converted_amount_minor is
  'What exchange_rate_e9 said the settlement was worth. Present only on a manual row.';

-- -----------------------------------------------------------------------------
-- 2. The one place a conversion is decided
--
-- resolve_amount_minor() from 0011 still answers "what is this worth at this
-- rate", unchanged and still used. This wraps it with the second question --
-- "and is that what actually changed hands?" -- so that no RPC holds the rule
-- and none of them can drift from another.
--
-- The automatic figure is computed even when it is about to be overridden. That
-- is deliberate: the rate is validated on every converted row whatever the
-- mode, and the reference figure exists precisely to be compared with later.
-- -----------------------------------------------------------------------------

create or replace function public.resolve_conversion(
  p_account_currency       text,
  p_amount_minor           bigint,
  p_entered_amount_minor   bigint,
  p_entered_currency       text,
  p_rate_e9                bigint,
  p_converted_amount_minor bigint default null,
  p_conversion_mode        text   default null,
  out o_amount_minor       bigint,
  out o_auto_minor         bigint,
  out o_mode               text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_entered text := upper(nullif(btrim(coalesce(p_entered_currency, '')), ''));
  v_account text := upper(coalesce(p_account_currency, 'INR'));
  v_mode    text := lower(nullif(btrim(coalesce(p_conversion_mode, '')), ''));
begin
  if v_mode is not null and v_mode not in ('automatic', 'manual') then
    raise exception 'Unknown conversion mode %.', v_mode using errcode = 'check_violation';
  end if;

  -- Nothing was converted, so there is nothing to override. An override sent
  -- against a same-currency entry is ignored rather than refused: the two
  -- figures would be the same number, and refusing would turn a harmless
  -- client into a failed save.
  if v_entered is null or v_entered = v_account then
    o_amount_minor := public.resolve_amount_minor(
      v_account, p_amount_minor, p_entered_amount_minor, null, null
    );
    o_auto_minor := null;
    o_mode       := null;
    return;
  end if;

  -- What the recorded rate says. Also validates the currency and the rate.
  o_auto_minor := public.resolve_amount_minor(
    v_account, null, p_entered_amount_minor, v_entered, p_rate_e9
  );

  -- A converted amount arriving without a mode is an override by intent: a
  -- client with nothing to say would have sent nothing.
  if v_mode is null then
    v_mode := case
                when coalesce(p_converted_amount_minor, 0) > 0 then 'manual'
                else 'automatic'
              end;
  end if;

  if v_mode = 'manual' then
    if p_converted_amount_minor is null or p_converted_amount_minor <= 0 then
      raise exception
        'Enter the actual amount that changed hands in %, or switch back to the automatic conversion.',
        v_account
        using errcode = 'check_violation';
    end if;
    -- A manual figure equal to the automatic one is still a manual figure. The
    -- user looked at the rate and confirmed it, and that is worth recording as
    -- what it is rather than collapsing back into a guess.
    o_amount_minor := p_converted_amount_minor;
    o_mode         := 'manual';
  else
    o_amount_minor := o_auto_minor;
    o_auto_minor   := null;
    o_mode         := 'automatic';
  end if;
end;
$$;

revoke all on function public.resolve_conversion(
  text, bigint, bigint, text, bigint, bigint, text
) from public;
grant execute on function public.resolve_conversion(
  text, bigint, bigint, text, bigint, bigint, text
) to authenticated, service_role;

comment on function public.resolve_conversion(text, bigint, bigint, text, bigint, bigint, text) is
  'Decides the ledger amount, the automatic reference amount and the conversion mode for one entry. The only place that rule lives.';

-- -----------------------------------------------------------------------------
-- 3. The write path
--
-- Each of these is 0013's function with two more trailing parameters, both
-- defaulted, and its call to resolve_amount_minor() replaced by
-- resolve_conversion(). A v1.1.1 client that names neither new parameter gets
-- mode 'automatic' and byte-identical behaviour.
--
-- The old signatures are dropped rather than left beside the new ones: two
-- overloads of one name make PostgREST ambiguous, and an ambiguous write path
-- is worse than either.
-- -----------------------------------------------------------------------------

drop function if exists public.set_person_opening_balance(
  uuid, text, bigint, date, bigint, text, bigint, timestamptz, text
);

create or replace function public.set_person_opening_balance(
  p_person_id            uuid,
  p_direction            text,                     -- 'they_owe_me' | 'i_owe_them' | 'none'
  p_amount_minor         bigint      default null,
  p_date                 date        default null,
  p_entered_amount_minor bigint      default null,
  p_entered_currency     text        default null,
  p_rate_e9              bigint      default null,
  p_rate_at              timestamptz default null,
  p_rate_source          text        default null,
  p_converted_amount_minor bigint    default null,
  p_conversion_mode      text        default null
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
  v_conv     record;
  v_foreign  boolean;
  v_existing uuid;
  v_row      public.transactions;
begin
  select * into v_person
  from public.people p
  where p.id = p_person_id and p.owner_id = v_owner;

  if not found then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  -- The denomination, not the default (0013 upgrade 5).
  v_currency := coalesce(v_person.ledger_currency, v_person.currency,
                         public.owner_base_currency(v_owner));

  -- Replacing an opening balance retracts the old one rather than editing it,
  -- so the correction is visible in the history.
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

  v_conv := public.resolve_conversion(
    v_currency, p_amount_minor, p_entered_amount_minor, v_entered, p_rate_e9,
    p_converted_amount_minor, p_conversion_mode
  );
  v_foreign := v_entered is not null and v_entered <> v_currency;

  insert into public.transactions (
    owner_id, person_id, type, amount_minor, transaction_date, description,
    is_opening, entered_amount_minor, entered_currency,
    exchange_rate_e9, exchange_rate_at, exchange_rate_source,
    conversion_mode, auto_converted_amount_minor, created_by
  )
  values (
    v_owner, p_person_id, v_type, v_conv.o_amount_minor,
    coalesce(p_date, v_person.created_at::date, current_date),
    'Opening balance',
    true,
    case when v_foreign then p_entered_amount_minor end,
    case when v_foreign then v_entered end,
    case when v_foreign then p_rate_e9 end,
    case when v_foreign then coalesce(p_rate_at, now()) end,
    case when v_foreign then left(coalesce(p_rate_source, 'manual'), 60) end,
    v_conv.o_mode,
    v_conv.o_auto_minor,
    auth.uid()
  )
  returning * into v_row;

  return jsonb_build_object(
    'transaction', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
  );
end;
$$;

-- -----------------------------------------------------------------------------

drop function if exists public.create_transaction(
  uuid, public.txn_type, bigint, date, text, bigint, text, bigint, timestamptz, text
);

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
  p_rate_source          text        default null,
  p_converted_amount_minor bigint    default null,
  p_conversion_mode      text        default null
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
  v_conv     record;
  v_foreign  boolean;
  v_row      public.transactions;
begin
  v_currency := public.person_ledger_currency(p_person_id);
  if v_currency is null then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;
  if p_date > current_date + interval '1 day' then
    raise exception 'Transaction date cannot be in the future.' using errcode = 'check_violation';
  end if;

  v_conv := public.resolve_conversion(
    v_currency, p_amount_minor, p_entered_amount_minor, v_entered, p_exchange_rate_e9,
    p_converted_amount_minor, p_conversion_mode
  );
  v_foreign := v_entered is not null and v_entered <> v_currency;

  insert into public.transactions (
    owner_id, person_id, type, amount_minor, transaction_date, description,
    entered_amount_minor, entered_currency, exchange_rate_e9,
    exchange_rate_at, exchange_rate_source,
    conversion_mode, auto_converted_amount_minor, created_by
  )
  values (
    v_owner, p_person_id, p_type, v_conv.o_amount_minor, coalesce(p_date, current_date),
    nullif(btrim(coalesce(p_description, '')), ''),
    case when v_foreign then p_entered_amount_minor end,
    case when v_foreign then v_entered end,
    case when v_foreign then p_exchange_rate_e9 end,
    case when v_foreign then coalesce(p_rate_at, now()) end,
    case when v_foreign then left(coalesce(p_rate_source, 'manual'), 60) end,
    v_conv.o_mode,
    v_conv.o_auto_minor,
    auth.uid()
  )
  returning * into v_row;

  return jsonb_build_object(
    'transaction', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
  );
end;
$$;

-- -----------------------------------------------------------------------------

drop function if exists public.update_transaction(
  uuid, public.txn_type, bigint, date, text, bigint, text, bigint, timestamptz, text
);

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
  p_rate_source          text        default null,
  p_converted_amount_minor bigint    default null,
  p_conversion_mode      text        default null
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
  v_conv     record;
  v_foreign  boolean;
  v_row      public.transactions;
begin
  select * into v_existing
  from public.transactions t
  where t.id = p_transaction_id and t.owner_id = v_owner and not t.is_void;

  if not found then
    raise exception 'Transaction not found, or it has been voided.'
      using errcode = 'no_data_found';
  end if;

  -- Editing a row denominates it the way it has always been denominated.
  v_currency := public.person_ledger_currency(v_existing.person_id);

  -- An edit that says nothing about currency keeps whatever the row already
  -- carried -- and, since 0014, that includes the override. Editing the note on
  -- a manually converted row must not quietly restate it at the stored rate,
  -- which is the whole of "preserve the manual override if one exists".
  if v_entered is null and p_entered_amount_minor is null and p_exchange_rate_e9 is null then
    v_entered              := v_existing.entered_currency;
    p_entered_amount_minor := v_existing.entered_amount_minor;
    p_exchange_rate_e9     := v_existing.exchange_rate_e9;
    p_rate_at              := coalesce(p_rate_at, v_existing.exchange_rate_at);
    p_rate_source          := coalesce(p_rate_source, v_existing.exchange_rate_source);

    if p_conversion_mode is null then
      p_conversion_mode := v_existing.conversion_mode;
      -- On a stored manual row the manual figure IS amount_minor; that is what
      -- "manual" means here. Carry it forward so the row survives its own edit.
      if coalesce(p_conversion_mode, 'automatic') = 'manual'
         and p_converted_amount_minor is null then
        p_converted_amount_minor := v_existing.amount_minor;
      end if;
    end if;

    -- The amount was restated in the account currency: the entered figure it
    -- was converted from is no longer what was entered, so drop the whole
    -- conversion rather than keep a rate and a mode that explain nothing.
    if p_amount_minor is not null and v_entered is not null then
      v_entered                := null;
      p_entered_amount_minor   := null;
      p_exchange_rate_e9       := null;
      p_converted_amount_minor := null;
      p_conversion_mode        := null;
    end if;
  end if;

  v_conv := public.resolve_conversion(
    v_currency, p_amount_minor, p_entered_amount_minor, v_entered, p_exchange_rate_e9,
    p_converted_amount_minor, p_conversion_mode
  );
  v_foreign := v_entered is not null and v_entered <> v_currency;

  update public.transactions set
    type                 = coalesce(p_type, type),
    amount_minor         = v_conv.o_amount_minor,
    transaction_date     = coalesce(p_date, transaction_date),
    description          = nullif(btrim(coalesce(p_description, '')), ''),
    entered_amount_minor = case when v_foreign then p_entered_amount_minor end,
    entered_currency     = case when v_foreign then v_entered end,
    exchange_rate_e9     = case when v_foreign then p_exchange_rate_e9 end,
    exchange_rate_at     = case when v_foreign then coalesce(p_rate_at, now()) end,
    exchange_rate_source = case when v_foreign then left(coalesce(p_rate_source, 'manual'), 60) end,
    conversion_mode             = v_conv.o_mode,
    auto_converted_amount_minor = v_conv.o_auto_minor
  where id = p_transaction_id and owner_id = v_owner and not is_void
  returning * into v_row;

  return jsonb_build_object(
    'transaction', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = v_row.person_id)
  );
end;
$$;

-- -----------------------------------------------------------------------------

drop function if exists public.create_settlement(
  uuid, bigint, public.settlement_direction, uuid, date, text,
  bigint, text, bigint, timestamptz, text
);

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
  p_rate_source          text        default null,
  p_converted_amount_minor bigint    default null,
  p_conversion_mode      text        default null
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
  v_conv      record;
  v_foreign   boolean;
  v_remaining bigint;
  v_row       public.settlements;
begin
  v_currency := public.person_ledger_currency(p_person_id);
  if v_currency is null then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  -- The override lands BEFORE the over-settlement guard, on purpose. The guard
  -- compares what is being settled with what is outstanding, and what is being
  -- settled is the money that changed hands -- not what the rate said it should
  -- have been.
  v_conv := public.resolve_conversion(
    v_currency, p_amount_minor, p_entered_amount_minor, v_entered, p_exchange_rate_e9,
    p_converted_amount_minor, p_conversion_mode
  );
  v_foreign := v_entered is not null and v_entered <> v_currency;

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

  if v_conv.o_amount_minor > v_remaining then
    raise exception 'Settlement of % exceeds the outstanding amount of %.',
      v_conv.o_amount_minor, v_remaining
      using errcode = 'check_violation';
  end if;

  insert into public.settlements (
    owner_id, person_id, transaction_id, direction, amount_minor, settlement_date, note,
    entered_amount_minor, entered_currency, exchange_rate_e9,
    exchange_rate_at, exchange_rate_source,
    conversion_mode, auto_converted_amount_minor, created_by
  )
  values (
    v_owner, p_person_id, p_transaction_id, v_direction, v_conv.o_amount_minor,
    coalesce(p_date, current_date), nullif(btrim(coalesce(p_note, '')), ''),
    case when v_foreign then p_entered_amount_minor end,
    case when v_foreign then v_entered end,
    case when v_foreign then p_exchange_rate_e9 end,
    case when v_foreign then coalesce(p_rate_at, now()) end,
    case when v_foreign then left(coalesce(p_rate_source, 'manual'), 60) end,
    v_conv.o_mode,
    v_conv.o_auto_minor,
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
-- create_person() only forwards the opening balance, but its call now has two
-- more arguments to forward, and its own signature has to grow to accept them
-- from the form.
-- -----------------------------------------------------------------------------

drop function if exists public.create_person(
  text, public.party_type, text, text, text, text, text,
  text, bigint, date, bigint, text, bigint, timestamptz, text
);

create or replace function public.create_person(
  p_name     text,
  p_type     public.party_type default 'person',
  p_phone    text default null,
  p_email    text default null,
  p_address  text default null,
  p_notes    text default null,
  p_currency text default null,
  p_opening_direction      text   default null,   -- 'they_owe_me' | 'i_owe_them' | null
  p_opening_amount_minor   bigint default null,
  p_opening_date           date   default null,
  p_opening_entered_minor  bigint default null,
  p_opening_entered_currency text default null,
  p_opening_rate_e9        bigint default null,
  p_opening_rate_at        timestamptz default null,
  p_opening_rate_source    text   default null,
  p_opening_converted_minor bigint default null,
  p_opening_conversion_mode text  default null
)
returns public.people
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner    uuid := public.assert_caller();
  v_row      public.people;
  v_currency text := upper(nullif(btrim(coalesce(p_currency, '')), ''));
begin
  if btrim(coalesce(p_name, '')) = '' then
    raise exception 'Name is required.' using errcode = 'check_violation';
  end if;
  if v_currency is not null and not public.is_supported_currency(v_currency) then
    raise exception 'Unsupported currency %.', v_currency using errcode = 'check_violation';
  end if;

  insert into public.people (owner_id, name, type, phone, email, address, notes, currency)
  values (
    v_owner,
    btrim(p_name),
    coalesce(p_type, 'person'),
    nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_email, '')), ''),
    nullif(btrim(coalesce(p_address, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), ''),
    v_currency
  )
  returning * into v_row;

  if coalesce(p_opening_direction, 'none') <> 'none'
     and coalesce(p_opening_amount_minor, p_opening_entered_minor, 0) > 0 then
    perform public.set_person_opening_balance(
      p_person_id              => v_row.id,
      p_direction              => p_opening_direction,
      p_amount_minor           => p_opening_amount_minor,
      p_date                   => p_opening_date,
      p_entered_amount_minor   => p_opening_entered_minor,
      p_entered_currency       => p_opening_entered_currency,
      p_rate_e9                => p_opening_rate_e9,
      p_rate_at                => p_opening_rate_at,
      p_rate_source            => p_opening_rate_source,
      p_converted_amount_minor => p_opening_converted_minor,
      p_conversion_mode        => p_opening_conversion_mode
    );
  end if;

  return v_row;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. The read path carries the override
--
-- Two more columns on the activity feed, and the three page RPCs that select
-- explicit lists from it. Nothing else changes: no figure moves, and a client
-- that ignores the new keys renders exactly what it rendered before.
--
-- The view resolves NULL to 'automatic' rather than passing it through, so a
-- client never has to know that pre-0014 rows stored nothing there.
-- -----------------------------------------------------------------------------

-- Dropped and recreated rather than replaced: the two new columns land before
-- `related_transaction_id`, and CREATE OR REPLACE VIEW may only append. Nothing
-- depends on this view but the plpgsql RPCs below, which bind by name at call
-- time, so the drop costs nothing.
drop view if exists public.activity_feed;

create view public.activity_feed
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
  case when t.entered_currency is null then null
       else coalesce(t.conversion_mode, 'automatic') end as conversion_mode,
  t.auto_converted_amount_minor,
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
  case when s.entered_currency is null then null
       else coalesce(s.conversion_mode, 'automatic') end,
  s.auto_converted_amount_minor,
  s.transaction_id,
  s.created_at
from public.settlements s;

comment on view public.activity_feed is
  'Chronological union of transactions and settlements. Order by entry_date desc, created_at desc. '
  'conversion_mode is resolved here, so the NULL stored on a pre-0014 row reads as the automatic conversion it was.';

grant select on public.activity_feed to authenticated;
revoke all on public.activity_feed from anon;

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
  v_owner  uuid := public.assert_caller();
  v_base   text := public.owner_base_currency(v_owner);
  v_result jsonb;
begin
  p_activity_limit := least(greatest(coalesce(p_activity_limit, 10), 1), 50);
  p_people_limit   := least(greatest(coalesce(p_people_limit, 8), 1), 50);

  select jsonb_build_object(
    'summary', (select to_jsonb(s) from public.owner_summary s where s.owner_id = v_owner),
    'base_currency', v_base,
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
               a.conversion_mode, a.auto_converted_amount_minor,
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
           a.entered_amount_minor, a.entered_currency, a.exchange_rate_e9,
           a.conversion_mode, a.auto_converted_amount_minor
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
-- 5. Grants for the widened write path
-- -----------------------------------------------------------------------------

grant execute on function public.create_person(
  text, public.party_type, text, text, text, text, text,
  text, bigint, date, bigint, text, bigint, timestamptz, text, bigint, text
) to authenticated;

grant execute on function public.set_person_opening_balance(
  uuid, text, bigint, date, bigint, text, bigint, timestamptz, text, bigint, text
) to authenticated;

grant execute on function public.create_transaction(
  uuid, public.txn_type, bigint, date, text, bigint, text, bigint, timestamptz, text,
  bigint, text
) to authenticated;

grant execute on function public.update_transaction(
  uuid, public.txn_type, bigint, date, text, bigint, text, bigint, timestamptz, text,
  bigint, text
) to authenticated;

grant execute on function public.create_settlement(
  uuid, bigint, public.settlement_direction, uuid, date, text,
  bigint, text, bigint, timestamptz, text, bigint, text
) to authenticated;

notify pgrst, 'reload schema';
