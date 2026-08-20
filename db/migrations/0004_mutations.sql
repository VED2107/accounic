-- =============================================================================
-- 0004_mutations.sql
-- Write RPCs. Every client (web, Android, desktop) mutates through these, so
-- validation and the returned post-state are identical everywhere
-- (context.md §12, §21).
--
-- Each function runs inside the implicit statement transaction, so a failed
-- constraint rolls the whole operation back: "your balance has not been
-- changed" is literally true (context.md §26).
--
-- All are SECURITY INVOKER: RLS still applies. owner_id is stamped from
-- current_owner() and never accepted from the client.
-- =============================================================================

create or replace function public.assert_caller()
returns uuid
language plpgsql
stable
as $$
declare
  v_owner uuid := public.current_owner();
begin
  if v_owner is null then
    raise exception 'Your session is not valid or your account is disabled.'
      using errcode = 'insufficient_privilege';
  end if;
  return v_owner;
end;
$$;

grant execute on function public.assert_caller() to authenticated;

-- -----------------------------------------------------------------------------
-- People
-- -----------------------------------------------------------------------------

create or replace function public.create_person(
  p_name    text,
  p_type    public.party_type default 'person',
  p_phone   text default null,
  p_email   text default null,
  p_address text default null,
  p_notes   text default null
)
returns public.people
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_row   public.people;
begin
  if btrim(coalesce(p_name, '')) = '' then
    raise exception 'Name is required.' using errcode = 'check_violation';
  end if;

  insert into public.people (owner_id, name, type, phone, email, address, notes)
  values (
    v_owner,
    btrim(p_name),
    coalesce(p_type, 'person'),
    nullif(btrim(coalesce(p_phone, '')), ''),
    nullif(btrim(coalesce(p_email, '')), ''),
    nullif(btrim(coalesce(p_address, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), '')
  )
  returning * into v_row;

  return v_row;
end;
$$;

create or replace function public.update_person(
  p_person_id uuid,
  p_name      text,
  p_type      public.party_type,
  p_phone     text default null,
  p_email     text default null,
  p_address   text default null,
  p_notes     text default null
)
returns public.people
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_row   public.people;
begin
  if btrim(coalesce(p_name, '')) = '' then
    raise exception 'Name is required.' using errcode = 'check_violation';
  end if;

  update public.people set
    name    = btrim(p_name),
    type    = coalesce(p_type, type),
    phone   = nullif(btrim(coalesce(p_phone, '')), ''),
    email   = nullif(btrim(coalesce(p_email, '')), ''),
    address = nullif(btrim(coalesce(p_address, '')), ''),
    notes   = nullif(btrim(coalesce(p_notes, '')), '')
  where id = p_person_id and owner_id = v_owner
  returning * into v_row;

  if not found then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;
  return v_row;
end;
$$;

create or replace function public.set_person_archived(p_person_id uuid, p_archived boolean)
returns public.people
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_row   public.people;
begin
  update public.people set is_archived = coalesce(p_archived, true)
  where id = p_person_id and owner_id = v_owner
  returning * into v_row;

  if not found then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;
  return v_row;
end;
$$;

-- Hard delete is allowed only while the person has no financial history
-- (context.md §17: prefer archive; never corrupt history).
create or replace function public.delete_person(p_person_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_txns  int;
begin
  select count(*) into v_txns
  from public.transactions t where t.person_id = p_person_id and t.owner_id = v_owner;

  if v_txns > 0 then
    raise exception 'This person has transactions and cannot be deleted. Archive them instead.'
      using errcode = 'check_violation';
  end if;

  delete from public.people where id = p_person_id and owner_id = v_owner;
  if not found then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Transactions
--
-- Returns the transaction plus the person's refreshed balance so an optimistic
-- client can reconcile in the same round trip (context.md §14, §23).
-- -----------------------------------------------------------------------------

create or replace function public.create_transaction(
  p_person_id    uuid,
  p_type         public.txn_type,
  p_amount_minor bigint,
  p_date         date default current_date,
  p_description  text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_row   public.transactions;
begin
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Amount must be greater than zero.' using errcode = 'check_violation';
  end if;
  if p_date > current_date + interval '1 day' then
    raise exception 'Transaction date cannot be in the future.' using errcode = 'check_violation';
  end if;

  insert into public.transactions
    (owner_id, person_id, type, amount_minor, transaction_date, description, created_by)
  values
    (v_owner, p_person_id, p_type, p_amount_minor, coalesce(p_date, current_date),
     nullif(btrim(coalesce(p_description, '')), ''), auth.uid())
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
  p_amount_minor   bigint,
  p_date           date,
  p_description    text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_row   public.transactions;
begin
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Amount must be greater than zero.' using errcode = 'check_violation';
  end if;

  update public.transactions set
    type             = coalesce(p_type, type),
    amount_minor     = p_amount_minor,
    transaction_date = coalesce(p_date, transaction_date),
    description      = nullif(btrim(coalesce(p_description, '')), '')
  where id = p_transaction_id and owner_id = v_owner and not is_void
  returning * into v_row;

  if not found then
    raise exception 'Transaction not found, or it has been voided.'
      using errcode = 'no_data_found';
  end if;

  -- If this edit strands existing settlements, the deferred constraint trigger
  -- from 0002 aborts the whole statement here.
  return jsonb_build_object(
    'transaction', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = v_row.person_id)
  );
end;
$$;

-- Voiding is the safe alternative to deletion (context.md §17).
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

-- -----------------------------------------------------------------------------
-- Settlements (context.md §9)
--
-- p_direction may be omitted when p_transaction_id is supplied: it is then
-- derived from the transaction's type, which removes a whole class of
-- client-side mistakes.
-- -----------------------------------------------------------------------------

create or replace function public.create_settlement(
  p_person_id      uuid,
  p_amount_minor   bigint,
  p_direction      public.settlement_direction default null,
  p_transaction_id uuid default null,
  p_date           date default current_date,
  p_note           text default null
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
  v_remaining bigint;
  v_row       public.settlements;
begin
  if p_amount_minor is null or p_amount_minor <= 0 then
    raise exception 'Settlement amount must be greater than zero.'
      using errcode = 'check_violation';
  end if;

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

  -- Friendly pre-check. The deferred constraint trigger is still the real
  -- guarantee; this exists so the user gets a useful number in the message.
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

  if p_amount_minor > v_remaining then
    raise exception 'Settlement of % exceeds the outstanding amount of %.',
      p_amount_minor, v_remaining
      using errcode = 'check_violation';
  end if;

  insert into public.settlements
    (owner_id, person_id, transaction_id, direction, amount_minor, settlement_date, note, created_by)
  values
    (v_owner, p_person_id, p_transaction_id, v_direction, p_amount_minor,
     coalesce(p_date, current_date), nullif(btrim(coalesce(p_note, '')), ''), auth.uid())
  returning * into v_row;

  return jsonb_build_object(
    'settlement', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
  );
end;
$$;

create or replace function public.void_settlement(p_settlement_id uuid, p_reason text default null)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_row   public.settlements;
begin
  update public.settlements set
    is_void     = true,
    void_reason = nullif(btrim(coalesce(p_reason, '')), '')
  where id = p_settlement_id and owner_id = v_owner and not is_void
  returning * into v_row;

  if not found then
    raise exception 'Settlement not found, or it is already voided.'
      using errcode = 'no_data_found';
  end if;

  return jsonb_build_object(
    'settlement', to_jsonb(v_row),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = v_row.person_id)
  );
end;
$$;

-- Settle an entire person account in one call: the net position decides the
-- direction, so the UI can offer a single prominent Settle button (context.md §9).
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
    -- Ambiguous: the caller must say which side they are settling.
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
    p_person_id    => p_person_id,
    p_amount_minor => coalesce(p_amount_minor, v_max),
    p_direction    => v_direction,
    p_transaction_id => null,
    p_date         => p_date,
    p_note         => p_note
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Profile (context.md §4)
-- -----------------------------------------------------------------------------

create or replace function public.update_my_profile(
  p_name          text,
  p_phone         text default null,
  p_business_name text default null,
  p_currency      text default null,
  p_avatar_url    text default null
)
returns public.profiles
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_row   public.profiles;
begin
  update public.profiles set
    name          = coalesce(nullif(btrim(coalesce(p_name, '')), ''), name),
    phone         = nullif(btrim(coalesce(p_phone, '')), ''),
    business_name = nullif(btrim(coalesce(p_business_name, '')), ''),
    currency      = coalesce(nullif(upper(btrim(coalesce(p_currency, ''))), ''), currency),
    avatar_url    = nullif(btrim(coalesce(p_avatar_url, '')), '')
  where id = v_owner
  returning * into v_row;

  return v_row;
end;
$$;

-- -----------------------------------------------------------------------------
-- Person page payload in one round trip (context.md §6, §16, §23).
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
    'timeline', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.entry_kind, a.entry_type, a.money_direction, a.amount_minor,
               a.entry_date, a.note, a.is_void, a.related_transaction_id, a.created_at,
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
               t.created_at, st.remaining_minor, st.settled_minor
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

grant execute on function public.create_person(text, public.party_type, text, text, text, text) to authenticated;
grant execute on function public.update_person(uuid, text, public.party_type, text, text, text, text) to authenticated;
grant execute on function public.set_person_archived(uuid, boolean) to authenticated;
grant execute on function public.delete_person(uuid) to authenticated;
grant execute on function public.create_transaction(uuid, public.txn_type, bigint, date, text) to authenticated;
grant execute on function public.update_transaction(uuid, public.txn_type, bigint, date, text) to authenticated;
grant execute on function public.void_transaction(uuid, text) to authenticated;
grant execute on function public.create_settlement(uuid, bigint, public.settlement_direction, uuid, date, text) to authenticated;
grant execute on function public.void_settlement(uuid, text) to authenticated;
grant execute on function public.settle_account(uuid, bigint, date, text) to authenticated;
grant execute on function public.update_my_profile(text, text, text, text, text) to authenticated;
grant execute on function public.person_page(uuid, int, int) to authenticated;
