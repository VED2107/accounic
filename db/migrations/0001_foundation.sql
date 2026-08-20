-- =============================================================================
-- 0001_foundation.sql
-- Extensions, enums, profiles, admin registry, helper predicates.
--
-- Design notes (context.md §2, §3, §4, §24):
--   * Every user-owned row carries owner_id = auth.users.id.
--   * profiles.id IS the auth user id (1:1), so owner_id joins stay trivial.
--   * Admin membership lives in its own table (app_admins) with NO client-facing
--     write policy. A normal user therefore cannot escalate by editing a column
--     on a row they own. Admin membership is granted only by the service role.
--   * is_active gates data access at the database layer, so disabling a user
--     revokes their data even while an issued JWT is still technically valid.
-- =============================================================================

create extension if not exists "pgcrypto";
create extension if not exists "citext";

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------

do $$ begin
  create type public.party_type as enum ('person', 'business');
exception when duplicate_object then null; end $$;

do $$ begin
  -- credit = the other party owes the user   (receivable)
  -- debit  = the user owes the other party   (payable)
  create type public.txn_type as enum ('credit', 'debit');
exception when duplicate_object then null; end $$;

do $$ begin
  -- in  = money received by the user  -> reduces receivable
  -- out = money paid by the user      -> reduces payable
  create type public.settlement_direction as enum ('in', 'out');
exception when duplicate_object then null; end $$;

-- -----------------------------------------------------------------------------
-- profiles (context.md §4)
-- -----------------------------------------------------------------------------

create table if not exists public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  name          text        not null default '',
  email         citext      not null,
  phone         text,
  business_name text,
  avatar_url    text,
  currency      text        not null default 'INR',
  is_active     boolean     not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint profiles_name_len     check (char_length(name) <= 120),
  constraint profiles_phone_len    check (phone is null or char_length(phone) between 3 and 32),
  constraint profiles_business_len check (business_name is null or char_length(business_name) <= 120),
  constraint profiles_currency_fmt check (currency ~ '^[A-Z]{3}$')
);

comment on table public.profiles is
  'One row per authenticated user. id mirrors auth.users.id. Owns an isolated accounting workspace.';

-- -----------------------------------------------------------------------------
-- app_admins (context.md §24, §25)
-- Deliberately separate from profiles: no client role may write to it.
-- -----------------------------------------------------------------------------

create table if not exists public.app_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users (id) on delete set null
);

comment on table public.app_admins is
  'Admin registry. Writable only by the service role (no RLS policy grants write to authenticated).';

-- -----------------------------------------------------------------------------
-- Helper predicates
--
-- security definer + empty search_path so they cannot be shadowed and can read
-- the admin registry regardless of the caller''s own RLS view of it.
-- -----------------------------------------------------------------------------

create or replace function public.is_admin(uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.app_admins a where a.user_id = uid);
$$;

create or replace function public.is_active_user(uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select p.is_active from public.profiles p where p.id = uid), false);
$$;

-- current_owner(): the workspace the caller may touch.
-- Returns null when the caller is anonymous or deactivated, which makes every
-- RLS predicate below evaluate to false rather than accidentally true.
create or replace function public.current_owner()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case
           when auth.uid() is null then null
           when public.is_active_user(auth.uid()) then auth.uid()
           else null
         end;
$$;

revoke all on function public.is_admin(uuid)       from public;
revoke all on function public.is_active_user(uuid) from public;
revoke all on function public.current_owner()      from public;
grant execute on function public.is_admin(uuid)       to authenticated, service_role;
grant execute on function public.is_active_user(uuid) to authenticated, service_role;
grant execute on function public.current_owner()      to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- updated_at maintenance
-- -----------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Provision a profile whenever an auth user is created.
-- The admin API passes name/phone/business_name/currency through user_metadata.
-- -----------------------------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, name, phone, business_name, currency)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(new.email, '@', 1)),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    nullif(new.raw_user_meta_data ->> 'business_name', ''),
    coalesce(nullif(upper(new.raw_user_meta_data ->> 'currency'), ''), 'INR')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- Keep profiles.email in step with auth.users.email after an admin email change.
create or replace function public.handle_auth_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.email is distinct from old.email then
    update public.profiles set email = new.email where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.handle_auth_user_email_change();
