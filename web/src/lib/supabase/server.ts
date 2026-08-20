import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { cache } from 'react';
import type { Me } from '@/lib/types';

/**
 * Request-scoped Supabase client using the ANON key plus the user's session
 * cookie. Every query it makes is subject to RLS — this client can never see
 * another workspace (context.md §3).
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(env().url, env().anonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Called from a Server Component, where cookies are read-only.
          // middleware.ts already refreshed the session for this request.
        }
      },
    },
  });
}

function env() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    throw new Error(
      'Supabase is not configured. Copy web/.env.local.example to web/.env.local and fill it in.',
    );
  }
  return { url, anonKey };
}

/**
 * The signed-in user's profile, or null.
 *
 * `cache` dedupes this across a single render pass, so a layout, a page and
 * three components asking "who am I?" cost one round trip (context.md §23).
 */
export const getMe = cache(async (): Promise<Me | null> => {
  const supabase = await createClient();

  // getUser() revalidates the JWT with the auth server. getSession() alone
  // trusts a cookie the client could have written, so it is never used here.
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data, error } = await supabase.rpc('me');
  if (error || !data) return null;

  const me = data as Me;
  return me.is_active ? me : null;
});
