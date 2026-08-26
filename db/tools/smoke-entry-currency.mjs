/**
 * Entry-currency end-to-end check (db/tools/smoke-entry-currency.mjs).
 *
 *   node db/tools/smoke-entry-currency.mjs
 *
 * Builds a throwaway workspace holding one INR entry, one USD entry and one AED
 * entry, then asserts what dashboard() hands a client:
 *
 *   * every activity row reports the amount and currency that were ENTERED,
 *     not the converted ledger figure;
 *   * every row also carries a base-currency equivalent, so the UI never has to
 *     convert anything itself;
 *   * totals_by_currency has a row per ENTRY currency — the currency the money
 *     was actually in, not the denomination of the account it landed in;
 *   * no total ever adds two currencies together.
 *
 * This is the check that would have caught the bug it was written for: the
 * originals were in the database all along, and every read path handed the
 * client the conversion instead.
 *
 * Creates its own user and deletes it again.
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
    .filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => {
      const i = l.indexOf('=');
      return [l.slice(0, i).trim(), l.slice(i + 1).trim()];
    }),
);

const URL = env.NEXT_PUBLIC_SUPABASE_URL;
const ANON = env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const SERVICE = env.SUPABASE_SERVICE_ROLE_KEY;

let passed = 0;
let failed = 0;
function check(label, ok, detail = '') {
  if (ok) { passed += 1; console.log(`ok   ${label}${detail ? ` — ${detail}` : ''}`); }
  else { failed += 1; console.log(`FAIL ${label}${detail ? ` — ${detail}` : ''}`); }
}

const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });
const email = `entry-currency-${Date.now()}@accounic.test`;
const password = `Entry-${Math.random().toString(36).slice(2)}-9!`;

const created = await admin.auth.admin.createUser({
  email, password, email_confirm: true,
  user_metadata: { name: 'Entry Currency', currency: 'INR' },
});
if (created.error) throw created.error;
const userId = created.data.user.id;

const api = createClient(URL, ANON, { auth: { persistSession: false } });
const signIn = await api.auth.signInWithPassword({ email, password });
if (signIn.error) throw signIn.error;

const today = new Date().toISOString().slice(0, 10);

try {
  // Cache the rates these conversions need. Stated as "one INR buys this much
  // of X", which is the shape upsert_exchange_rates() takes — the same call the
  // web and Flutter clients make (web/src/lib/rates.ts).
  const rates = await api.rpc('upsert_exchange_rates', {
    p_base: 'INR',
    p_rates: { USD: 0.0117, AED: 0.0430, INR: 1 },
    p_as_of: today,
    p_source: 'smoke',
  });
  check('rates cached', !rates.error, rates.error?.message ?? `${rates.data} pairs`);

  // A rupee-denominated person: this is the case the bug lived in. A USD entry
  // here is STORED as rupees, so if any read path reports amount_minor as "the"
  // amount, the dollars disappear.
  const person = await api.rpc('create_person', { p_name: 'Mixed Co', p_type: 'business', p_currency: 'INR' });
  if (person.error) throw person.error;
  const personId = person.data.id;

  const entries = [
    { label: 'INR 5,000', currency: null, minor: 500000, expectCurrency: 'INR', expectMinor: 500000 },
    // rate_e9 = units of the ACCOUNT currency per one entry currency.
    { label: 'USD 100',   currency: 'USD', minor: 10000,  rateE9: 85470085470,  expectCurrency: 'USD', expectMinor: 10000 },
    { label: 'AED 500',   currency: 'AED', minor: 50000,  rateE9: 23255813953,  expectCurrency: 'AED', expectMinor: 50000 },
  ];

  for (const e of entries) {
    const args = { p_person_id: personId, p_type: 'credit', p_date: today, p_description: e.label };
    if (e.currency) {
      // Entered in a foreign currency: the original goes in the entered_* pair
      // and the database converts for the ledger amount.
      args.p_entered_amount_minor = e.minor;
      args.p_entered_currency = e.currency;
      args.p_exchange_rate_e9 = e.rateE9;
      args.p_rate_source = 'smoke';
    } else {
      args.p_amount_minor = e.minor;
    }
    const res = await api.rpc('create_transaction', args);
    check(`recorded ${e.label}`, !res.error, res.error?.message);
  }

  const dash = await api.rpc('dashboard');
  check('dashboard() succeeds', !dash.error, dash.error?.message);
  const activity = dash.data?.recent_activity ?? [];
  check('three activity rows', activity.length === 3, `${activity.length}`);

  for (const e of entries) {
    const row = activity.find((r) => r.note === e.label);
    if (!row) { check(`activity row for ${e.label}`, false); continue; }

    check(`${e.label}: keeps its own currency`, row.entry_currency === e.expectCurrency,
      `entry_currency=${row.entry_currency}`);
    check(`${e.label}: keeps its own amount`, Number(row.entry_amount_minor) === e.expectMinor,
      `entry_amount_minor=${row.entry_amount_minor}`);
    check(`${e.label}: carries a base equivalent`, row.base_currency === 'INR' && row.amount_base_minor != null,
      `${row.amount_base_minor} ${row.base_currency}`);

    if (e.currency) {
      // The whole point: the entered figure and the stored ledger figure differ,
      // and the client is given both rather than only the second.
      check(`${e.label}: original differs from the converted ledger figure`,
        Number(row.entry_amount_minor) !== Number(row.amount_minor),
        `entered=${row.entry_amount_minor} ${row.entry_currency} / ledger=${row.amount_minor} ${row.currency}`);
    } else {
      check(`${e.label}: an INR entry needs no conversion`,
        Number(row.entry_amount_minor) === Number(row.amount_minor));
    }
  }

  const totals = dash.data?.totals_by_currency ?? [];
  const codes = totals.map((t) => t.currency).sort();
  check('totals_by_currency covers all three entry currencies',
    JSON.stringify(codes) === JSON.stringify(['AED', 'INR', 'USD']), codes.join(','));

  for (const e of entries) {
    const row = totals.find((t) => t.currency === e.expectCurrency);
    if (!row) { check(`${e.expectCurrency} total`, false); continue; }
    check(`${e.expectCurrency} total is that currency's own money`,
      Number(row.gross_credit) === e.expectMinor, `gross_credit=${row.gross_credit}`);
    check(`${e.expectCurrency} total carries a base equivalent`,
      row.base_currency === 'INR' && row.net_base_minor != null, `${row.net_base_minor}`);
  }

  // The arithmetic guard: no row may equal the sum of raw amounts across
  // currencies. 500000 + 10000 + 50000 = 560000 would be rupees, dollars and
  // dirhams added together.
  const naive = 560000;
  check('no currency row is the naive cross-currency sum',
    !totals.some((t) => Number(t.gross_credit) === naive));

  // The base headline still exists and is a conversion, not a raw sum.
  check('summary keeps a base-currency total', typeof dash.data?.summary?.total_receivable === 'number',
    `${dash.data?.summary?.total_receivable}`);
} finally {
  for (const table of ['settlements', 'transactions', 'people', 'exchange_rates']) {
    await admin.from(table).delete().eq('owner_id', userId);
  }
  await admin.from('app_admins').delete().eq('user_id', userId);
  await admin.auth.admin.deleteUser(userId);
  console.log('\n--- throwaway user removed ---');
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
