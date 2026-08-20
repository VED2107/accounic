-- =============================================================================
-- 0002_ledger.sql
-- people, transactions, settlements + integrity constraints.
--
-- Money rule (context.md §7): all amounts are integer minor units (paise for
-- INR). No numeric/float column anywhere in the money path.
--
-- Ownership rule (context.md §12): a child row must belong to the same owner as
-- its parent. Enforced structurally with composite foreign keys rather than
-- triggers, so it holds even for service-role writes and bulk imports.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- people  (context.md §5)
-- -----------------------------------------------------------------------------

create table if not exists public.people (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  name        text not null,
  type        public.party_type not null default 'person',
  phone       text,
  email       citext,
  address     text,
  notes       text,
  is_archived boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint people_name_not_blank check (btrim(name) <> ''),
  constraint people_name_len       check (char_length(name) <= 120),
  constraint people_phone_len      check (phone is null or char_length(phone) between 3 and 32),
  constraint people_address_len    check (address is null or char_length(address) <= 500),
  constraint people_notes_len      check (notes is null or char_length(notes) <= 2000),

  -- Composite target so children can prove they share the owner.
  constraint people_owner_id_uniq unique (owner_id, id)
);

comment on table public.people is
  'A person or business the owner transacts with. Generic on purpose (context.md §5).';

drop trigger if exists people_touch on public.people;
create trigger people_touch
  before update on public.people
  for each row execute function public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- transactions  (context.md §7, §8)
-- -----------------------------------------------------------------------------

create table if not exists public.transactions (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references public.profiles (id) on delete cascade,
  person_id        uuid not null,
  type             public.txn_type not null,
  amount_minor     bigint not null,
  transaction_date date   not null default current_date,
  description      text,
  is_void          boolean not null default false,
  void_reason      text,
  created_by       uuid references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  constraint transactions_amount_positive check (amount_minor > 0),
  -- Guards against a mis-scaled entry (₹92,233,720,368.54 ceiling) and overflow
  -- in downstream sums.
  constraint transactions_amount_sane     check (amount_minor <= 9223372036854),
  constraint transactions_desc_len        check (description is null or char_length(description) <= 500),
  constraint transactions_void_reason     check (is_void or void_reason is null),

  -- person must belong to the same owner (context.md §12)
  constraint transactions_person_same_owner
    foreign key (owner_id, person_id)
    references public.people (owner_id, id)
    on delete restrict,

  constraint transactions_owner_id_uniq unique (owner_id, id)
);

comment on column public.transactions.amount_minor is
  'Integer minor units (paise for INR). Always positive; direction is carried by type.';
comment on column public.transactions.is_void is
  'Voided transactions stay in history but are excluded from every balance (context.md §17).';

drop trigger if exists transactions_touch on public.transactions;
create trigger transactions_touch
  before update on public.transactions
  for each row execute function public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- settlements  (context.md §9)
--
-- direction is the authoritative field:
--   'in'  money the user received  -> reduces outstanding receivable
--   'out' money the user paid      -> reduces outstanding payable
--
-- transaction_id is an OPTIONAL reference meaning "the user pressed Settle on
-- this row". Balances never depend on it; it only biases display allocation
-- (see 0003_engine.sql). Account-level settlement = transaction_id null.
-- -----------------------------------------------------------------------------

create table if not exists public.settlements (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null references public.profiles (id) on delete cascade,
  person_id       uuid not null,
  transaction_id  uuid,
  direction       public.settlement_direction not null,
  amount_minor    bigint not null,
  settlement_date date not null default current_date,
  note            text,
  is_void         boolean not null default false,
  void_reason     text,
  created_by      uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint settlements_amount_positive check (amount_minor > 0),
  constraint settlements_amount_sane     check (amount_minor <= 9223372036854),
  constraint settlements_note_len        check (note is null or char_length(note) <= 500),
  constraint settlements_void_reason     check (is_void or void_reason is null),

  constraint settlements_person_same_owner
    foreign key (owner_id, person_id)
    references public.people (owner_id, id)
    on delete restrict,

  -- If a transaction is referenced it must be the same owner's transaction.
  constraint settlements_txn_same_owner
    foreign key (owner_id, transaction_id)
    references public.transactions (owner_id, id)
    on delete set null (transaction_id)
);

comment on table public.settlements is
  'Money that actually moved. Reduces outstanding balance; never mutates the original transaction.';

