-- =============================================================================
-- 0016 — close the anonymous execute surface
--
-- THE BUG
--
-- Every migration that defines a function follows it with
--
--   revoke all on function … from public;
--   grant execute on function … to authenticated, service_role;
--
-- which reads as "nobody but a signed-in user may call this". On Supabase it
-- does not mean that. A Supabase project ships
--
--   alter default privileges in schema public
--     grant all on functions to postgres, anon, authenticated, service_role;
--
-- so every function created in `public` is born with an EXPLICIT grant to
-- `anon`. `revoke … from public` removes the implicit PUBLIC grant and leaves
-- that explicit one untouched. The result: `anon` — the role behind the
-- publishable API key, which is in every shipped binary and every browser —
-- could execute essentially every function in this schema.
--
-- Most of them were saved by an assertion in the body: `assert_caller()` and
-- `current_owner()` raise when `auth.uid()` is null, which is why an anonymous
-- `dashboard()` or `create_transaction()` was refused. That is one layer, and
-- it only protects functions that remembered to check.
--
-- Three did not check, because they were believed unreachable:
--
--   owner_rate_e9(uuid, text, text)          → another workspace's cached rates
--   convert_for_owner(uuid, bigint, …)       → the same rates, one step removed
--   owner_base_currency(uuid)                → another workspace's base currency
--
-- All three are SECURITY DEFINER and read tenant tables, so RLS does not apply
-- to them. Verified against the live project before this migration: an
-- unauthenticated caller holding only the publishable key and a workspace UUID
-- read that workspace's AED→INR rate. Low-value data and a UUID has to be known
-- or guessed, but it is a cross-tenant read by an unauthenticated caller, and
-- the same mistake on a function that returned rows would have been severe.
--
-- THE FIX, in two layers
--
--   1. Revoke EXECUTE from `anon` (and PUBLIC) on every function this project
--      defines in `public`, and reset the default privilege that recreates the
--      problem for future functions. `authenticated` and `service_role` keep
--      exactly what they had, so no client behaviour changes.
--
--   2. Give the three unguarded helpers the check they never had: the caller
--      must be signed in, and may only ask about their OWN workspace. That
--      closes the IDOR independently of who can reach the function, which is
--      the layer that survives someone re-granting execute by accident.
--
-- Nothing anonymous is needed in this schema: sign-in is GoTrue in the `auth`
-- schema, and no client calls a `public` function before it has a session.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Stop minting the grant
--
-- Both spellings, because the default may be recorded against the role that
-- owns the migration connection or against `postgres`.
-- -----------------------------------------------------------------------------

alter default privileges in schema public revoke execute on functions from anon;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon;

-- -----------------------------------------------------------------------------
-- 2. Take back what was already granted
--
-- Extension-owned functions (citext, pg_trgm) are skipped: they are not ours to
-- re-privilege, they read no application data, and revoking them buys nothing.
-- -----------------------------------------------------------------------------

do $$
declare
  r record;
  v_count int := 0;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and not exists (
        select 1 from pg_depend d
        where d.objid = p.oid and d.deptype = 'e'      -- extension member
      )
  loop
    execute format('revoke all on function %s from anon', r.sig);
    execute format('revoke all on function %s from public', r.sig);
    v_count := v_count + 1;
  end loop;
  raise notice 'revoked execute from anon on % functions', v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. The three helpers get the check they never had
--
-- Each now refuses an unauthenticated caller outright, and refuses to answer
-- about a workspace that is not the caller's. `service_role` is exempt, the
-- same way public.guard_profile_self_update() exempts it (0005): it bypasses
-- RLS by design and is the administrative path.
--
-- The application's own callers are unaffected. Both views that use these pass
-- `pb.owner_id` / `p.owner_id` from rows RLS has already confined to the
-- caller, so the assertion is true wherever the product actually calls them.
-- -----------------------------------------------------------------------------

