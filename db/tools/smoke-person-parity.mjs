/**
 * Person Details = Dashboard = Person statement, end to end
 * (db/tools/smoke-person-parity.mjs).
 *
 *   node db/tools/smoke-person-parity.mjs [dump-dir]
 *
 * Builds a throwaway INR workspace whose history was entered at a rate that is
 * NOT today's (1 AED = ₹22.50 then, ₹26.32 in the cache now) and covers every
 * shape the brief names: an account kept in AED holding rupee and dirham
 * entries, a rupee account holding a dirham entry, opening balances on both, a
 * partial settlement, and a transfer between the two accounts across
 * currencies. Then:
 *
 *   * every person's per-currency rows, summed, equal dashboard()'s
 *     totals_by_currency exactly (person-dashboard-parity.mjs);
 *   * the dirham account's workspace-currency figure keeps its rupee entries
 *     at the rupees that were entered, and differs from the old whole-position
 *     today's-rate figure — the bug this was written for.
 *
 * With a dump dir, writes each person_page() JSON there so the web and Flutter
 * statement renderers can be run over the same data. Creates its own user and
 * deletes it again.
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const here = dirname(fileURLToPath(import.meta.url));
const env = Object.fromEntries(
  readFileSync(join(here, '..', '..', 'web', '.env.local'), 'utf8')
    .split('\n')
    .filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
);
const dumpDir = process.argv[2] ? resolve(process.argv[2]) : null;

let passed = 0;
let failed = 0;
function check(label, ok, detail = '') {
  if (ok) passed += 1;
  else failed += 1;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${detail ? ` — ${detail}` : ''}`);
}
async function must(label, promise) {
  const res = await promise;
  if (res.error) throw new Error(`${label}: ${res.error.message}`);
  return res.data;
}

const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});
const email = `person-parity-${Date.now()}@accounic.test`;
const password = `Parity-${Math.random().toString(36).slice(2)}-9!`;
const created = await admin.auth.admin.createUser({
  email,
  password,
  email_confirm: true,
  user_metadata: { name: 'Parity Check', currency: 'INR' },
});
if (created.error) throw created.error;
const userId = created.data.user.id;

const api = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
  auth: { persistSession: false },
});
await must('sign in', api.auth.signInWithPassword({ email, password }));

const today = new Date().toISOString().slice(0, 10);
// Then: 1 AED = ₹22.50. Now (the cache): 1 INR = 0.0380 AED, so 1 AED ≈ ₹26.32.
const AED_PER_INR_THEN_E9 = 44_444_444; // account (AED) per entry (INR)
const INR_PER_AED_THEN_E9 = 22_500_000_000; // account (INR) per entry (AED)

try {
  await must(
    'rates',
    api.rpc('upsert_exchange_rates', {
      p_base: 'INR',
      p_rates: { AED: 0.038, INR: 1 },
      p_as_of: today,
      p_source: 'smoke',
    }),
  );

  // An account kept in dirhams, carried in with a rupee opening balance.
  const dubai = await must(
    'dubai',
    api.rpc('create_person', {
      p_name: 'Dubai Traders',
      p_type: 'business',
      p_currency: 'AED',
      p_opening_direction: 'they_owe_me',
      p_opening_date: '2026-01-01',
      p_opening_entered_minor: 5_000_000,
      p_opening_entered_currency: 'INR',
      p_opening_rate_e9: AED_PER_INR_THEN_E9,
      p_opening_rate_source: 'smoke',
    }),
  );
  // A rupee account, carried in with a dirham opening balance.
  const mumbai = await must(
    'mumbai',
    api.rpc('create_person', {
      p_name: 'Mumbai Supplier',
      p_type: 'business',
      p_currency: 'INR',
      p_opening_direction: 'i_owe_them',
      p_opening_date: '2026-01-01',
      p_opening_entered_minor: 30_000,
      p_opening_entered_currency: 'AED',
      p_opening_rate_e9: INR_PER_AED_THEN_E9,
      p_opening_rate_source: 'smoke',
    }),
  );

  const txn = (person, type, date, note, extra) =>
    must(
      note,
      api.rpc('create_transaction', {
        p_person_id: person,
        p_type: type,
        p_date: date,
        p_description: note,
        ...extra,
      }),
    );

  await txn(dubai.id, 'credit', '2026-01-15', 'rupees at the old rate', {
    p_entered_amount_minor: 10_000_000,
    p_entered_currency: 'INR',
    p_exchange_rate_e9: AED_PER_INR_THEN_E9,
    p_rate_source: 'smoke',
  });
  await txn(dubai.id, 'debit', '2026-02-01', 'dirhams, native', { p_amount_minor: 100_000 });
  await txn(mumbai.id, 'credit', '2026-01-20', 'dirhams at the old rate', {
    p_entered_amount_minor: 200_000,
    p_entered_currency: 'AED',
    p_exchange_rate_e9: INR_PER_AED_THEN_E9,
    p_rate_source: 'smoke',
  });
  await txn(mumbai.id, 'debit', '2026-02-10', 'rupees, native', { p_amount_minor: 1_000_000 });
  await must(
    'settlement',
    api.rpc('create_settlement', {
      p_person_id: mumbai.id,
      p_amount_minor: 2_000_000,
      p_direction: 'in',
      p_date: '2026-03-05',
      p_note: 'part paid',
    }),
  );
  await must(
    'transfer',
    api.rpc('create_transfer', {
      p_from_person_id: mumbai.id,
      p_to_person_id: dubai.id,
      p_amount_minor: 500_000,
      p_currency: 'INR',
      p_date: '2026-03-01',
      p_note: 'moved across',
      p_exchange_rate_e9: AED_PER_INR_THEN_E9,
      p_rate_source: 'smoke',
    }),
  );
  check('scenario recorded', true, 'old-rate entries, openings, settlement, transfer');

  // 1. Every person, summed, is the dashboard.
  try {
    const out = execFileSync('node', [join(here, 'person-dashboard-parity.mjs'), userId], {
      encoding: 'utf8',
    });
    check('person pages sum to the dashboard exactly', true, out.trim().split('\n').at(-2));
  } catch (e) {
    check('person pages sum to the dashboard exactly', false, `${e.stdout ?? e.message}`);
  }

  // 2. The dirham account's workspace figure.
  const page = await must('person_page', api.rpc('person_page', { p_person_id: dubai.id }));
  const rows = page.regular_by_currency;
  const inr = rows.find((r) => r.currency === 'INR');
  const aed = rows.find((r) => r.currency === 'AED');
  check(
    'dirham account holds a rupee row and a dirham row',
    !!inr && !!aed,
    rows.map((r) => `${r.currency} ${r.net}`).join(', '),
  );
  const transferLeg = (page.timeline ?? []).find((t) => t.transfer_role);
  const sign = transferLeg?.entry_type === 'debit' ? -1 : 1;
  const entered = 10_000_000 + sign * 500_000; // the rupees typed, both entries
  check('rupee row is the rupees entered, not a conversion', Number(inr?.net) === entered, `${inr?.net}`);
  const shown = Number(inr.net) + Number(aed.net_base_minor);
  check(
    "workspace figure is not the old whole-position today's-rate figure",
    shown !== Number(page.regular.position_base),
    `old ${page.regular.position_base} vs now ${shown}`,
  );
  const obc = page.opening_by_currency;
  check(
    'opening book keeps its rupees too',
    obc.length === 1 && obc[0].currency === 'INR' && Number(obc[0].net) === 5_000_000,
    obc.map((r) => `${r.currency} ${r.net}`).join(', '),
  );

  if (dumpDir) {
    mkdirSync(dumpDir, { recursive: true });
    const me = await must('me', api.rpc('me'));
    for (const [slug, id] of [
      ['dubai', dubai.id],
      ['mumbai', mumbai.id],
    ]) {
      const p = await must('page', api.rpc('person_page', { p_person_id: id, p_limit: 100 }));
      writeFileSync(join(dumpDir, `${slug}.json`), JSON.stringify(p, null, 1));
    }
    writeFileSync(join(dumpDir, 'me.json'), JSON.stringify(me, null, 1));
    writeFileSync(
      join(dumpDir, 'dashboard.json'),
      JSON.stringify(await must('dashboard', api.rpc('dashboard')), null, 1),
    );
    console.log(`dumped to ${dumpDir}`);
  }
} finally {
  const del = await admin.auth.admin.deleteUser(userId);
  check('throwaway user deleted', !del.error, del.error?.message);
}
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
