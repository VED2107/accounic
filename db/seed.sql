-- =============================================================================
-- seed.sql — demo data (context.md Deliverables #14)
--
-- Creates two isolated workspaces so tenant isolation is visible immediately:
--
--   demo@example.com    — Indian trading business
--   friend@example.com  — a second, unrelated workspace
--
-- Run AFTER 0001..0007. Service role / SQL editor only. Idempotent.
-- Do not run against production.
--
-- THE PASSWORD IS NOT IN THIS FILE, and this script refuses to run without one.
-- It used to be `Demo@12345`, written here and again in db/tools/smoke-api.mjs,
-- and demo@example.com was granted admin. That was survivable while the
-- repository was private; in a public one it is a known-password administrator
-- for whatever project the script is pointed at. Both users were deleted from
-- the live project on 2026-08-26 (docs/deployment.md §2), and the shape that
-- made it possible is closed here rather than only cleaned up after the fact.
--
-- Supply a password for this session, and opt in to admin separately:
--
--   select set_config('accounic.seed_password', '<a long random string>', false);
--   select set_config('accounic.seed_admin',    'on', false);  -- optional
--   \i db/seed.sql
--
-- Nothing is granted admin unless `accounic.seed_admin` is on. Use
-- `select public.grant_admin('you@example.com')` for a real administrator.
-- =============================================================================

set local role postgres;

do $$
declare
  v_demo   uuid;
  v_friend uuid;
  -- No default, deliberately: a seed script that will invent a password is a
  -- seed script that ships one.
  v_password text := nullif(btrim(coalesce(current_setting('accounic.seed_password', true), '')), '');
  v_grant_admin boolean := lower(coalesce(current_setting('accounic.seed_admin', true), '')) in ('on','true','yes','1');
begin
  if v_password is null then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'No seed password was set.',
      hint    = 'select set_config(''accounic.seed_password'', ''<a long random string>'', false); then re-run. The password is deliberately not stored in this file.';
  end if;

  if length(v_password) < 12 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'The seed password is too short (minimum 12 characters).';
  end if;
  ---------------------------------------------------------------------------
  -- Auth users. Passwords are bcrypt hashed exactly the way GoTrue does it.
  --
  -- Guarded with EXISTS rather than ON CONFLICT: auth.users enforces email
  -- uniqueness through a PARTIAL index (where is_sso_user = false), and a
  -- partial index cannot serve as an ON CONFLICT arbiter.
  ---------------------------------------------------------------------------
  if not exists (select 1 from auth.users where email = 'demo@example.com') then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      -- GoTrue scans these into non-nullable Go strings. Left NULL, every
      -- subsequent sign-in fails with "Database error querying schema".
      confirmation_token, recovery_token, email_change, email_change_token_new,
      email_change_token_current, phone_change, phone_change_token,
      reauthentication_token
    )
    values (
      '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
      'demo@example.com', crypt(v_password, gen_salt('bf')),
      now(), '{"provider":"email","providers":["email"]}'::jsonb,
      '{"name":"Ved","business_name":"Ved Traders","currency":"INR"}'::jsonb,
      now(), now(),
      '', '', '', '', '', '', '', ''
    );
  end if;

  if not exists (select 1 from auth.users where email = 'friend@example.com') then
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      -- GoTrue scans these into non-nullable Go strings. Left NULL, every
      -- subsequent sign-in fails with "Database error querying schema".
      confirmation_token, recovery_token, email_change, email_change_token_new,
      email_change_token_current, phone_change, phone_change_token,
      reauthentication_token
    )
    values (
      '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
      'friend@example.com', crypt(v_password, gen_salt('bf')),
      now(), '{"provider":"email","providers":["email"]}'::jsonb,
      '{"name":"Arjun","business_name":"Arjun Electricals","currency":"INR"}'::jsonb,
      now(), now(),
      '', '', '', '', '', '', '', ''
    );
  end if;

  select id into v_demo   from auth.users where email = 'demo@example.com';
  select id into v_friend from auth.users where email = 'friend@example.com';

  -- GoTrue writes an identity row; without it password login can misbehave.
  if not exists (select 1 from auth.identities where user_id = v_demo) then
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (v_demo::text, v_demo, jsonb_build_object('sub', v_demo::text, 'email', 'demo@example.com'), 'email', now(), now(), now());
  end if;
  if not exists (select 1 from auth.identities where user_id = v_friend) then
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (v_friend::text, v_friend, jsonb_build_object('sub', v_friend::text, 'email', 'friend@example.com'), 'email', now(), now(), now());
  end if;

  -- Admin is opt-in. A demo account that is an administrator by default is how
  -- a seed password becomes an administrative credential.
  if v_grant_admin then
    insert into public.app_admins (user_id) values (v_demo) on conflict do nothing;
    raise notice 'demo@example.com was granted admin because accounic.seed_admin is on.';
  end if;

  ---------------------------------------------------------------------------
  -- Workspace A — demo@example.com
  ---------------------------------------------------------------------------
  if not exists (select 1 from public.people where owner_id = v_demo) then
    with p as (
      insert into public.people (owner_id, name, type, phone, email, address, notes)
      values
        (v_demo, 'Rahul Traders',        'business', '+91 98200 11223', 'accounts@rahultraders.in', 'Dadar West, Mumbai', 'Wholesale buyer, pays on 30-day terms'),
        (v_demo, 'Sharma Electricals',   'business', '+91 98200 44556', null, 'Lamington Road, Mumbai', 'Main supplier for fittings'),
        (v_demo, 'Priya Nair',           'person',   '+91 99300 77889', 'priya.nair@example.com', null, 'Personal loan'),
        (v_demo, 'Kumar Hardware',       'business', '+91 97600 22110', null, 'Thane', null),
        (v_demo, 'Anil Deshmukh',        'person',   '+91 98111 33445', null, null, 'Neighbour'),
        (v_demo, 'Mehta & Sons',         'business', '+91 98333 55667', 'billing@mehtasons.co.in', 'Surat', 'Archived — account closed')
      returning id, name
    )
    insert into public.transactions (owner_id, person_id, type, amount_minor, transaction_date, description, created_by)
    select v_demo, p.id, v.type::public.txn_type, v.amount, current_date - v.days_ago, v.note, v_demo
    from p
    join (values
      ('Rahul Traders',      'credit', 1050000::bigint, 22, 'Invoice #101 — 40 units'),
      ('Rahul Traders',      'credit',  800000::bigint, 12, 'Invoice #102 — repeat order'),
      ('Rahul Traders',      'credit',  250000::bigint,  3, 'Invoice #108 — accessories'),
      ('Sharma Electricals', 'debit',   600000::bigint, 18, 'Purchase — copper wire'),
      ('Sharma Electricals', 'debit',   150000::bigint,  6, 'Purchase — switchgear'),
      ('Priya Nair',         'credit',  500000::bigint, 60, 'Personal loan given'),
      ('Kumar Hardware',     'debit',   225000::bigint,  9, 'Tools and consumables'),
      ('Kumar Hardware',     'credit',   40000::bigint,  4, 'Returned faulty drill'),
      ('Anil Deshmukh',      'credit',   75000::bigint,  1, 'Lent cash'),
      ('Mehta & Sons',       'credit',  300000::bigint, 90, 'Final invoice')
    ) as v(person_name, type, amount, days_ago, note)
      on v.person_name = p.name;

    -- Settlements: partial, full, and account-level (context.md §9)
    insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor, settlement_date, note, created_by)
    select v_demo, t.person_id, t.id, 'in', 400000, current_date - 8, 'Part payment by NEFT', v_demo
    from public.transactions t
    join public.people pe on pe.id = t.person_id
    where t.owner_id = v_demo and pe.name = 'Rahul Traders' and t.description = 'Invoice #101 — 40 units';

    insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor, settlement_date, note, created_by)
    select v_demo, t.person_id, t.id, 'out', 600000, current_date - 10, 'Paid in full — cheque 004512', v_demo
    from public.transactions t
    join public.people pe on pe.id = t.person_id
    where t.owner_id = v_demo and pe.name = 'Sharma Electricals' and t.description = 'Purchase — copper wire';

    insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor, settlement_date, note, created_by)
    select v_demo, pe.id, null, 'in', 200000, current_date - 20, 'Cash received', v_demo
    from public.people pe where pe.owner_id = v_demo and pe.name = 'Priya Nair';

    insert into public.settlements (owner_id, person_id, transaction_id, direction, amount_minor, settlement_date, note, created_by)
    select v_demo, pe.id, null, 'in', 300000, current_date - 85, 'Settled and closed', v_demo
    from public.people pe where pe.owner_id = v_demo and pe.name = 'Mehta & Sons';

    update public.people set is_archived = true
    where owner_id = v_demo and name = 'Mehta & Sons';
  end if;

  ---------------------------------------------------------------------------
  -- Workspace B — friend@example.com (must never be visible to workspace A)
  ---------------------------------------------------------------------------
  if not exists (select 1 from public.people where owner_id = v_friend) then
    with p as (
      insert into public.people (owner_id, name, type, phone)
      values
        (v_friend, 'Nikhil Stores', 'business', '+91 90000 12345'),
        (v_friend, 'Sunita Rao',    'person',   '+91 90000 67890')
      returning id, name
    )
    insert into public.transactions (owner_id, person_id, type, amount_minor, transaction_date, description, created_by)
    select v_friend, p.id, v.type::public.txn_type, v.amount, current_date - v.days_ago, v.note, v_friend
    from p
    join (values
      ('Nikhil Stores', 'credit', 1200000::bigint, 5, 'Monthly supply'),
      ('Sunita Rao',    'debit',   350000::bigint, 2, 'Advance received for order')
    ) as v(person_name, type, amount, days_ago, note)
      on v.person_name = p.name;
  end if;
end $$;

-- Sanity readout
select p.email, s.total_receivable, s.total_payable, s.net_position
from public.owner_summary s
join public.profiles p on p.id = s.owner_id
order by p.email;
