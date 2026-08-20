'use client';

import { createBrowserClient } from '@supabase/ssr';

/**
 * Browser Supabase client. Holds the ANON key only — the service-role key is
 * never bundled (context.md §24). Everything it can do is bounded by RLS.
 */
let browserClient: ReturnType<typeof createBrowserClient> | undefined;

export function createClient() {
  if (!browserClient) {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!url || !anonKey) throw new Error('Supabase is not configured.');
    browserClient = createBrowserClient(url, anonKey);
  }
  return browserClient;
}
