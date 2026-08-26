/**
 * Tenant-isolation and privilege security suite (db/tools/security-isolation.mjs).
 *
 *   node db/tools/security-isolation.mjs
 *
 * Runs over real HTTP against a real project, as three callers:
 *
 *   * anonymous — holding only the publishable key, which is in every shipped
 *     binary and every browser and is therefore public knowledge
 *   * user A    — a throwaway workspace with one person and one transaction
 *   * user B    — a second throwaway workspace that must not reach any of it
 *
 * It creates both users, proves what each can and cannot do, and deletes them
 * again. It writes only to workspaces it made, so it is safe against a live
 * project — but it does write, so prefer a staging one.
 *
 * Why this exists as well as db/tests/02_rls_isolation.sql: that suite proves
 * the RLS policies are right by becoming each user inside a transaction. This
 * proves the deployed HTTP surface agrees — grants, PostgREST, RPC argument
 * handling and all — which is where migration 0016 found a hole that the SQL
 * suite could not see. A policy can be perfect while a function that bypasses
 * it is reachable by `anon`.
 */

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');
const env = Object.fromEntries(
  readFileSync(join(repoRoot, 'web', '.env.local'), 'utf8')
    .split('\n')
    .filter((line) => line.includes('=') && !line.trim().startsWith('#'))
    .map((line) => {
      const i = line.indexOf('=');
      return [line.slice(0, i).trim(), line.slice(i + 1).trim()];
    }),
);

