import 'server-only';

import { createClient } from '@supabase/supabase-js';

/**
 * Service-role client. Bypasses RLS, so it exists for exactly two jobs that the
 * Auth Admin API requires: creating users and setting passwords (context.md §25).
 *
 * Guards:
 *   - `server-only` makes importing this from a Client Component a build error.
 *   - The key is read from a non-NEXT_PUBLIC_ variable, so it cannot leak into
 *     the browser bundle even by accident.
 *   - Every caller must independently prove the requester is an admin; holding
 *     this client is not authorisation.
 */
export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceKey) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY is not configured on the server.');
  }

  return createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
