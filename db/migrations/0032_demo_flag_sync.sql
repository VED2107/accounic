-- =============================================================================
-- 0032_demo_flag_sync.sql
-- A user created as a demo user is actually marked as one.
--
-- THE BUG
--
-- 0030 reads `is_demo` out of the new auth user's app metadata inside
-- `handle_new_auth_user()`, which runs on INSERT into auth.users. The Supabase
-- Admin API does not put app_metadata there on the insert: it creates the row
-- and merges `app_metadata` immediately afterwards, in an UPDATE. So the
-- trigger ran against metadata that did not yet contain the key, wrote
-- `is_demo = false`, and the account an administrator had explicitly created as
-- a demo user appeared in Administration as a real one.
--
-- Found by creating one through the web form and looking:
--
--   auth.users.raw_app_meta_data ->> 'is_demo'  = 'true'
--   public.profiles.is_demo                     = false
--
-- THE FIX, IN TWO PLACES BECAUSE ONE IS NOT ENOUGH
--
-- Here: a second trigger on UPDATE of auth.users, so the flag lands whenever
-- the metadata arrives — whichever order the Admin API chooses, now or in a
-- future version of it. This is the durable half: it does not depend on any
-- caller remembering anything.
--
-- And in `adminCreateUser` (web/src/lib/admin-actions.ts): the server writes
-- profiles.is_demo explicitly after creating the user, so the outcome does not
-- depend on trigger timing at all.
--
-- Deliberately one-way. The metadata can turn an account INTO a demo one; it
-- can never turn one back, because clearing the flag is an administrative act
-- that belongs to admin_convert_demo_user() and admin_set_user_demo(), both of
-- which check who is asking and write an audit row. A metadata edit does
-- neither.
-- =============================================================================

create or replace function public.sync_demo_flag_from_metadata()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce((new.raw_app_meta_data ->> 'is_demo')::boolean, false) then
    update public.profiles
       set is_demo = true
     where id = new.id
       and is_demo = false;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_demo_metadata on auth.users;
create trigger on_auth_user_demo_metadata
  after update of raw_app_meta_data on auth.users
  for each row execute function public.sync_demo_flag_from_metadata();

-- Repair every account already created this way. There is no matching rule for
-- the other direction on purpose: an account whose metadata does not say
-- `is_demo` may perfectly well be a demo account that an administrator marked
-- through admin_set_user_demo(), and this must not undo that.
update public.profiles p
   set is_demo = true
  from auth.users u
 where u.id = p.id
   and p.is_demo = false
   and coalesce((u.raw_app_meta_data ->> 'is_demo')::boolean, false);

-- PostgREST caches the schema, and 0030 replaced admin_list_users() with a
-- four-argument version. Until the cache is reloaded, a client calling it with
-- p_demo_only gets "function not found" and the Demo tab shows nothing at all.
notify pgrst, 'reload schema';