create or replace function public.assert_own_workspace(p_owner uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- What identifies a remote request is the JWT claims PostgREST sets on the
  -- connection, NOT the role. Two earlier attempts got this wrong and are worth
  -- recording, because both failed OPEN:
  --
  --   * `is_superuser` — Supabase's `postgres` role reports `off`, so this
  --     exempted nobody and broke the migration runner instead.
  --   * `current_user not in ('anon','authenticated')` — inside a SECURITY
  --     DEFINER function current_user is the function OWNER, so this exempted
  --     every caller including `anon`. The guard was inert.
  --
  -- Claims are set for every PostgREST request, including an anonymous one
  -- (the publishable key is itself a JWT carrying role=anon), and are absent on
  -- a direct SQL connection — the migration runner, the test suites,
  -- db/tools/snapshot.mjs. `service_role` is exempt explicitly: it bypasses RLS
  -- by design and is the administrative path.
  if current_setting('role', true) = 'service_role' then
    return;
  end if;

  if coalesce(current_setting('request.jwt.claims', true), '') = '' then
    return;   -- direct SQL connection, already privileged
  end if;

  -- From here on this is a remote caller and must prove who it is.

  if auth.uid() is null then
    raise exception 'Not authorised.' using errcode = 'insufficient_privilege';
  end if;

  -- A null argument is not a licence to read everyone's; it is a bad call.
  if p_owner is null or p_owner is distinct from public.current_owner() then
    raise exception 'Not authorised.' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

comment on function public.assert_own_workspace(uuid) is
  'Refuses a caller who is not signed in, or who is asking about a workspace that is not theirs. For SECURITY DEFINER helpers that take an owner id and therefore escape RLS (0016).';

create or replace function public.owner_rate_e9(
  p_owner uuid,
  p_from  text,
  p_to    text
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.assert_own_workspace(p_owner);

  return (
    select case
      when p_from is null or p_to is null then null
      when upper(p_from) = upper(p_to) then 1000000000::bigint
      else coalesce(
        (select r.rate_e9
           from public.exchange_rates r
          where r.owner_id = p_owner and r.base = upper(p_from) and r.quote = upper(p_to)),
        (select round(1000000000000000000::numeric / r.rate_e9)::bigint
           from public.exchange_rates r
          where r.owner_id = p_owner and r.base = upper(p_to) and r.quote = upper(p_from))
      )
    end
  );
end;
$$;

create or replace function public.convert_for_owner(
  p_owner        uuid,
  p_amount_minor bigint,
  p_from         text,
  p_to           text
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.assert_own_workspace(p_owner);

  return public.convert_amount_minor(
    p_amount_minor, p_from, p_to, public.owner_rate_e9(p_owner, p_from, p_to)
  );
end;
$$;

create or replace function public.owner_base_currency(p_owner uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform public.assert_own_workspace(p_owner);

  return coalesce(
    (select p.currency from public.profiles p where p.id = p_owner),
    'INR'
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Re-grant, to signed-in users only
--
-- Step 2 revoked from anon and PUBLIC; `authenticated` and `service_role` kept
-- their grants. These three were replaced above, so they are re-granted
-- explicitly, and the new helper is granted for the first time.
-- -----------------------------------------------------------------------------

revoke all on function public.assert_own_workspace(uuid)                     from public, anon;
revoke all on function public.owner_rate_e9(uuid, text, text)                from public, anon;
revoke all on function public.convert_for_owner(uuid, bigint, text, text)    from public, anon;
revoke all on function public.owner_base_currency(uuid)                      from public, anon;

grant execute on function public.assert_own_workspace(uuid)                  to authenticated, service_role;
grant execute on function public.owner_rate_e9(uuid, text, text)             to authenticated, service_role;
grant execute on function public.convert_for_owner(uuid, bigint, text, text) to authenticated, service_role;
grant execute on function public.owner_base_currency(uuid)                   to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5. Least privilege on the read-only views
--
-- `authenticated` held INSERT/UPDATE/DELETE/TRUNCATE on all three engine views.
-- None is auto-updatable — they carry unions, aggregates and lateral joins — so
-- nothing could actually be written through them, but a write grant that only
-- fails by accident is not a control. Reads are what they are for.
-- -----------------------------------------------------------------------------

revoke insert, update, delete, truncate, references
  on public.person_balances, public.owner_summary, public.activity_feed
  from authenticated;

grant select on public.person_balances, public.owner_summary, public.activity_feed
  to authenticated;
