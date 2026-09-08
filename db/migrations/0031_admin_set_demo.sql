-- =============================================================================
-- 0031_admin_set_demo.sql
-- An administrator edits an account's type, in both directions.
--
-- 0030 gave one door: admin_convert_demo_user(), demo -> real, refusing
-- anything else. That is the right shape for the flow it serves — a visitor
-- becomes a customer, and it must be impossible to fire that at a paying user
-- by accident — and it is deliberately kept exactly as it is.
--
-- This adds the general edit beside it. An administrator creates demo users and
-- real users, and can change their minds afterwards: a real account made in
-- error, a customer who asked for a sandbox, a demo account that should have
-- been real from the start. One database, one directory, one flag, edited from
-- Administration.
--
-- Both write to admin_events, so the record shows which route was taken. The
-- specific one says `demo_user_converted` and the general one
-- `demo_status_changed`; an audit that could not tell them apart would be
-- hiding the more interesting of the two.
--
-- WHAT IT STILL WILL NOT DO
--
--   * Run for anyone but an administrator.
--   * Touch a single ledger row. Flipping this flag changes what the interface
--     OFFERS an account. It does not create, move, convert or delete one
--     person, transaction or settlement, in either direction.
--   * Change your own status. An administrator who marks themselves as a demo
--     user loses the administration screen they would need to undo it.
--   * Make an anonymous visitor real. They have no email and no password, so
--     the result would be an account nobody can sign in to.
-- =============================================================================

create or replace function public.admin_set_user_demo(
  p_user_id uuid,
  p_is_demo boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor     uuid := auth.uid();
  v_profile   public.profiles;
  v_anonymous boolean;
  v_people    int;
  v_entries   int;
begin
  if not public.is_admin() then
    raise exception 'Administrator access is required.' using errcode = 'insufficient_privilege';
  end if;

  if p_is_demo is null then
    raise exception 'Say which account type this should be.' using errcode = 'check_violation';
  end if;

  select * into v_profile from public.profiles p where p.id = p_user_id;
  if not found then
    raise exception 'User not found.' using errcode = 'no_data_found';
  end if;

  if p_user_id = v_actor then
    raise exception 'You cannot change your own account type.'
      using errcode = 'check_violation';
  end if;

  select coalesce(u.is_anonymous, false) into v_anonymous
  from auth.users u where u.id = p_user_id;

  if v_anonymous and p_is_demo = false then
    raise exception
      'That is an anonymous demo visitor with no email or password. Create a real '
      'account for them instead.'
      using errcode = 'check_violation';
  end if;

  -- Nothing to do is not an error. An administrator who clicks twice, or two
  -- administrators who act on the same row, should get the same calm answer as
  -- the one who acted first — and no second audit row saying nothing happened.
  if v_profile.is_demo = p_is_demo then
    return jsonb_build_object(
      'id', p_user_id,
      'email', v_profile.email::text,
      'name', v_profile.name,
      'is_demo', p_is_demo,
      'changed', false
    );
  end if;

  -- Counted before the change, so the record says what the account was carrying
  -- at the moment its type changed. Neither number moves as a result.
  select count(*) into v_people  from public.people       x where x.owner_id = p_user_id;
  select count(*) into v_entries from public.transactions x
   where x.owner_id = p_user_id and not x.is_void;

  update public.profiles set is_demo = p_is_demo where id = p_user_id;

  insert into public.admin_events (actor_id, action, target_id, detail)
  values (
    v_actor,
    'demo_status_changed',
    p_user_id,
    jsonb_build_object(
      'email', v_profile.email::text,
      'name', v_profile.name,
      'from', v_profile.is_demo,
      'to', p_is_demo,
      'people_kept', v_people,
      'transactions_kept', v_entries
    )
  );

  return jsonb_build_object(
    'id', p_user_id,
    'email', v_profile.email::text,
    'name', v_profile.name,
    'is_demo', p_is_demo,
    'changed', true,
    'people_kept', v_people,
    'transactions_kept', v_entries
  );
end;
$$;

revoke all on function public.admin_set_user_demo(uuid, boolean) from public, anon;
grant execute on function public.admin_set_user_demo(uuid, boolean)
  to authenticated, service_role;
