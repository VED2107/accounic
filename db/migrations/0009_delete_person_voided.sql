-- ============================================================================
-- 0009 — deleting a person whose history was all retracted
--
-- The bug this fixes was a disagreement between two definitions of "has
-- transactions".
--
-- `person_balances.transaction_count` counts only rows that are **not void**,
-- because every figure in that view treats a voided row as something that did
-- not happen. Both clients read that column to decide whether to offer Delete.
--
-- `delete_person()` counted **every** row, void or not. So a person whose only
-- transactions had been voided reported zero transactions, a zero balance and
-- "Everything is settled" — and then refused to be deleted, saying they had
-- transactions. The action was offered and then refused, which is the one
-- outcome the person menu is designed never to produce.
--
-- They now agree. A voided transaction is a retraction: it contributes to no
-- balance, appears in no total, and is excluded from the activity feed. A
-- person holding nothing but retractions has no financial position, and
-- deleting them removes a self-contained set of rows — nothing survives to be
-- left inconsistent, which is what `context.md`'s "must not corrupt historical
-- records" is protecting.
--
-- Live records still block deletion, and that is unchanged: a single non-void
-- transaction or settlement means Archive is the only option.
--
-- Settlements are checked too. A settlement can outlive the transaction it
-- paid — voiding a transaction does not void the settlement against it — so a
-- person can reach zero non-void transactions while a real payment is still on
-- record. That is financial history and it blocks the delete.
-- ============================================================================

-- SECURITY DEFINER, where the previous definition was INVOKER.
--
-- `authenticated` is granted select/insert/update on transactions and
-- settlements and deliberately **not** delete (0005_rls.sql): no client may
-- ever hard-delete a ledger row directly. Removing the retracted rows therefore
-- cannot be done as the caller, and widening that grant to let it would hand
-- every client a raw DELETE on the whole ledger through PostgREST.
--
-- So this one function does it instead, and being DEFINER it bypasses RLS —
-- which means the `owner_id = v_owner` on every statement below is the only
-- thing standing between callers, and is not optional. `v_owner` comes from
-- assert_caller(), which reads the caller's JWT and cannot be influenced by an
-- argument.
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

  -- Both foreign keys onto people are ON DELETE RESTRICT, so the retracted
  -- rows have to go first and in this order: settlements reference
  -- transactions, not the other way round.
  delete from public.settlements
  where person_id = p_person_id and owner_id = v_owner;

  delete from public.transactions
  where person_id = p_person_id and owner_id = v_owner;

  delete from public.people
  where id = p_person_id and owner_id = v_owner;

  if not found then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;
end;
$$;

comment on function public.delete_person(uuid) is
  'Hard delete, allowed only when nothing live remains. Voided transactions and '
  'settlements are removed with the person; a single non-void row of either kind '
  'blocks the delete in favour of archiving.';

-- 0005_rls.sql granted execute on the previous definition; CREATE OR REPLACE
-- keeps the existing grants, but state them again so this file is standalone.
revoke all on function public.delete_person(uuid) from public, anon;
grant execute on function public.delete_person(uuid) to authenticated, service_role;
