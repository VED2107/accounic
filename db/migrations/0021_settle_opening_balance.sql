-- =============================================================================
-- 0021 — an opening balance is settled on its own terms, not as a transaction
--
-- WHAT 0019 GOT HALF RIGHT
--
-- 0019 stopped an opening balance being settled through the ordinary
-- "Settle this" affordance, and it was right to: an opening balance is not a
-- credit or a debit, and offering the same row action on it said it was.
--
-- But it went one step too far. It refused *every* settlement that named an
-- opening balance, which left a real question with no answer: somebody pays off
-- what the account opened with, specifically, and the user has nowhere to
-- record it. Account-level settlement did retire it — by FIFO, along with
-- everything else — but that is a different statement of fact.
--
-- WHAT THIS ADDS
--
--   1. `settle_opening_balance()` — a dedicated RPC. It is the ONLY route by
--      which a settlement may name an opening balance, and it derives the
--      direction from the opening entry rather than accepting one, so the
--      caller cannot get it backwards.
--
--   2. `validate_settlement_row()` still refuses an opening balance to every
--      other caller. The permission is granted by a transaction-local flag that
--      only §1 sets, so `create_settlement()` — and any raw PostgREST client —
--      is refused exactly as it was.
--
--   3. `person_opening` gains `settled_minor`, `remaining_minor` and `status`,
--      so the opening section can show where its own settlement stands without
--      the screen recomputing anything.
--
-- The two sections now each have their own way of being settled, on one page:
--
--     Opening balance        Settle opening balance   → this entry only
--     Regular transactions   Settle / Settle this     → the account, or a row
--
-- Nothing about the balance engine changes. A settlement against an opening
-- balance is an ordinary settlement row and always was; what changes is which
-- callers may write one, and that the screen can see the result.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The permission flag
--
-- A transaction-local GUC rather than a column or an argument. It cannot be set
-- by a client — PostgREST has no way to send it — and it disappears at the end
-- of the statement's transaction, so the permission cannot leak into the next
-- request on a pooled connection.
--
-- It carries the person id rather than a bare boolean so that even inside the
-- one function that sets it, the exemption applies to the account being settled
-- and to no other.
-- -----------------------------------------------------------------------------

