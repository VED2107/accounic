/**
 * Person Details = Dashboard = Person statement, end to end
 * (db/tools/smoke-person-parity.mjs).
 *
 *   node db/tools/smoke-person-parity.mjs [dump-dir] [--fixtures]
 *
 * Builds a throwaway INR workspace whose history was entered at rates that are
 * NOT today's (1 AED = ₹22.50 and ₹24.00 then, ₹26.32 in the cache now) and
 * covers every shape the brief names:
 *
 *   Dubai Traders    kept in AED: rupee and dirham entries, a rupee opening
 *                    balance, a manual conversion, a partial settlement paid
 *                    in rupees, and the receiving leg of a transfer.
 *   Mumbai Supplier  kept in INR: dirham entries at two historical rates, a
 *                    manual conversion, a dirham opening balance, a partial
 *                    settlement, and the sending leg of the transfer.
 *   Gulf Settled     kept in AED: AED 10,000 owed, paid back as ₹2,25,000 at
 *                    the day's ₹22.50. The ledger reads exactly zero.
 *
 * Then, numerically:
 *
 *   * every person's per-currency rows, summed, equal dashboard()'s
 *     totals_by_currency exactly (person-dashboard-parity.mjs);
 *   * each person's workspace-currency figure (positionInBase — the person
 *     page and both statements) equals the figure the dashboard counts for that
 *     account, and summed over the workspace equals the dashboard's "Total in"
 *     lines for cash in hand and for the opening book;
 *   * Gulf Settled reads zero — where the v1.16 per-currency re-sum invented a
 *     balance out of the rate movement (the bug this was rewritten for);
 *   * a rupee account sums the rupees its dirham entries were BOOKED at.
 *
 * With a dump dir, writes each person_page() JSON there; with --fixtures, also
 * rewrites shared/fixtures/, which drive the parity tests in both clients and
 * the statement check (db/tools/verify-statement-pdfs.mjs). Creates its own
 * user and deletes it again.
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
const args = process.argv.slice(2);
const writeFixtures = args.includes('--fixtures');
const dumpArg = args.find((a) => !a.startsWith('--'));
const dumpDir = dumpArg ? resolve(dumpArg) : null;
const fixturesDir = join(here, '..', '..', 'shared', 'fixtures');

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
// Then: 1 AED = ₹22.50, later ₹24.00. Now (the cache): 1 INR = 0.0380 AED,
// so 1 AED ≈ ₹26.32.
const AED_PER_INR_2250_E9 = 44_444_444; // account (AED) per entry (INR)
const AED_PER_INR_2400_E9 = 41_666_667;
const INR_PER_AED_2250_E9 = 22_500_000_000; // account (INR) per entry (AED)
const INR_PER_AED_2400_E9 = 24_000_000_000;

/** The person page's workspace-currency figure: twin of positionInBase. */
const positionInBase = (split, ledger, base) =>
  ledger === base
    ? Number(split.position)
    : split.position_base == null
      ? null
      : Number(split.position_base);