drop trigger if exists settlements_touch on public.settlements;
create trigger settlements_touch
  before update on public.settlements
  for each row execute function public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Cross-row consistency that a CHECK cannot express.
-- -----------------------------------------------------------------------------

create or replace function public.validate_settlement_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_txn public.transactions%rowtype;
begin
  if new.transaction_id is not null then
    select * into v_txn
    from public.transactions t
    where t.id = new.transaction_id;

    if not found then
      raise exception 'Referenced transaction does not exist.'
        using errcode = 'foreign_key_violation';
    end if;

    if v_txn.person_id <> new.person_id then
      raise exception 'Settlement and transaction belong to different people.'
        using errcode = 'check_violation';
    end if;

    if v_txn.is_void then
      raise exception 'Cannot settle a voided transaction.'
        using errcode = 'check_violation';
    end if;

    -- credit is settled by money coming in; debit by money going out.
    if (v_txn.type = 'credit' and new.direction <> 'in')
       or (v_txn.type = 'debit' and new.direction <> 'out') then
      raise exception 'Settlement direction does not match the transaction type.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists settlements_validate on public.settlements;
create trigger settlements_validate
  before insert or update on public.settlements
  for each row execute function public.validate_settlement_row();

-- -----------------------------------------------------------------------------
-- Over-settlement guard (context.md §12).
--
-- Runs as a CONSTRAINT TRIGGER deferred to end of statement so that a multi-row
-- statement is judged on its final state, not row by row. Compares, per
-- (owner, person, direction), the total settled against the total transacted.
-- -----------------------------------------------------------------------------

create or replace function public.assert_not_oversettled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner     uuid;
  v_person    uuid;
  v_direction public.settlement_direction;
  v_txn_type  public.txn_type;
  v_settled   bigint;
  v_charged   bigint;
begin
  v_owner     := coalesce(new.owner_id,  old.owner_id);
  v_person    := coalesce(new.person_id, old.person_id);
  v_direction := coalesce(new.direction, old.direction);
  v_txn_type  := case v_direction when 'in' then 'credit'::public.txn_type
                                  else 'debit'::public.txn_type end;

  select coalesce(sum(s.amount_minor), 0) into v_settled
  from public.settlements s
  where s.owner_id  = v_owner
    and s.person_id = v_person
    and s.direction = v_direction
    and not s.is_void;

  select coalesce(sum(t.amount_minor), 0) into v_charged
  from public.transactions t
  where t.owner_id  = v_owner
    and t.person_id = v_person
    and t.type      = v_txn_type
    and not t.is_void;

  if v_settled > v_charged then
    raise exception
      'Settlement exceeds the outstanding amount (settled %, outstanding basis %).',
      v_settled, v_charged
      using errcode = 'check_violation',
            hint    = 'Reduce the settlement amount or record the missing transaction first.';
  end if;

  return null;
end;
$$;

drop trigger if exists settlements_no_oversettle on public.settlements;
create constraint trigger settlements_no_oversettle
  after insert or update on public.settlements
  deferrable initially deferred
  for each row execute function public.assert_not_oversettled();

-- The same invariant can be broken from the transaction side: voiding or
-- shrinking a transaction can leave prior settlements stranded above the basis.
create or replace function public.assert_txn_keeps_settlements_valid()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_direction public.settlement_direction;
  v_settled   bigint;
  v_charged   bigint;
begin
  v_direction := case old.type when 'credit' then 'in'::public.settlement_direction
                               else 'out'::public.settlement_direction end;

  select coalesce(sum(s.amount_minor), 0) into v_settled
  from public.settlements s
  where s.owner_id  = old.owner_id
    and s.person_id = old.person_id
    and s.direction = v_direction
    and not s.is_void;

  select coalesce(sum(t.amount_minor), 0) into v_charged
  from public.transactions t
  where t.owner_id  = old.owner_id
    and t.person_id = old.person_id
    and t.type      = old.type
    and not t.is_void;

  if v_settled > v_charged then
    raise exception
      'This change would leave % settled against only % of transactions.',
      v_settled, v_charged
      using errcode = 'check_violation',
            hint    = 'Void or reduce the related settlements first.';
  end if;

  return null;
end;
$$;

drop trigger if exists transactions_keep_settlements_valid on public.transactions;
create constraint trigger transactions_keep_settlements_valid
  after update or delete on public.transactions
  deferrable initially deferred
  for each row execute function public.assert_txn_keeps_settlements_valid();
