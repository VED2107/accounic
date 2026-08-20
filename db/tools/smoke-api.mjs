/**
 * End-to-end API smoke test (db/tools/smoke-api.mjs).
 *
 * Exercises the exact path the three clients use — anon key, a real signed-in
 * session, PostgREST, RLS, and the RPCs — rather than a privileged SQL
 * connection. If this passes, the web and Flutter clients are talking to a
 * working backend.
 *
 *   node db/tools/smoke-api.mjs
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
      const index = line.indexOf('=');
      return [line.slice(0, index).trim(), line.slice(index + 1).trim()];
    }),
);

const URL = env.NEXT_PUBLIC_SUPABASE_URL;
const ANON = env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

let failures = 0;
function check(label, condition, detail = '') {
  if (condition) {
    console.log(`ok   ${label}${detail ? ` (${detail})` : ''}`);
  } else {
    failures += 1;
    console.log(`FAIL ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

const rupees = (minor) => `₹${(minor / 100).toLocaleString('en-IN')}`;

// --- anonymous ---------------------------------------------------------------

const anon = createClient(URL, ANON, { auth: { persistSession: false } });
{
  const { data, error } = await anon.from('people').select('*');
  check('anon cannot read people', error !== null || (data ?? []).length === 0, error?.code ?? '');
  const rpc = await anon.rpc('dashboard');
  check('anon cannot call dashboard', rpc.error !== null, rpc.error?.code ?? '');
}

// --- demo user ---------------------------------------------------------------

const demo = createClient(URL, ANON, { auth: { persistSession: false } });
const signIn = await demo.auth.signInWithPassword({
  email: 'demo@example.com',
  password: 'Demo@12345',
});
check('demo signs in with email + password', !signIn.error, signIn.error?.message ?? '');
if (signIn.error) process.exit(1);

const me = await demo.rpc('me');
check('me() returns the profile', me.data?.email === 'demo@example.com', me.data?.name);
check('me() reports admin', me.data?.is_admin === true);
check('currency comes from the profile', me.data?.currency === 'INR');

const dash = await demo.rpc('dashboard');
check('dashboard() succeeds', !dash.error, dash.error?.message ?? '');
check(
  'dashboard receivable is an integer number, not a string',
  typeof dash.data?.summary?.total_receivable === 'number',
  typeof dash.data?.summary?.total_receivable,
);
check(
  'dashboard totals match the seed',
  dash.data?.summary?.total_receivable === 2075000 && dash.data?.summary?.total_payable === 335000,
  `${rupees(dash.data?.summary?.total_receivable)} in / ${rupees(dash.data?.summary?.total_payable)} out`,
);
check('recent activity is populated', (dash.data?.recent_activity ?? []).length > 0,
  `${dash.data?.recent_activity?.length} entries`);

const people = await demo.from('person_balances').select('*').order('name');
check('person_balances is readable', !people.error, people.error?.message ?? '');
check('only the demo workspace is visible', (people.data ?? []).length === 6,
  `${people.data?.length} people`);

const rahul = people.data.find((p) => p.name === 'Rahul Traders');
check('Rahul Traders receivable', rahul.outstanding_receivable === 1700000, rupees(rahul.outstanding_receivable));
check('Rahul Traders net', rahul.net_balance === 1700000, rupees(rahul.net_balance));

const kumar = people.data.find((p) => p.name === 'Kumar Hardware');
check('mixed account keeps both sides', kumar.outstanding_receivable === 40000 && kumar.outstanding_payable === 225000,
  `${rupees(kumar.outstanding_receivable)} in / ${rupees(kumar.outstanding_payable)} out`);
check('mixed account net is payable', kumar.net_balance === -185000, rupees(kumar.net_balance));

const page = await demo.rpc('person_page', { p_person_id: rahul.person_id, p_limit: 30, p_offset: 0 });
check('person_page() succeeds', !page.error, page.error?.message ?? '');
check('timeline includes transactions and settlements', (page.data?.timeline ?? []).length === 4,
  `${page.data?.timeline?.length} entries`);
check('partially settled invoice is marked partial',
  page.data.timeline.some((e) => e.status === 'partial' && e.remaining_minor === 650000));
check('open transactions are listed for settling', (page.data?.open_transactions ?? []).length === 3);

const search = await demo.rpc('search_all', { p_query: 'rahul' });
check('search finds people', search.data?.people?.[0]?.name === 'Rahul Traders');
const noteSearch = await demo.rpc('search_all', { p_query: 'Invoice #102' });
check('search finds transaction notes', (noteSearch.data?.transactions ?? []).length === 1);

// --- a full write cycle ------------------------------------------------------

const created = await demo.rpc('create_person', { p_name: 'Smoke Test Co', p_type: 'business' });
check('create_person()', !created.error, created.error?.message ?? '');
const personId = created.data.id;

const txn = await demo.rpc('create_transaction', {
  p_person_id: personId,
  p_type: 'credit',
  p_amount_minor: 1000000,
  p_date: new Date().toISOString().slice(0, 10),
  p_description: 'Smoke test invoice',
});
check('create_transaction() returns the new balance', txn.data?.balance?.outstanding_receivable === 1000000,
  rupees(txn.data?.balance?.outstanding_receivable));

const partial = await demo.rpc('create_settlement', {
  p_person_id: personId,
  p_amount_minor: 400000,
  p_transaction_id: txn.data.transaction.id,
  p_date: new Date().toISOString().slice(0, 10),
  p_note: 'Smoke partial',
});
check('partial settlement leaves the remainder', partial.data?.balance?.outstanding_receivable === 600000,
  rupees(partial.data?.balance?.outstanding_receivable));

const over = await demo.rpc('create_settlement', {
  p_person_id: personId,
  p_amount_minor: 99900000,
  p_direction: 'in',
  p_date: new Date().toISOString().slice(0, 10),
});
check('over-settlement is refused', over.error !== null, over.error?.message ?? '');

const rest = await demo.rpc('settle_account', { p_person_id: personId, p_note: 'Smoke final' });
check('settle_account() clears the balance', rest.data?.balance?.outstanding_receivable === 0);

const voided = await demo.rpc('void_settlement', { p_settlement_id: rest.data.settlement.id });
check('voiding a settlement restores the outstanding amount',
  voided.data?.balance?.outstanding_receivable === 600000,
  rupees(voided.data?.balance?.outstanding_receivable));

const badAmount = await demo.rpc('create_transaction', {
  p_person_id: personId,
  p_type: 'credit',
  p_amount_minor: -500,
});
check('negative amounts are refused', badAmount.error !== null, badAmount.error?.message ?? '');

// --- cross-tenant isolation over the real API -------------------------------

const friend = createClient(URL, ANON, { auth: { persistSession: false } });
await friend.auth.signInWithPassword({ email: 'friend@example.com', password: 'Demo@12345' });

const friendPeople = await friend.from('person_balances').select('*');
check('the second workspace sees only its own people', (friendPeople.data ?? []).length === 2,
  `${friendPeople.data?.length} people`);

const leak = await friend.from('people').select('*').eq('id', rahul.person_id);
check('workspace B cannot read a workspace A person by id', (leak.data ?? []).length === 0);

const crossPage = await friend.rpc('person_page', { p_person_id: rahul.person_id });
check('workspace B cannot open a workspace A account', crossPage.error !== null, crossPage.error?.code ?? '');

const crossWrite = await friend.rpc('create_transaction', {
  p_person_id: rahul.person_id,
  p_type: 'credit',
  p_amount_minor: 100,
});
check('workspace B cannot write into workspace A', crossWrite.error !== null, crossWrite.error?.code ?? '');

const escalate = await friend.from('app_admins').insert({ user_id: (await friend.rpc('me')).data.id });
check('a normal user cannot make themselves an admin', escalate.error !== null, escalate.error?.code ?? '');

const adminPeek = await friend.rpc('admin_list_users');
check('a normal user cannot list users', adminPeek.error !== null, adminPeek.error?.code ?? '');

const adminList = await demo.rpc('admin_list_users');
check('an admin can list users', !adminList.error && adminList.data.total >= 2,
  `${adminList.data?.total} users`);

// --- cleanup -----------------------------------------------------------------

await demo.rpc('set_person_archived', { p_person_id: personId, p_archived: true });

console.log(failures === 0 ? '\n=== API SMOKE TEST PASSED ===' : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