create or replace function public.opening_settlement_allowed(p_person_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(nullif(current_setting('accounic.settle_opening', true), ''), '')
         = p_person_id::text;
$$;

revoke all on function public.opening_settlement_allowed(uuid) from public, anon;
grant execute on function public.opening_settlement_allowed(uuid) to authenticated, service_role;

comment on function public.opening_settlement_allowed(uuid) is
  'True only inside settle_opening_balance() for the account it is settling. The one exemption to 0019''s rule (0021).';

-- -----------------------------------------------------------------------------
-- 2. The guard, narrowed
--
-- 0019's version with one clause changed: the refusal now yields to the flag.
-- Every other caller sees exactly the behaviour 0019 introduced, and
-- `db/tests/09` still asserts that create_settlement() is refused.
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

    -- An opening balance is settled through settle_opening_balance() and by no
    -- other route. INSERT only: voiding a settlement recorded by an older
    -- version of this product is an UPDATE, and must stay possible.
    if tg_op = 'INSERT'
       and v_txn.is_opening
       and not public.opening_settlement_allowed(new.person_id) then
      raise exception 'An opening balance is not a transaction that can be settled on its own.'
        using errcode = 'check_violation',
              hint    = 'Use the opening balance section''s own settle action, or settle the whole account.';
    end if;

    -- A transfer leg is one half of a movement between two accounts, not
    -- something the other party pays off.
    if tg_op = 'INSERT' and v_txn.transfer_id is not null then
      raise exception 'A transfer is not something that can be settled.'
        using errcode = 'check_violation',
              hint    = 'Retract the transfer instead, and both sides move together.';
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

-- -----------------------------------------------------------------------------
-- 3. settle_opening_balance()
--
-- The direction is derived, never accepted: an opening balance the person owes
-- is retired by money coming in, and one the user owes by money going out.
-- Getting that pair the wrong way round is the single mistake this function
-- exists to make impossible.
--
-- Everything else — the over-settlement ceiling, the conversion path, the
-- ledger denomination — is `create_settlement()`'s, unchanged. This adds a
-- permission and a derivation and no arithmetic of its own.
-- -----------------------------------------------------------------------------

create or replace function public.settle_opening_balance(
  p_person_id            uuid,
  p_amount_minor         bigint      default null,
  p_date                 date        default current_date,
  p_note                 text        default null,
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
  v_opening   public.transactions;
  v_direction public.settlement_direction;
  v_remaining bigint;
  v_result    jsonb;
begin
  select t.* into v_opening
  from public.transactions t
  where t.person_id = p_person_id
    and t.owner_id  = v_owner
    and t.is_opening
    and not t.is_void
  limit 1;

  if not found then
    raise exception 'This account has no opening balance to settle.'
      using errcode = 'no_data_found';
  end if;

  -- Derived from the entry, not from the caller.
  v_direction := case v_opening.type
                   when 'credit' then 'in'::public.settlement_direction
                   else 'out'::public.settlement_direction
                 end;

  select st.remaining_minor into v_remaining
  from public.transaction_settlement_status(p_person_id) st
  where st.transaction_id = v_opening.id;

  if coalesce(v_remaining, 0) <= 0 then
    raise exception 'This opening balance is already settled in full.'
      using errcode = 'check_violation';
  end if;

  -- Default to closing it, which is the common case.
  if coalesce(p_amount_minor, p_entered_amount_minor) is null then
    p_amount_minor := v_remaining;
  end if;

  -- The exemption, for this account and this statement only.
  perform set_config('accounic.settle_opening', p_person_id::text, true);

  v_result := public.create_settlement(
    p_person_id      => p_person_id,
    p_amount_minor   => p_amount_minor,
    p_direction      => v_direction,
    p_transaction_id => v_opening.id,
    p_date           => coalesce(p_date, current_date),
    p_note           => p_note,
    p_entered_amount_minor => p_entered_amount_minor,
    p_entered_currency     => p_entered_currency,
    p_exchange_rate_e9     => p_exchange_rate_e9,
    p_rate_at              => p_rate_at,
    p_rate_source          => p_rate_source,
    p_converted_amount_minor => p_converted_amount_minor,
    p_conversion_mode        => p_conversion_mode
  );

  -- Closed again immediately. The flag is transaction-local anyway, but a
  -- permission that outlives the one call it was granted for is a permission
  -- waiting to be misused by the next statement in the same transaction.
  perform set_config('accounic.settle_opening', '', true);

  return v_result;
end;
$$;

revoke all on function public.settle_opening_balance(
  uuid, bigint, date, text, bigint, text, bigint, timestamptz, text, bigint, text
) from public, anon;
grant execute on function public.settle_opening_balance(
  uuid, bigint, date, text, bigint, text, bigint, timestamptz, text, bigint, text
) to authenticated;

comment on function public.settle_opening_balance(
  uuid, bigint, date, text, bigint, text, bigint, timestamptz, text, bigint, text
) is
  'Settles a person''s opening balance, and only that. The direction is derived from the opening entry; the amount defaults to whatever is left of it. The one route by which a settlement may name an opening balance (0021).';

-- -----------------------------------------------------------------------------
-- 4. The opening section can see where its own settlement stands
--
-- 0020's view with three columns added, resolved by the same FIFO allocator
-- every other screen reads. Nothing here computes a remainder itself.
-- -----------------------------------------------------------------------------

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
  a.created_at,
  -- Where its own settlement stands. Same allocator, same numbers as every
  -- other row on the page.
  coalesce(st.settled_minor, 0)::bigint     as settled_minor,
  coalesce(st.remaining_minor, a.amount_minor)::bigint as remaining_minor,
  coalesce(st.status, 'open')               as status
from public.activity_entries a
left join lateral public.transaction_settlement_status(a.person_id) st
       on st.transaction_id = a.id
where a.entry_kind = 'transaction'
  and a.is_opening
  and not a.is_void;

comment on view public.person_opening is
  'One row per person that has an opening balance: the original figure, its currency, the base equivalent, the rate with its provenance, and how much of it has been settled (0019, extended 0021).';

grant select on public.person_opening to authenticated;
revoke all on public.person_opening from anon;
