/**
 * Creates (or repairs) the shared Accounic demo account (docs/demo.md).
 *
 * The hosted demo signs each visitor in anonymously, which is the right default:
 * a private workspace each, nothing to vandalise. This script makes the OTHER
 * kind of demo login — one email and password you can put in a deck, send to a
 * customer, or leave in a README, which comes back to the same books tomorrow.
 *
 * It sets `is_demo` in two places, and both are deliberate:
 *
 *   * the user's APP metadata, which only the service role can write and which
 *     the `handle_new_auth_user` trigger reads when a profile is provisioned;
 *   * `profiles.is_demo`, which is where the flag actually LIVES and what
 *     `is_demo_visitor()` and the administration screen read
 *     (db/migrations/0030). The trigger only fires on insert, so an account that
 *     already existed needs the column written directly.
 *
 * There is one database. This account is an ordinary Accounic account in it,
 * confined by exactly the RLS every other account is confined by; the flag
 * decides what the interface offers, never what the database will hand over.
 *
 * Run it from a terminal. It needs the service-role key, which must never reach
 * a browser, a Flutter build, a CI secret used by a web deploy, or this
 * repository.
 *
 * Usage:
 *
 *   SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=... \
 *   node db/tools/demo-account.mjs [email] [password]
 *
 * Defaults to demo@accounic.app with a password it generates and prints. Run it
 * again at any time: an existing account has its password reset, its flag
 * re-applied, and its books left alone.
 */

import { randomBytes } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceKey) {
  console.error(
    'SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must both be set, and must point\n' +
      'at the DEMO project — never at production.',
  );
  process.exit(1);
}

const email = process.argv[2] ?? 'demo@accounic.app';

// A generated password beats a memorable one even for a demo: this account can
// record and reset data, and "demo/demo" is the first thing anyone tries against
// every other host on the internet too.
const password =
  process.argv[3] ?? `Demo-${randomBytes(6).toString('base64url')}-${randomBytes(3).toString('hex')}`;

const admin = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function findByEmail(address) {
  // listUsers is paginated and there is no get-by-email; a demo project holds
  // few enough users that walking the pages is fine, and it stops at the match.
  for (let page = 1; page <= 20; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    const hit = data.users.find((user) => user.email?.toLowerCase() === address.toLowerCase());
    if (hit) return hit;
    if (data.users.length < 200) return null;
  }
  return null;
}

async function main() {
  const existing = await findByEmail(email);

  const attributes = {
    email,
    password,
    email_confirm: true,
    app_metadata: { is_demo: true },
    user_metadata: { name: 'Accounic Demo', business_name: 'Accounic Demo', currency: 'INR' },
  };

  let user;
  if (existing) {
    const { data, error } = await admin.auth.admin.updateUserById(existing.id, attributes);
    if (error) throw error;
    user = data.user;
    console.log(`Updated the existing demo account (${user.id}).`);
  } else {
    const { data, error } = await admin.auth.admin.createUser(attributes);
    if (error) throw error;
    user = data.user;
    console.log(`Created the demo account (${user.id}).`);
  }

  // Where the flag actually lives. The trigger sets it for a NEW user from the
  // app metadata above; an account that already existed needs it written here,
  // and writing it twice for a new one costs nothing and cannot be wrong.
  const flagged = await admin.from('profiles').update({ is_demo: true }).eq('id', user.id);
  if (flagged.error) throw flagged.error;

  // Seed as the account itself rather than with the service role, so the sample
  // books are written by the same RPC path a visitor's are — demo_seed() is
  // SECURITY INVOKER and is a no-op on a workspace that already has people.
  const asUser = createClient(url, process.env.SUPABASE_ANON_KEY ?? serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const signIn = await asUser.auth.signInWithPassword({ email, password });
  if (signIn.error) throw signIn.error;

  const seeded = await asUser.rpc('demo_seed');
  if (seeded.error) throw seeded.error;
  console.log('Sample workspace:', JSON.stringify(seeded.data));

  await asUser.auth.signOut();

  console.log('\nHand these out:\n');
  console.log(`  Email     ${email}`);
  console.log(`  Password  ${password}`);
  console.log(
    '\nAnyone signed in with it can reset the sample books from Profile, so a\n' +
      'visitor who leaves it in a mess is one tap away from tidy again.\n',
  );
}

main().catch((error) => {
  console.error(error.message ?? error);
  process.exit(1);
});
