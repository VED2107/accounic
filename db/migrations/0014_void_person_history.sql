-- =============================================================================
-- 0014 — Voiding a person's whole history in one call
--
-- The product already had a way to retract one entry (`void_transaction`,
-- `void_settlement`). What it had no way to do was start an account over: a
-- person whose ledger was entered wrong, or test rows recorded against a real
-- contact, had to be retracted one row at a time, and a directory of thirty
-- entries made that a chore nobody would finish.
--
-- This is a **void**, not a delete. Nothing leaves the database:
--
--   * every row keeps its amount, its date, its currency and its rate;
--   * `is_void` is set, which is the same flag the single-entry retraction
--     sets, so every view and every RPC already knows what to do with it;
--   * the balance engine stops counting the row (`person_balances`,
--     `owner_summary`, `dashboard()`), and the feed stops listing it
--     (`activity_page()`, `activity_summary()`, dashboard recent activity) —
--     all of those already filter on `not is_void`;
--   * the person's own timeline still shows it, marked voided, because that is
--     the audit trail and the whole reason this is not a delete.
--
-- Reversing one row is `void_transaction`'s existing story and is unchanged.
-- Reversing a bulk void is deliberately NOT offered: "unvoid everything" would
-- also resurrect rows the user had retracted individually and on purpose, which
-- is a different intent wearing the same button.
--
-- Additive and backwards compatible: one new function, no schema change, no
-- existing object altered.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- void_person_history(person, reason)
--
-- Voids every live transaction and settlement belonging to one person, in a
-- single transaction so the account can never be left half-retracted. Returns
-- the counts and the resulting balance, so the caller can say what it did
-- rather than guess.
--
-- `security invoker` and the `owner_id = v_owner` predicate: the same two
-- guards every other mutation uses. RLS applies on top. A caller can only ever
-- void their own rows, and passing someone else's person id touches nothing.
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
begin
  -- Resolve the person first, so a bad id is refused by name rather than
  -- silently voiding nothing and reporting success.
  select * into v_person
  from public.people
  where id = p_person_id and owner_id = v_owner;

  if not found then
    raise exception 'That person could not be found.'
      using errcode = 'no_data_found';
  end if;

  -- Settlements first. They reference transactions, and retracting the
  -- reference before the thing it points at keeps the intermediate state
  -- readable to anything inspecting the table mid-statement.
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
    'balance', (
      select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id
    )
  );
end;
$$;

grant execute on function public.void_person_history(uuid, text) to authenticated;

comment on function public.void_person_history(uuid, text) is
  'Retracts every live transaction and settlement for one person in a single '
  'transaction. Sets is_void; deletes nothing. The balance goes to zero and the '
  'entries leave the activity feed, while the person''s own timeline keeps '
  'showing them marked voided.';