/** What v1.16 showed instead: the per-currency rows re-summed. */
const oldWorkspaceTotal = (rows, ledger, base) =>
  rows.reduce(
    (t, r) =>
      t +
      (r.currency === base
        ? Number(r.net)
        : ledger === base
          ? Number(r.net_ledger_minor)
          : Number(r.net_base_minor)),
    0,
  );

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
      p_opening_rate_e9: AED_PER_INR_2250_E9,
      p_opening_rate_source: 'smoke',
    }),
  );
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
      p_opening_rate_e9: INR_PER_AED_2250_E9,
      p_opening_rate_source: 'smoke',
    }),
  );
  const gulf = await must(
    'gulf',
    api.rpc('create_person', { p_name: 'Gulf Settled', p_type: 'person', p_currency: 'AED' }),
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

  // Dubai Traders (AED).
  await txn(dubai.id, 'credit', '2026-01-15', 'rupees at 22.50', {
    p_entered_amount_minor: 10_000_000,
    p_entered_currency: 'INR',
    p_exchange_rate_e9: AED_PER_INR_2250_E9,
    p_rate_source: 'smoke',
  });
  await txn(dubai.id, 'credit', '2026-01-25', 'rupees, manual AED 2,600', {
    p_entered_amount_minor: 6_000_000,
    p_entered_currency: 'INR',
    p_exchange_rate_e9: AED_PER_INR_2400_E9,
    p_rate_source: 'smoke',
    p_converted_amount_minor: 260_000,
    p_conversion_mode: 'manual',
  });
  await txn(dubai.id, 'debit', '2026-02-01', 'dirhams, native', { p_amount_minor: 100_000 });
  await must(
    'dubai part paid in rupees',
    api.rpc('create_settlement', {
      p_person_id: dubai.id,
      p_direction: 'in',
      p_date: '2026-02-20',
      p_note: 'part paid in rupees at 24.00',
      p_entered_amount_minor: 2_000_000,
      p_entered_currency: 'INR',
      p_exchange_rate_e9: AED_PER_INR_2400_E9,
      p_rate_source: 'smoke',
    }),
  );

  // Mumbai Supplier (INR).
  await txn(mumbai.id, 'credit', '2026-01-20', 'dirhams at 22.50', {
    p_entered_amount_minor: 200_000,
    p_entered_currency: 'AED',
    p_exchange_rate_e9: INR_PER_AED_2250_E9,
    p_rate_source: 'smoke',
  });
  await txn(mumbai.id, 'credit', '2026-02-05', 'dirhams at 24.00', {
    p_entered_amount_minor: 50_000,
    p_entered_currency: 'AED',
    p_exchange_rate_e9: INR_PER_AED_2400_E9,
    p_rate_source: 'smoke',
  });
  await txn(mumbai.id, 'credit', '2026-02-07', 'dirhams, manual 2,700 rupees', {
    p_entered_amount_minor: 10_000,
    p_entered_currency: 'AED',
    p_exchange_rate_e9: INR_PER_AED_2400_E9,
    p_rate_source: 'smoke',
    p_converted_amount_minor: 270_000,
    p_conversion_mode: 'manual',
  });
  await txn(mumbai.id, 'debit', '2026-02-10', 'rupees, native', { p_amount_minor: 1_000_000 });
  await must(
    'mumbai part paid',
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
      p_exchange_rate_e9: AED_PER_INR_2250_E9,
      p_rate_source: 'smoke',
    }),
  );

  // Gulf Settled (AED): owed AED 10,000, repaid as ₹2,25,000 at ₹22.50.
  await txn(gulf.id, 'debit', '2026-01-10', 'dirhams borrowed', { p_amount_minor: 1_000_000 });
  await txn(gulf.id, 'credit', '2026-01-12', 'repaid in rupees at 22.50', {
    p_entered_amount_minor: 22_500_000,
    p_entered_currency: 'INR',
    p_exchange_rate_e9: AED_PER_INR_2250_E9,
    p_rate_source: 'smoke',
  });
  check('scenario recorded', true, 'historical + manual rates, openings, settlements, transfer');

  // 1. Every person's per-currency rows, summed, are the dashboard's.
  try {
    const out = execFileSync('node', [join(here, 'person-dashboard-parity.mjs'), userId], {
      encoding: 'utf8',
    });
    check('per-currency rows sum to the dashboard exactly', true, out.trim().split('\n').at(-2));
  } catch (e) {
    check('per-currency rows sum to the dashboard exactly', false, `${e.stdout ?? e.message}`);
  }

  // 2. Each account's workspace figure IS the dashboard's.
  const dash = await must('dashboard', api.rpc('dashboard', { p_people_limit: 50 }));
  const base = dash.base_currency;
  const balances = await must(
    'person_balances',
    api.from('person_balances').select('person_id, name, cash_in_hand_base, opening_net_base'),
  );
  const pages = {};
  for (const [slug, id] of [
    ['dubai', dubai.id],
    ['mumbai', mumbai.id],
    ['gulf', gulf.id],
  ]) {
    pages[slug] = await must('page', api.rpc('person_page', { p_person_id: id, p_limit: 100 }));
  }
  let cashSum = 0;
  let openingSum = 0;
  const figures = {};
  for (const page of Object.values(pages)) {
    const b = balances.find((r) => r.person_id === page.person.id);
    const cash = positionInBase(page.regular, page.currency, base);
    const opening = positionInBase(page.opening_position, page.currency, base);
    cashSum += cash;
    openingSum += opening;
    figures[page.person.name] = {
      cash_in_hand_base: Number(b.cash_in_hand_base),
      opening_net_base: Number(b.opening_net_base),
    };
    check(
      `${page.person.name}: cash in hand = dashboard's figure`,
      cash === Number(b.cash_in_hand_base),
      `person ${cash} / dashboard ${b.cash_in_hand_base}`,
    );
    check(
      `${page.person.name}: opening = dashboard's figure`,
      opening === Number(b.opening_net_base),
      `person ${opening} / dashboard ${b.opening_net_base}`,
    );
  }
  check(
    'Σ person cash in hand = dashboard Total in INR',
    cashSum === Number(dash.cash_in_hand.position),
    `${cashSum} / ${dash.cash_in_hand.position}`,
  );
  check(
    'Σ person opening = dashboard opening Total in INR',
    openingSum === Number(dash.opening.position),
    `${openingSum} / ${dash.opening.position}`,
  );

  // 3. The account settled in rupees is settled — the reported bug.
  const g = pages.gulf;
  check('Gulf Settled ledger reads zero', Number(g.regular.position) === 0, `${g.regular.position}`);
  check('Gulf Settled shows ₹0', positionInBase(g.regular, 'AED', base) === 0);
  const phantom = oldWorkspaceTotal(g.regular_by_currency, 'AED', base);
  check('v1.16 re-sum invented a balance here (bug reproduced)', phantom !== 0, `${phantom}`);

  // 4. A rupee account holds its dirham entries at the rupees BOOKED:
  //    AED 2,000 at 22.50 + AED 500 at 24.00 + AED 100 manual ₹2,700.
  const m = pages.mumbai;
  const mAed = m.regular_by_currency.find((r) => r.currency === 'AED');
  check(
    'Mumbai dirham row: entered AED 2,600, booked at the old rates (not today)',
    Number(mAed.credit) === 260_000 && Number(mAed.net_ledger_minor) !== Number(mAed.net_base_minor),
    `credit AED ${mAed.credit}, booked net ₹${mAed.net_ledger_minor}, today ₹${mAed.net_base_minor}`,
  );
  const mBooked = m.timeline
    .filter((t) => t.entry_kind === 'transaction' && t.entry_currency === 'AED' && !t.is_void)
    .reduce((t, r) => t + Number(r.amount_minor), 0);
  check('Mumbai dirham entries booked ₹59,700 (45,000 + 12,000 + manual 2,700)', mBooked === 5_970_000, `${mBooked}`);
  check(
    'Mumbai figure = its INR headline',
    positionInBase(m.regular, 'INR', base) === Number(m.regular.position),
  );

  // 5. Dubai: the AED position is the sum of what each entry booked.
  const d = pages.dubai;
  const dInr = d.regular_by_currency.find((r) => r.currency === 'INR');
  const dAed = d.regular_by_currency.find((r) => r.currency === 'AED');
  check(
    'Dubai position = Σ booked per-currency figures',
    Number(dInr.net_ledger_minor) + Number(dAed.net_ledger_minor) === Number(d.regular.position),
    `${dInr.net_ledger_minor} + ${dAed.net_ledger_minor} = ${d.regular.position}`,
  );
  const manual = d.timeline.find((t) => t.conversion_mode === 'manual');
  check('Dubai manual conversion kept as entered', Number(manual?.amount_minor) === 260_000);

  const names = {
    dubai: 'person-page-aed-ledger',
    mumbai: 'person-page-inr-ledger',
    gulf: 'person-page-aed-settled',
  };
  const dashboardFigures = {
    base_currency: base,
    cash_in_hand: Number(dash.cash_in_hand.position),
    opening: Number(dash.opening.position),
    people: figures,
  };
  for (const dir of [dumpDir, writeFixtures ? fixturesDir : null].filter(Boolean)) {
    mkdirSync(dir, { recursive: true });
    for (const [slug, page] of Object.entries(pages)) {
      writeFileSync(join(dir, `${names[slug]}.json`), JSON.stringify(page, null, 1) + '\n');
    }
    writeFileSync(
      join(dir, 'dashboard-figures.json'),
      JSON.stringify(dashboardFigures, null, 1) + '\n',
    );
    console.log(`wrote ${dir}`);
  }
} finally {
  const del = await admin.auth.admin.deleteUser(userId);
  check('throwaway user deleted', !del.error, del.error?.message);
}
console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
