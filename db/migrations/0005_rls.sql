-- =============================================================================
-- 0005_rls.sql
-- Row Level Security (context.md §3, §24).
--
-- The contract: even with a valid anon key and a raw HTTP client, a user can
-- only ever reach rows whose owner_id equals their own active user id.
-- Nothing here depends on the frontend filtering anything.
--
-- Admins deliberately get NO read policy on ledger data. Administration is user
-- management, not access to other people's books (context.md §25).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Baseline grants. anon gets nothing at all.
-- -----------------------------------------------------------------------------

revoke all on public.profiles    from anon, authenticated;
revoke all on public.people      from anon, authenticated;
revoke all on public.transactions from anon, authenticated;
revoke all on public.settlements from anon, authenticated;
revoke all on public.app_admins  from anon, authenticated;

grant select, update            on public.profiles     to authenticated;
grant select, insert, update, delete on public.people       to authenticated;
grant select, insert, update    on public.transactions to authenticated;
grant select, insert, update    on public.settlements  to authenticated;
grant select                    on public.person_balances, public.owner_summary,
                                   public.activity_feed to authenticated;

-- Deleting financial history is not an operation the API exposes at all
-- (context.md §17). Void is the supported path.

alter table public.profiles     enable row level security;
alter table public.people       enable row level security;
alter table public.transactions enable row level security;
alter table public.settlements  enable row level security;
alter table public.app_admins   enable row level security;

alter table public.profiles     force row level security;
alter table public.people       force row level security;
alter table public.transactions force row level security;
alter table public.settlements  force row level security;
alter table public.app_admins   force row level security;

-- -----------------------------------------------------------------------------
-- profiles
-- -----------------------------------------------------------------------------

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = auth.uid());

-- A deactivated user cannot edit their way back in: current_owner() is null
-- for them, so the predicate fails.
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = public.current_owner())
  with check (id = public.current_owner());

-- is_active is administrative state. Block self-service changes to it.
create or replace function public.guard_profile_self_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The service role bypasses RLS and is the admin path; it is exempt.
  if current_setting('role', true) = 'service_role' or auth.uid() is null then
    return new;
  end if;
  -- Administrators reach this through admin_set_user_active(), which does its
  -- own is_admin() check and refuses self-disable. Ordinary users cannot flip
  -- their own status by any route: RLS confines their UPDATE to their own row,
  -- and this rejects the one column that matters.
  if new.is_active is distinct from old.is_active and not public.is_admin() then
    raise exception 'Account status can only be changed by an administrator.'
      using errcode = 'insufficient_privilege';
  end if;
  if new.id is distinct from old.id or new.email is distinct from old.email then
    raise exception 'Identity fields cannot be changed here.'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_self_update on public.profiles;
create trigger profiles_guard_self_update
  before update on public.profiles
  for each row execute function public.guard_profile_self_update();

-- -----------------------------------------------------------------------------
-- app_admins
-- Readable only by the admin themselves (so the UI can show the admin nav).
-- No insert/update/delete policy exists, so authenticated can never write here
-- regardless of what the client sends (context.md §24).
-- -----------------------------------------------------------------------------

drop policy if exists app_admins_select_self on public.app_admins;
create policy app_admins_select_self on public.app_admins
  for select to authenticated
  using (user_id = auth.uid());

grant select on public.app_admins to authenticated;

-- -----------------------------------------------------------------------------
-- people
-- -----------------------------------------------------------------------------

drop policy if exists people_select_own on public.people;
create policy people_select_own on public.people
  for select to authenticated
  using (owner_id = public.current_owner());

drop policy if exists people_insert_own on public.people;
create policy people_insert_own on public.people
  for insert to authenticated
  with check (owner_id = public.current_owner());

drop policy if exists people_update_own on public.people;
create policy people_update_own on public.people
  for update to authenticated
  using (owner_id = public.current_owner())
  with check (owner_id = public.current_owner());

drop policy if exists people_delete_own on public.people;
create policy people_delete_own on public.people
  for delete to authenticated
  using (owner_id = public.current_owner());

-- -----------------------------------------------------------------------------
-- transactions
--
-- The WITH CHECK clause re-verifies that the referenced person is also owned by
-- the caller. The composite FK already guarantees it structurally; this makes
-- the intent explicit at the policy layer and fails earlier with a clearer
-- authorisation error.
-- -----------------------------------------------------------------------------

drop policy if exists transactions_select_own on public.transactions;
create policy transactions_select_own on public.transactions
  for select to authenticated
  using (owner_id = public.current_owner());

drop policy if exists transactions_insert_own on public.transactions;
create policy transactions_insert_own on public.transactions
  for insert to authenticated
  with check (
    owner_id = public.current_owner()
    and exists (
      select 1 from public.people p
      where p.id = person_id and p.owner_id = public.current_owner()
    )
  );

drop policy if exists transactions_update_own on public.transactions;
create policy transactions_update_own on public.transactions
  for update to authenticated
  using (owner_id = public.current_owner())
  with check (
    owner_id = public.current_owner()
    and exists (
      select 1 from public.people p
      where p.id = person_id and p.owner_id = public.current_owner()
    )
  );

-- -----------------------------------------------------------------------------
-- settlements
-- -----------------------------------------------------------------------------

drop policy if exists settlements_select_own on public.settlements;
create policy settlements_select_own on public.settlements
  for select to authenticated
  using (owner_id = public.current_owner());

drop policy if exists settlements_insert_own on public.settlements;
create policy settlements_insert_own on public.settlements
  for insert to authenticated
  with check (
    owner_id = public.current_owner()
    and exists (
      select 1 from public.people p
      where p.id = person_id and p.owner_id = public.current_owner()
    )
    and (
      transaction_id is null
      or exists (
        select 1 from public.transactions t
        where t.id = transaction_id and t.owner_id = public.current_owner()
      )
    )
  );

drop policy if exists settlements_update_own on public.settlements;
create policy settlements_update_own on public.settlements
  for update to authenticated
  using (owner_id = public.current_owner())
  with check (owner_id = public.current_owner());

-- -----------------------------------------------------------------------------
-- Immutability of the audit trail: once written, owner_id and person_id of a
-- financial row can never be re-pointed (context.md §24 audit-friendly).
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
  return new;
end;
$$;

drop trigger if exists transactions_immutable_keys on public.transactions;
create trigger transactions_immutable_keys
  before update on public.transactions
  for each row execute function public.guard_ledger_immutable_keys();

drop trigger if exists settlements_immutable_keys on public.settlements;
create trigger settlements_immutable_keys
  before update on public.settlements
  for each row execute function public.guard_ledger_immutable_keys();
