-- =============================================================================
-- 0007_admin.sql
-- Administrative surface (context.md §2, §25).
--
-- Split of responsibility:
--   * Credential operations (create user, set password, delete auth user) need
--     the Supabase Auth Admin API and therefore live in the Next.js server
--     routes, which hold the service-role key. Never a client.
--   * Everything that is plain data — listing users, enabling/disabling — is a
--     SECURITY DEFINER function here that re-checks is_admin() itself, so it is
--     safe even if it were ever exposed by mistake.
--
-- Deliberately absent: any way for an admin to read another user's ledger.
-- =============================================================================

create or replace function public.admin_list_users(
  p_query  text default null,
  p_limit  int  default 50,
  p_offset int  default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_like text;
begin
  if not public.is_admin() then
    raise exception 'Administrator access is required.' using errcode = 'insufficient_privilege';
  end if;

  p_limit  := least(greatest(coalesce(p_limit, 50), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);
  v_like   := '%' || btrim(coalesce(p_query, '')) || '%';

  return jsonb_build_object(
    'total', (
      select count(*) from public.profiles p
      where p.name ilike v_like or p.email::text ilike v_like
    ),
    'users', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from (
        select p.id, p.name, p.email::text as email, p.phone, p.business_name,
               p.currency, p.is_active, p.created_at, p.updated_at,
               public.is_admin(p.id) as is_admin,
               u.last_sign_in_at,
               (select count(*) from public.people    x where x.owner_id = p.id) as people_count,
               (select count(*) from public.transactions x where x.owner_id = p.id) as transaction_count
        from public.profiles p
        join auth.users u on u.id = p.id
        where p.name ilike v_like or p.email::text ilike v_like
        order by p.created_at desc
        limit p_limit offset p_offset
      ) r
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_set_user_active(p_user_id uuid, p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.profiles;
begin
  if not public.is_admin() then
    raise exception 'Administrator access is required.' using errcode = 'insufficient_privilege';
  end if;
  if p_user_id = auth.uid() and coalesce(p_active, true) = false then
    raise exception 'You cannot disable your own administrator account.'
      using errcode = 'check_violation';
  end if;

  update public.profiles set is_active = coalesce(p_active, true)
  where id = p_user_id
  returning * into v_row;

  if not found then
    raise exception 'User not found.' using errcode = 'no_data_found';
  end if;

  return jsonb_build_object('id', v_row.id, 'is_active', v_row.is_active);
end;
$$;

create or replace function public.admin_system_info()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Administrator access is required.' using errcode = 'insufficient_privilege';
  end if;

  return jsonb_build_object(
    'users_total',        (select count(*) from public.profiles),
    'users_active',       (select count(*) from public.profiles where is_active),
    'admins',             (select count(*) from public.app_admins),
    'people_total',       (select count(*) from public.people),
    'transactions_total', (select count(*) from public.transactions where not is_void),
    'settlements_total',  (select count(*) from public.settlements where not is_void),
    'database_size',      pg_size_pretty(pg_database_size(current_database())),
    'server_time',        now()
  );
end;
$$;

-- The one call a normal client makes: "should I render the admin nav item?"
create or replace function public.me()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return null;
  end if;

  return (
    select jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'email', p.email::text,
      'phone', p.phone,
      'business_name', p.business_name,
      'avatar_url', p.avatar_url,
      'currency', p.currency,
      'is_active', p.is_active,
      'is_admin', public.is_admin(p.id),
      'created_at', p.created_at
    )
    from public.profiles p where p.id = v_uid
  );
end;
$$;

revoke all on function public.admin_list_users(text, int, int)   from public, anon;
revoke all on function public.admin_set_user_active(uuid, boolean) from public, anon;
revoke all on function public.admin_system_info()                from public, anon;
revoke all on function public.me()                               from public, anon;

grant execute on function public.admin_list_users(text, int, int)   to authenticated, service_role;
grant execute on function public.admin_set_user_active(uuid, boolean) to authenticated, service_role;
grant execute on function public.admin_system_info()                to authenticated, service_role;
grant execute on function public.me()                               to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Bootstrap helper. Run once from the Supabase SQL editor (service role) after
-- creating the first user:
--
--   select public.grant_admin('admin@example.com');
--
-- It is service-role only: authenticated has no execute privilege, so a normal
-- user calling it over the API gets a permission error, not an admin badge.
-- -----------------------------------------------------------------------------

create or replace function public.grant_admin(p_email text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select id into v_id from auth.users where lower(email) = lower(btrim(p_email));
  if v_id is null then
    raise exception 'No auth user with email %', p_email using errcode = 'no_data_found';
  end if;

  insert into public.app_admins (user_id, granted_by)
  values (v_id, auth.uid())
  on conflict (user_id) do nothing;

  return v_id;
end;
$$;

create or replace function public.revoke_admin(p_email text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select id into v_id from auth.users where lower(email) = lower(btrim(p_email));
  if v_id is null then
    raise exception 'No auth user with email %', p_email using errcode = 'no_data_found';
  end if;
  if (select count(*) from public.app_admins) <= 1 then
    raise exception 'Refusing to remove the last administrator.' using errcode = 'check_violation';
  end if;

  delete from public.app_admins where user_id = v_id;
  return v_id;
end;
$$;

revoke all on function public.grant_admin(text)  from public, anon, authenticated;
revoke all on function public.revoke_admin(text) from public, anon, authenticated;
grant execute on function public.grant_admin(text)  to service_role;
grant execute on function public.revoke_admin(text) to service_role;
