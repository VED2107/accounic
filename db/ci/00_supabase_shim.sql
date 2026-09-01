-- =============================================================================
-- 00_supabase_shim.sql — the minimum of Supabase that the migrations depend on.
--
-- The migrations are written for a Supabase project, but they touch exactly
-- three things a plain PostgreSQL server does not have:
--
--   * the roles anon / authenticated / service_role, named by every grant
--   * auth.users, referenced by profiles.id and app_admins.user_id, and
--     written directly by every SQL test to create a workspace
--   * auth.uid(), which reads the JWT claims PostgREST puts on the session
--
-- This file supplies those and nothing else, so that `run-sql.mjs migrate` and
-- `run-sql.mjs test` run unchanged against a throwaway Postgres in CI. It is
-- NEVER applied to the live project: Supabase already owns all of it, and
-- these definitions are deliberately thinner than the real ones.
--
--   node db/tools/run-sql.mjs file db/ci/00_supabase_shim.sql
-- =============================================================================

-- --- roles -------------------------------------------------------------------
-- nologin: nothing signs in as these in CI. The tests reach them with
-- `set local role authenticated`, which needs membership, not a password.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

-- The session user must be able to become them, exactly as PostgREST's
-- authenticator role can on the real project.
do $$
begin
  execute format('grant anon, authenticated, service_role to %I', current_user);
end $$;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

-- --- auth.users --------------------------------------------------------------
-- Only the columns the migrations, the seed and the tests actually name. The
-- real table has ~35; the extra ones are GoTrue's business, not the ledger's.

create table if not exists auth.users (
  instance_id        uuid,
  id                 uuid primary key,
  aud                varchar(255),
  role               varchar(255),
  email              varchar(255) unique,
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  invited_at         timestamptz,
  confirmed_at       timestamptz,
  last_sign_in_at    timestamptz,
  raw_app_meta_data  jsonb default '{}'::jsonb,
  raw_user_meta_data jsonb default '{}'::jsonb,
  is_super_admin     boolean,
  created_at         timestamptz default now(),
  updated_at         timestamptz default now(),
  phone              text unique,
  banned_until       timestamptz,
  deleted_at         timestamptz
);

create table if not exists auth.identities (
  provider_id     text not null,
  user_id         uuid not null references auth.users (id) on delete cascade,
  identity_data   jsonb not null,
  provider        text not null,
  last_sign_in_at timestamptz,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now(),
  primary key (provider, provider_id)
);

-- --- auth.uid() and friends --------------------------------------------------
-- PostgREST sets request.jwt.claims per request; is_active_user() and every RLS
-- policy read auth.uid() out of it. Same contract here, same null-when-anonymous
-- behaviour — which is what makes the isolation tests meaningful in CI.

create or replace function auth.jwt()
returns jsonb
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  )
$$;

create or replace function auth.uid()
returns uuid
language sql stable
as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid
$$;

create or replace function auth.role()
returns text
language sql stable
as $$
  select nullif(auth.jwt() ->> 'role', '')
$$;

create or replace function auth.email()
returns text
language sql stable
as $$
  select nullif(auth.jwt() ->> 'email', '')
$$;

grant execute on function auth.jwt(), auth.uid(), auth.role(), auth.email()
  to anon, authenticated, service_role;

-- The auth-user provisioning trigger in 0001 is SECURITY DEFINER with an empty
-- search_path, so it names public.profiles explicitly and needs nothing here.
-- Reading auth.users during a test does need the grant, though.
grant select on auth.users, auth.identities to authenticated, service_role;

do $$
begin
  raise notice 'ok   supabase shim applied (roles, auth.users, auth.uid)';
end $$;
