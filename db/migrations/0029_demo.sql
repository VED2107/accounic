-- =============================================================================
-- 0029_demo.sql
-- The online demo: a seeded sample workspace, and a way to put it back.
--
-- MUST BE FOLLOWED BY 0030_demo_users.sql (docs/demo.md).
--
-- This file was written when the demo was going to live in a Supabase project
-- of its own. It does not any more: there is ONE Accounic database, and a demo
-- account is an ordinary account in it carrying a flag. 0030 supersedes this
-- file's copies of handle_new_auth_user() and is_demo_visitor() and moves the
-- flag into profiles.is_demo. What survives here unchanged is demo_seed() and
-- demo_reset(), which are the parts that matter -- and both are safe in the
-- real project, because both refuse any caller who is not a demo one.
--
-- Apply 0029 and 0030 together, in that order. 0029 on its own leaves the flag
-- somewhere an administrator cannot see it.
--
-- Nothing here computes a balance, allocates a settlement, or decides what a
-- credit means. It calls create_person(), create_transaction() and
-- create_settlement() -- the same SECURITY INVOKER RPCs every client calls --
-- so the demo's sample data is written BY the accounting engine rather than
-- alongside it. If the engine's rules change, the demo's figures change with
-- them, because there is no second copy of those rules to fall out of step.
--
-- Two safety properties, both enforced here rather than in the client:
--
--   * Every function below refuses a caller who is not a demo one -- either an
--     ANONYMOUS auth user, or the shared demo account flagged in APP metadata,
--     which only the service role can write. A production user is neither. So
--     even if this file were applied to the production project by mistake,
--     demo_reset() could not delete a paying user's ledger -- it would raise.
--
--   * Everything runs as the caller. RLS therefore confines a visitor to the
--     workspace anonymous sign-in gave them, exactly as it confines a real
--     user to theirs. One visitor cannot read, seed or reset another's.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Anonymous sign-in has to be able to provision a profile.
--
-- profiles.email is NOT NULL and auth.users.email is NULL for an anonymous
-- user, so the trigger from 0001 raises and the sign-in fails with a message
-- about the database. This is the same function with one coalesce added; the
-- named-user path through it is unchanged, which is why the whole body is
-- restated rather than a second trigger added beside it.
--
-- The synthetic address uses .invalid, which RFC 2606 reserves precisely so it
-- can never resolve or be delivered to.
-- -----------------------------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := coalesce(new.email, new.id::text || '@anonymous.invalid');
begin
  insert into public.profiles (id, email, name, phone, business_name, currency)
  values (
    new.id,
    v_email,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(v_email, '@', 1)),
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    nullif(new.raw_user_meta_data ->> 'business_name', ''),
    coalesce(nullif(upper(new.raw_user_meta_data ->> 'currency'), ''), 'INR')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. Who is allowed to be seeded and reset.
--
-- Two kinds of demo caller, and they exist for two different audiences:
--
--   * An ANONYMOUS user. The hosted demo signs each visitor in this way, so
--     every visitor gets a private workspace and no two of them can see or
--     spoil each other's books.
--
--   * A user carrying `is_demo` in their APP metadata. This is the shared
--     account whose email and password can be handed out -- in a deck, on a
--     landing page, to a customer who wants to look again tomorrow. App
--     metadata is writable only with the service role, so a user cannot promote
--     themselves into this by editing their own profile, and no production user
--     has ever had the key set.
--
-- SECURITY DEFINER because auth.users is not readable by `authenticated`, and
-- STABLE because the answer cannot change inside a statement.
-- -----------------------------------------------------------------------------

create or replace function public.is_demo_visitor()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select u.is_anonymous
             or coalesce((u.raw_app_meta_data ->> 'is_demo')::boolean, false)
      from auth.users u
      where u.id = auth.uid()
    ),
    false
  );
$$;

revoke all on function public.is_demo_visitor() from public, anon;
grant execute on function public.is_demo_visitor() to authenticated, service_role;

create or replace function public.assert_demo_visitor()
returns uuid
language plpgsql
stable
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
begin
  if not public.is_demo_visitor() then
    raise exception 'Demo data is only available to a demo visitor.'
      using errcode = 'insufficient_privilege';
  end if;
  return v_owner;
end;
$$;