const URL = env.NEXT_PUBLIC_SUPABASE_URL;
const ANON = env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const SERVICE = env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL || !ANON || !SERVICE) {
  console.error('web/.env.local must define NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(2);
}

let passed = 0;
let failed = 0;
function check(label, ok, detail = '') {
  if (ok) {
    passed += 1;
    console.log(`ok   ${label}${detail ? ` — ${detail}` : ''}`);
  } else {
    failed += 1;
    console.log(`FAIL ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

/** Denied means an error came back AND no data did. Both halves matter: an
 *  empty 200 is a pass for a row read, but never for a privileged call. */
const denied = (result) => result.error !== null;
const noRows = (result) => (result.data ?? []).length === 0;

const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });
const stamp = Date.now();
const password = `Audit-${Math.random().toString(36).slice(2)}-9!`;

async function makeUser(tag) {
  const email = `sec-${tag}-${stamp}@accounic.test`;
  const created = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name: `Security ${tag}`, currency: 'INR' },
  });
  if (created.error) throw created.error;
  const client = createClient(URL, ANON, { auth: { persistSession: false } });
  const signIn = await client.auth.signInWithPassword({ email, password });
  if (signIn.error) throw signIn.error;
  return { client, id: created.data.user.id, email };
}

async function destroy(user) {
  // Ledger rows first: delete_person refuses an account with history, and this
  // is a teardown, not a product operation.
  for (const table of ['settlements', 'transactions', 'people', 'exchange_rates']) {
    await admin.from(table).delete().eq('owner_id', user.id);
  }
  await admin.from('app_admins').delete().eq('user_id', user.id);
  await admin.auth.admin.deleteUser(user.id);
}

const A = await makeUser('a');
const B = await makeUser('b');

try {
  /* ---------------------------------------------------------------------- */
  /* 1. The anonymous surface                                                */
  /* ---------------------------------------------------------------------- */

  const anon = createClient(URL, ANON, { auth: { persistSession: false } });

  for (const [fn, args] of [
    ['dashboard', {}],
    ['activity_page', {}],
    ['activity_summary', {}],
    ['search_all', { p_query: 'a' }],
    ['create_person', { p_name: 'anon' }],
    ['create_transaction', { p_person_id: A.id, p_type: 'credit', p_amount_minor: 1 }],
    ['create_settlement', { p_person_id: A.id, p_amount_minor: 1 }],
    ['set_person_opening_balance', { p_person_id: A.id, p_direction: 'none' }],
    ['void_person_history', { p_person_id: A.id }],
    ['delete_person', { p_person_id: A.id }],
    ['update_my_profile', { p_name: 'anon' }],
    ['me', {}],
    ['admin_list_users', {}],
    ['admin_system_info', {}],
    ['grant_admin', { p_email: 'anon@example.com' }],
    // These three are SECURITY DEFINER and read tenant tables, so RLS does not
    // apply to them. Before 0016 all three answered an anonymous caller.
    ['owner_rate_e9', { p_owner: A.id, p_from: 'AED', p_to: 'INR' }],
    ['owner_base_currency', { p_owner: A.id }],
    ['convert_for_owner', { p_owner: A.id, p_amount_minor: 1000, p_from: 'AED', p_to: 'INR' }],
    ['person_currency', { p_person_id: A.id }],
    ['person_ledger_currency', { p_person_id: A.id }],
  ]) {
    check(`anon denied ${fn}`, denied(await anon.rpc(fn, args)));
  }

  for (const table of [
    'people', 'transactions', 'settlements', 'profiles', 'app_admins',
    'exchange_rates', 'currencies', 'person_balances', 'owner_summary', 'activity_feed',
  ]) {
    const read = await anon.from(table).select('*').limit(1);
    check(`anon cannot read ${table}`, denied(read) || noRows(read));
  }
  check('anon cannot insert a person', denied(await anon.from('people').insert({ name: 'x' })));

  /* ---------------------------------------------------------------------- */
  /* 2. A's own workspace works — security must not cost function            */
  /* ---------------------------------------------------------------------- */

  const person = await A.client.rpc('create_person', {
    p_name: 'Audit Co', p_type: 'business', p_currency: 'AED',
  });
  check('A creates a person', !denied(person), person.error?.message);
  const personId = person.data?.id;

  const today = new Date().toISOString().slice(0, 10);
  const txn = await A.client.rpc('create_transaction', {
    p_person_id: personId, p_type: 'credit', p_amount_minor: 50000, p_date: today,
  });
  check('A records a transaction', !denied(txn), txn.error?.message);

  const dash = await A.client.rpc('dashboard');
  check('A reads their dashboard', !denied(dash), dash.error?.message);
  check('A gets per-currency totals', Array.isArray(dash.data?.totals_by_currency));
  check('A owns exactly one person', (await A.client.from('person_balances').select('*')).data?.length === 1);
  check('A reads their OWN base currency', !denied(await A.client.rpc('owner_base_currency', { p_owner: A.id })));
  check('A reads their OWN rate', !denied(await A.client.rpc('owner_rate_e9', { p_owner: A.id, p_from: 'AED', p_to: 'INR' })));

  /* ---------------------------------------------------------------------- */
  /* 3. B must reach none of it                                              */
  /* ---------------------------------------------------------------------- */

  check("B denied A's rates (IDOR)", denied(await B.client.rpc('owner_rate_e9', { p_owner: A.id, p_from: 'AED', p_to: 'INR' })));
  check("B denied A's base currency", denied(await B.client.rpc('owner_base_currency', { p_owner: A.id })));
  check("B denied A's conversion", denied(await B.client.rpc('convert_for_owner', { p_owner: A.id, p_amount_minor: 1000, p_from: 'AED', p_to: 'INR' })));
  check("B denied A's person page", denied(await B.client.rpc('person_page', { p_person_id: personId })));

  check("B cannot read A's person", noRows(await B.client.from('people').select('*').eq('id', personId)));
  check("B cannot read A's transactions", noRows(await B.client.from('transactions').select('*').eq('person_id', personId)));
  check("B sees an empty ledger", (await B.client.from('person_balances').select('*')).data?.length === 0);

  const updated = await B.client.from('people').update({ name: 'pwned' }).eq('id', personId).select();
  check("B cannot rename A's person", denied(updated) || noRows(updated));
  const deleted = await B.client.from('people').delete().eq('id', personId).select();
  check("B cannot delete A's person", denied(deleted) || noRows(deleted));

  check("B cannot update A's person by RPC", denied(await B.client.rpc('update_person', {
    p_person_id: personId, p_name: 'pwned', p_type: 'person',
  })));
  check("B cannot void A's history", denied(await B.client.rpc('void_person_history', { p_person_id: personId })));
  check("B cannot delete A's person by RPC", denied(await B.client.rpc('delete_person', { p_person_id: personId })));
  check("B cannot write into A's workspace", denied(await B.client.rpc('create_transaction', {
    p_person_id: personId, p_type: 'credit', p_amount_minor: 1, p_date: today,
  })));
  check("B cannot settle against A's account", denied(await B.client.rpc('create_settlement', {
    p_person_id: personId, p_amount_minor: 1, p_date: today,
  })));
  check("B cannot set an opening balance on A's person", denied(await B.client.rpc('set_person_opening_balance', {
    p_person_id: personId, p_direction: 'they_owe_me', p_amount_minor: 1,
  })));

  // Forging owner_id on an insert must not plant a row in someone else's books.
  const forged = await B.client.from('people').insert({ owner_id: A.id, name: 'forged' }).select();
  check('B cannot forge owner_id on insert', denied(forged) || noRows(forged));

  /* ---------------------------------------------------------------------- */
  /* 4. Privilege escalation                                                 */
  /* ---------------------------------------------------------------------- */

  check('B cannot list users', denied(await B.client.rpc('admin_list_users', {})));
  check('B cannot read system info', denied(await B.client.rpc('admin_system_info', {})));
  check('B cannot disable another account', denied(await B.client.rpc('admin_set_user_active', { p_user_id: A.id, p_active: false })));
  check('B cannot grant themselves admin by RPC', denied(await B.client.rpc('grant_admin', { p_email: B.email })));
  const selfAdmin = await B.client.from('app_admins').insert({ user_id: B.id }).select();
  check('B cannot insert themselves into app_admins', denied(selfAdmin) || noRows(selfAdmin));
  const stillNotAdmin = await B.client.rpc('me');
  check('B is still not an admin', stillNotAdmin.data?.is_admin === false);

  // is_active is administrative state; a user may not flip their own. Setting
  // it to the value it already holds is a no-op the trigger correctly ignores,
  // so the attempt has to be a real change to test anything.
  const selfFlip = await B.client.from('profiles').update({ is_active: false }).eq('id', B.id).select();
  check('B cannot flip their own is_active', denied(selfFlip) || noRows(selfFlip),
    denied(selfFlip) ? selfFlip.error.code : `rows=${(selfFlip.data ?? []).length}`);
  const stillActive = await B.client.rpc('me');
  check('B is still active', stillActive.data?.is_active !== false);
  // Nor may they move their profile row to someone else.
  const hijack = await B.client.from('profiles').update({ name: 'pwned' }).eq('id', A.id).select();
  check("B cannot edit A's profile", denied(hijack) || noRows(hijack));

  /* ---------------------------------------------------------------------- */
  /* 5. Malformed and hostile input is rejected, not executed                */
  /* ---------------------------------------------------------------------- */

  check('a negative amount is refused', denied(await A.client.rpc('create_transaction', {
    p_person_id: personId, p_type: 'credit', p_amount_minor: -5000, p_date: today,
  })));
  check('a zero amount is refused', denied(await A.client.rpc('create_transaction', {
    p_person_id: personId, p_type: 'credit', p_amount_minor: 0, p_date: today,
  })));
  check('an unknown person id is refused', denied(await A.client.rpc('person_page', {
    p_person_id: '00000000-0000-0000-0000-000000000000',
  })));
  check('a malformed uuid is refused', denied(await A.client.rpc('person_page', { p_person_id: 'not-a-uuid' })));
  // A quoting bug would execute this; parameterised SQL stores it as a name.
  const injection = await A.client.rpc('create_person', { p_name: "Robert'); drop table public.people;--" });
  check('a SQL-injection payload is stored as text, not run', !denied(injection));
  check('the people table still exists', (await A.client.from('people').select('id').limit(1)).error === null);
  if (injection.data?.id) await A.client.rpc('delete_person', { p_person_id: injection.data.id });

  /* ---------------------------------------------------------------------- */
  /* 6. An expired / forged session is not a session                         */
  /* ---------------------------------------------------------------------- */

  const forgedJwt = createClient(URL, ANON, {
    auth: { persistSession: false },
    global: { headers: { Authorization: 'Bearer not.a.real.token' } },
  });
  check('a forged bearer token is refused', denied(await forgedJwt.rpc('dashboard')));

  const signedOut = createClient(URL, ANON, { auth: { persistSession: false } });
  await signedOut.auth.signOut();
  check('a signed-out client is refused', denied(await signedOut.rpc('dashboard')));
} finally {
  await destroy(A);
  await destroy(B);
  console.log('\n--- throwaway users removed ---');
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
