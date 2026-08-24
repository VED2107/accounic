-- =============================================================================
-- 0011_currency_mutations.sql
-- The write path for per-person currency, opening balances and conversion.
--
-- Every RPC here replaces one from 0004 with a wider signature whose new
-- parameters all carry defaults, so a client built before this migration calls
-- it by name and gets exactly its old behaviour. The old signatures are dropped
-- rather than left beside the new ones: two overloads of the same name make
-- PostgREST ambiguous, and an ambiguous write path is worse than either.
--
-- The conversion itself is computed here and nowhere else. A client sends what
-- the user typed, in which currency, and at which rate; the database decides
-- what that is worth in the account's currency. That is what keeps the three
-- clients from disagreeing about somebody's money by a rounding step.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- The one place an entered amount becomes an account amount.
-- -----------------------------------------------------------------------------

create or replace function public.resolve_amount_minor(
  p_account_currency     text,
  p_amount_minor         bigint,
  p_entered_amount_minor bigint,
  p_entered_currency     text,
  p_rate_e9              bigint
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_entered text := upper(nullif(btrim(coalesce(p_entered_currency, '')), ''));
  v_account text := upper(coalesce(p_account_currency, 'INR'));
  v_result  bigint;
begin
  -- Nothing foreign was entered: the amount is already in the account currency.
  if v_entered is null or v_entered = v_account then
    v_result := coalesce(p_amount_minor, p_entered_amount_minor);
    if v_result is null or v_result <= 0 then
      raise exception 'Amount must be greater than zero.' using errcode = 'check_violation';
    end if;
    return v_result;
  end if;

  if not public.is_supported_currency(v_entered) then
    raise exception 'Unsupported currency %.', v_entered using errcode = 'check_violation';
  end if;
  if p_entered_amount_minor is null or p_entered_amount_minor <= 0 then
    raise exception 'Amount must be greater than zero.' using errcode = 'check_violation';
  end if;
  if p_rate_e9 is null or p_rate_e9 <= 0 then
    raise exception
      'An exchange rate is required to record % against a % account.', v_entered, v_account
      using errcode = 'check_violation',
            hint    = 'Connect once to fetch a rate, or enter the amount in the account currency.';
  end if;

  v_result := public.convert_amount_minor(p_entered_amount_minor, v_entered, v_account, p_rate_e9);

  if v_result is null or v_result <= 0 then
    raise exception
      'That amount converts to nothing in %. Check the amount and the rate.', v_account
      using errcode = 'check_violation';
  end if;
  return v_result;
end;
$$;

revoke all on function public.resolve_amount_minor(text, bigint, bigint, text, bigint) from public;
grant execute on function public.resolve_amount_minor(text, bigint, bigint, text, bigint)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- People (upgrade §1, §3, §4)
-- -----------------------------------------------------------------------------

drop function if exists public.create_person(text, public.party_type, text, text, text, text);

create or replace function public.create_person(
  p_name     text,
  p_type     public.party_type default 'person',
  p_phone    text default null,
  p_email    text default null,
  p_address  text default null,
  p_notes    text default null,
  p_currency text default null,
  -- Opening balance, all optional (upgrade §4). Direction is stated in the
  -- user's words rather than in the engine's, because "credit" is exactly the
  -- word people get backwards.
  p_opening_direction      text   default null,   -- 'they_owe_me' | 'i_owe_them' | null
  p_opening_amount_minor   bigint default null,
  p_opening_date           date   default null,
  p_opening_entered_minor  bigint default null,
  p_opening_entered_currency text default null,
  p_opening_rate_e9        bigint default null,
  p_opening_rate_at        timestamptz default null,
  p_opening_rate_source    text   default null
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
      p_person_id            => v_row.id,
      p_direction            => p_opening_direction,
      p_amount_minor         => p_opening_amount_minor,
      p_date                 => p_opening_date,
      p_entered_amount_minor => p_opening_entered_minor,
      p_entered_currency     => p_opening_entered_currency,
      p_rate_e9              => p_opening_rate_e9,
      p_rate_at              => p_opening_rate_at,
      p_rate_source          => p_opening_rate_source
    );
  end if;

  return v_row;
end;
$$;

drop function if exists public.update_person(uuid, text, public.party_type, text, text, text, text);

create or replace function public.update_person(
  p_person_id uuid,
  p_name      text,
  p_type      public.party_type,
  p_phone     text default null,
  p_email     text default null,
  p_address   text default null,
  p_notes     text default null,
  p_currency  text default null,
  -- Changing the currency of an account that already holds entries restates
  -- them, which changes numbers the user has seen. It therefore needs saying so
  -- out loud (upgrade §1).
  p_restate_confirmed boolean default false,
  p_restate_rate_e9   bigint  default null
)
returns public.people
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner    uuid := public.assert_caller();
  v_row      public.people;
  v_current  public.people;
  v_old_ccy  text;
  v_new_ccy  text := upper(nullif(btrim(coalesce(p_currency, '')), ''));
  v_live     int;
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

  if v_new_ccy is not null then
    if not public.is_supported_currency(v_new_ccy) then
      raise exception 'Unsupported currency %.', v_new_ccy using errcode = 'check_violation';
    end if;

    if v_new_ccy <> v_old_ccy then
      select count(*) into v_live
      from public.transactions t
      where t.person_id = p_person_id and t.owner_id = v_owner and not t.is_void;

      select v_live + count(*) into v_live
      from public.settlements s
      where s.person_id = p_person_id and s.owner_id = v_owner and not s.is_void;

      if v_live > 0 then
        if not coalesce(p_restate_confirmed, false) then
          raise exception
            'This account holds % entries recorded in %. Changing it to % restates them at a rate you confirm; the original amounts are kept on every row.',
            v_live, v_old_ccy, v_new_ccy
            using errcode   = 'check_violation',
                  hint      = 'Confirm the change to continue.',
                  detail    = v_old_ccy || '->' || v_new_ccy;
        end if;
        perform public.restate_person_currency(
          p_person_id, v_old_ccy, v_new_ccy, p_restate_rate_e9
        );
      end if;
    end if;
  end if;

  update public.people set
    name     = btrim(p_name),
    type     = coalesce(p_type, type),
    phone    = nullif(btrim(coalesce(p_phone, '')), ''),
    email    = nullif(btrim(coalesce(p_email, '')), ''),
    address  = nullif(btrim(coalesce(p_address, '')), ''),
    notes    = nullif(btrim(coalesce(p_notes, '')), ''),
    currency = coalesce(v_new_ccy, currency)
  where id = p_person_id and owner_id = v_owner
  returning * into v_row;

  return v_row;
end;
$$;

-- -----------------------------------------------------------------------------
-- Restating an account into a different currency.
--
-- Every row keeps what was originally entered — amount, currency and the rate
-- that was used — so nothing is lost and the restatement can be read back. Only
-- `amount_minor`, which is by definition "in the account's currency", moves.
--
-- Voided rows are restated too. They contribute to no balance, but leaving them
-- denominated in the old currency would make the timeline read as two
-- currencies at once, and a retraction that no longer matches what it retracted
-- is worse than useless. The immutability guard in 0005 refuses to edit a
-- voided row, so this sets a transaction-local marker it honours; nothing else
-- sets it, and it dies with the transaction.
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
  if old.is_void and new.is_void
     and coalesce(current_setting('accounic.restating', true), '') <> 'on' then
    raise exception 'A voided record cannot be edited.' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create or replace function public.restate_person_currency(
  p_person_id uuid,
  p_from      text,
  p_to        text,
  p_rate_e9   bigint
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner   uuid := public.assert_caller();
  v_dir     public.settlement_direction;
  v_type    public.txn_type;
  v_charged bigint;
  v_settled bigint;
  v_excess  bigint;
  v_id      uuid;
  v_amount  bigint;
begin
  if p_rate_e9 is null or p_rate_e9 <= 0 then
    raise exception 'A rate is required to restate % into %.', p_from, p_to
      using errcode = 'check_violation';
  end if;

  perform set_config('accounic.restating', 'on', true);

  -- Stamp the original values on any row that does not already carry them, then
  -- move amount_minor into the new currency. A row that was already entered in
  -- some third currency keeps that as its origin and has its rate composed, so
  -- "what did I actually hand over" survives any number of restatements.
  update public.transactions t set
    entered_amount_minor = coalesce(t.entered_amount_minor, t.amount_minor),
    entered_currency     = coalesce(t.entered_currency, p_from),
    exchange_rate_e9     = case
                             when t.entered_currency is null then p_rate_e9
                             else round(t.exchange_rate_e9::numeric * p_rate_e9 / 1000000000)::bigint
                           end,
    exchange_rate_at     = coalesce(t.exchange_rate_at, now()),
    exchange_rate_source = coalesce(t.exchange_rate_source, 'restated ' || p_from || '->' || p_to),
    amount_minor         = public.convert_amount_minor(t.amount_minor, p_from, p_to, p_rate_e9)
  where t.person_id = p_person_id and t.owner_id = v_owner;

  update public.settlements s set
    entered_amount_minor = coalesce(s.entered_amount_minor, s.amount_minor),
    entered_currency     = coalesce(s.entered_currency, p_from),
    exchange_rate_e9     = case
                             when s.entered_currency is null then p_rate_e9
                             else round(s.exchange_rate_e9::numeric * p_rate_e9 / 1000000000)::bigint
                           end,
    exchange_rate_at     = coalesce(s.exchange_rate_at, now()),
    exchange_rate_source = coalesce(s.exchange_rate_source, 'restated ' || p_from || '->' || p_to),
    amount_minor         = public.convert_amount_minor(s.amount_minor, p_from, p_to, p_rate_e9)
  where s.person_id = p_person_id and s.owner_id = v_owner;

  -- Rounding each row independently can leave a fully settled account settled by
  -- one minor unit more than it was charged, which the over-settlement guard
  -- would refuse at commit — correctly. Absorb the difference into the newest
  -- settlement on that side, which is the only place it can go without
  -- inventing money.
  foreach v_dir in array array['in', 'out']::public.settlement_direction[] loop
    v_type := case v_dir when 'in' then 'credit'::public.txn_type
                         else 'debit'::public.txn_type end;

    select coalesce(sum(t.amount_minor), 0) into v_charged
    from public.transactions t
    where t.person_id = p_person_id and t.type = v_type and not t.is_void;

    select coalesce(sum(s.amount_minor), 0) into v_settled
    from public.settlements s
    where s.person_id = p_person_id and s.direction = v_dir and not s.is_void;

    v_excess := v_settled - v_charged;
    continue when v_excess <= 0;

    select s.id, s.amount_minor into v_id, v_amount
    from public.settlements s
    where s.person_id = p_person_id and s.direction = v_dir and not s.is_void
    order by s.settlement_date desc, s.created_at desc, s.id desc
    limit 1;

    if v_id is null or v_amount - v_excess <= 0 then
      raise exception
        'Restating this account into % cannot be done without changing what has been settled.', p_to
        using errcode = 'check_violation';
    end if;

    update public.settlements set amount_minor = v_amount - v_excess where id = v_id;
  end loop;

  perform set_config('accounic.restating', 'off', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- Opening balance (upgrade §3)
--
-- Recorded as a transaction carrying `is_opening`, so it is part of the balance
-- by construction rather than by a second code path that would have to be kept
-- in step with the engine. It is presented as "Opening Balance" everywhere, and
-- its date defaults to the day the account was created rather than to today.
--
-- Direction is the user's sentence, not the engine's vocabulary:
--   'they_owe_me' -> a receivable  -> stored type 'credit'
--   'i_owe_them'  -> a payable     -> stored type 'debit'
-- (See docs/accounting-direction.md for why those two words read backwards.)
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

  v_currency := coalesce(v_person.currency, public.owner_base_currency(v_owner));

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
    v_currency, p_amount_minor, p_entered_amount_minor, p_entered_currency, p_rate_e9
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
    case when upper(coalesce(p_entered_currency, v_currency)) = v_currency
         then null else p_entered_amount_minor end,
    case when upper(coalesce(p_entered_currency, v_currency)) = v_currency
         then null else upper(p_entered_currency) end,
    case when upper(coalesce(p_entered_currency, v_currency)) = v_currency
         then null else p_rate_e9 end,
    case when upper(coalesce(p_entered_currency, v_currency)) = v_currency
         then null else coalesce(p_rate_at, now()) end,
    case when upper(coalesce(p_entered_currency, v_currency)) = v_currency
         then null else left(coalesce(p_rate_source, 'manual'), 60) end,
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
-- Transactions (upgrade §2, §5, §11)
-- -----------------------------------------------------------------------------

drop function if exists public.create_transaction(uuid, public.txn_type, bigint, date, text);

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
  v_currency := public.person_currency(p_person_id);
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

drop function if exists public.update_transaction(uuid, public.txn_type, bigint, date, text);

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

  v_currency := public.person_currency(v_existing.person_id);

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

-- -----------------------------------------------------------------------------
-- Settlements (upgrade §2)
-- -----------------------------------------------------------------------------

drop function if exists public.create_settlement(uuid, bigint, public.settlement_direction, uuid, date, text);

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
  v_currency := public.person_currency(p_person_id);
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

-- settle_account() calls create_settlement() by name; the new defaults keep it
-- working unchanged, but it is re-created here so the file is self-contained
-- and so the account-currency path is explicit.
create or replace function public.settle_account(
  p_person_id    uuid,
  p_amount_minor bigint default null,
  p_date         date default current_date,
  p_note         text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner     uuid := public.assert_caller();
  v_bal       public.person_balances%rowtype;
  v_direction public.settlement_direction;
  v_max       bigint;
begin
  select * into v_bal
  from public.person_balances b
  where b.person_id = p_person_id and b.owner_id = v_owner;

  if not found then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  if v_bal.outstanding_receivable > 0 and v_bal.outstanding_payable > 0 then
    raise exception 'This account has both receivable and payable amounts. Choose which side to settle.'
      using errcode = 'check_violation';
  elsif v_bal.outstanding_receivable > 0 then
    v_direction := 'in';  v_max := v_bal.outstanding_receivable;
  elsif v_bal.outstanding_payable > 0 then
    v_direction := 'out'; v_max := v_bal.outstanding_payable;
  else
    raise exception 'Nothing outstanding to settle.' using errcode = 'check_violation';
  end if;

  return public.create_settlement(
    p_person_id      => p_person_id,
    p_amount_minor   => coalesce(p_amount_minor, v_max),
    p_direction      => v_direction,
    p_transaction_id => null,
    p_date           => p_date,
    p_note           => p_note
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------

grant execute on function public.create_person(
  text, public.party_type, text, text, text, text, text,
  text, bigint, date, bigint, text, bigint, timestamptz, text
) to authenticated;

grant execute on function public.update_person(
  uuid, text, public.party_type, text, text, text, text, text, boolean, bigint
) to authenticated;

grant execute on function public.set_person_opening_balance(
  uuid, text, bigint, date, bigint, text, bigint, timestamptz, text
) to authenticated;

grant execute on function public.create_transaction(
  uuid, public.txn_type, bigint, date, text, bigint, text, bigint, timestamptz, text
) to authenticated;

grant execute on function public.update_transaction(
  uuid, public.txn_type, bigint, date, text, bigint, text, bigint, timestamptz, text
) to authenticated;

grant execute on function public.create_settlement(
  uuid, bigint, public.settlement_direction, uuid, date, text,
  bigint, text, bigint, timestamptz, text
) to authenticated;

grant execute on function public.settle_account(uuid, bigint, date, text) to authenticated;

revoke all on function public.restate_person_currency(uuid, text, text, bigint) from public, anon;
grant execute on function public.restate_person_currency(uuid, text, text, bigint) to authenticated;