revoke all on function public.assert_demo_visitor() from public, anon;
grant execute on function public.assert_demo_visitor() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. The sample workspace.
--
-- Five accounts, chosen so the first screen answers the four questions the
-- product exists to answer: who owes me, who do I owe, how much, and what
-- happened. Four of them are receivable or payable and untouched, so the
-- dashboard's totals are exactly the figures the demo advertises. The fifth
-- carries a part payment already recorded against it, so the settlement idea --
-- outstanding, settled, remaining -- is legible before the visitor has done
-- anything at all.
--
-- On direction: the wire values are 'credit' for money the person owes the
-- owner and 'debit' for money the owner owes them. The two words read
-- backwards against the app's spoken vocabulary and that is deliberate and
-- documented -- docs/accounting-direction.md, app/lib/core/direction.dart.
-- What the seed fixes is the BALANCE each account ends on; the label the
-- interface prints is the interface's business, and it is already right.
--
-- Idempotent: seeding a workspace that already has people does nothing, so a
-- reload cannot double the ledger.
-- -----------------------------------------------------------------------------

create or replace function public.demo_seed()
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner  uuid := public.assert_demo_visitor();
  v_rahul  public.people;
  v_aarav  public.people;
  v_priya  public.people;
  v_neha   public.people;
  v_vikram public.people;
  v_people int;
begin
  select count(*) into v_people from public.people p where p.owner_id = v_owner;
  if v_people > 0 then
    return jsonb_build_object('seeded', false, 'reason', 'already_seeded');
  end if;

  -- The profile the rail and every currency-formatted figure read from.
  perform public.update_my_profile(
    p_name          => 'Demo visitor',
    p_phone         => null,
    p_business_name => 'Accounic Demo',
    p_currency      => 'INR',
    p_avatar_url    => null
  );

  v_rahul  := public.create_person(p_name => 'Rahul Sharma', p_type => 'person',
                                   p_phone => '+91 98200 41127');
  v_aarav  := public.create_person(p_name => 'Aarav Patel',  p_type => 'business',
                                   p_phone => '+91 99870 33410');
  v_priya  := public.create_person(p_name => 'Priya Shah',   p_type => 'person');
  v_neha   := public.create_person(p_name => 'Neha Mehta',   p_type => 'person');
  v_vikram := public.create_person(p_name => 'Vikram Rao',   p_type => 'business');

  -- Rahul Sharma -- they owe 8,500, across two entries.
  perform public.create_transaction(
    p_person_id => v_rahul.id, p_type => 'credit', p_amount_minor => 500000,
    p_date => current_date - 9, p_description => 'Laptop repair');
  perform public.create_transaction(
    p_person_id => v_rahul.id, p_type => 'credit', p_amount_minor => 350000,
    p_date => current_date - 2, p_description => 'Advance payment');

  -- Aarav Patel -- the owner owes 2,000.
  perform public.create_transaction(
    p_person_id => v_aarav.id, p_type => 'debit', p_amount_minor => 200000,
    p_date => current_date - 6, p_description => 'Equipment purchase');

  -- Priya Shah -- they owe 4,800.
  perform public.create_transaction(
    p_person_id => v_priya.id, p_type => 'credit', p_amount_minor => 480000,
    p_date => current_date - 4, p_description => 'Project payment');

  -- Neha Mehta -- they owe 1,200.
  perform public.create_transaction(
    p_person_id => v_neha.id, p_type => 'credit', p_amount_minor => 120000,
    p_date => current_date - 1, p_description => 'Reimbursement');

  -- Vikram Rao -- 15,000 invoiced, 9,000 already received. The engine works out
  -- the 6,000 that is left; nothing here does.
  perform public.create_transaction(
    p_person_id => v_vikram.id, p_type => 'credit', p_amount_minor => 1500000,
    p_date => current_date - 21, p_description => 'Site work');
  perform public.create_settlement(
    p_person_id => v_vikram.id, p_amount_minor => 900000, p_direction => 'in',
    p_date => current_date - 7, p_note => 'Part payment by transfer');

  return jsonb_build_object('seeded', true, 'people', 5);
end;
$$;

revoke all on function public.demo_seed() from public, anon;
grant execute on function public.demo_seed() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4. Reset.
--
-- Retracts each account's history and removes the account, both through the
-- production RPCs -- void_person_history() decides what a retraction is, and
-- delete_person() decides when an account may go. This function decides only
-- the order, and re-seeds afterwards.
-- -----------------------------------------------------------------------------

create or replace function public.demo_reset()
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner   uuid := public.assert_demo_visitor();
  v_person  record;
  v_removed int := 0;
begin
  for v_person in
    select p.id from public.people p where p.owner_id = v_owner
  loop
    perform public.void_person_history(v_person.id, 'Demo reset');
    perform public.delete_person(v_person.id);
    v_removed := v_removed + 1;
  end loop;

  perform public.demo_seed();

  return jsonb_build_object('reset', true, 'removed', v_removed);
end;
$$;

revoke all on function public.demo_reset() from public, anon;
grant execute on function public.demo_reset() to authenticated, service_role;
