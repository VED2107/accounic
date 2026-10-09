// Person Details = Dashboard, checked against the live database.
//
//   node db/tools/person-dashboard-parity.mjs <owner-uuid> [...]
//
// Read-only: every query runs as the owner (RLS applies) inside a transaction
// that is rolled back. For each owner it checks:
//
//   1. Summing every person's person_page().regular_by_currency /
//      opening_by_currency per currency gives EXACTLY the dashboard's
//      totals_by_currency[i].cash / .opening — credit, debit, settled,
//      receivable, payable, net. The person screen and the dashboard read
//      one set of figures, not two.
//   2. Each person's workspace-currency figure — the one the person page and
//      both statements now print (positionInBase) — is EXACTLY the figure the
//      dashboard counts for that account (person_balances.cash_in_hand_base /
//      opening_net_base), and summed over the workspace is the dashboard's
//      "Total in" line. Every account where v1.16's per-currency re-sum
//      disagreed with the dashboard is printed, so the fix is visible on real
//      data.
import { readFileSync } from 'node:fs';
import pg from 'pg';

const url = readFileSync(new URL('../../web/.env.local', import.meta.url), 'utf8')
  .match(/^DATABASE_URL=(.+)$/m)[1].trim();
const owners = process.argv.slice(2);
if (owners.length === 0) {
  console.error('usage: node db/tools/person-dashboard-parity.mjs <owner-uuid> [...]');
  process.exit(2);
}

const positionInBase = (split, ledger, base) =>
  ledger === base ? Number(split.position) : split.position_base == null ? null : Number(split.position_base);
const oldWorkspaceTotal = (rows, ledger, base) =>
  rows.reduce(
    (t, r) =>
      t + (r.currency === base ? Number(r.net) : ledger === base ? Number(r.net_ledger_minor) : Number(r.net_base_minor)),
    0,
  );
const KEYS = ['credit', 'debit', 'settled', 'receivable', 'payable', 'net'];

let failures = 0;
const c = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
await c.connect();
for (const owner of owners) {
  await c.query('begin');
  await c.query(`select set_config('request.jwt.claims', $1, true)`, [
    JSON.stringify({ sub: owner, role: 'authenticated' }),
  ]);
  await c.query('set local role authenticated');

  const dash = (await c.query('select public.dashboard() d')).rows[0].d;
  const base = dash.base_currency;
  const people = (await c.query('select id, name from public.people order by name')).rows;

  const sums = { cash: {}, opening: {} };
  let diverged = 0;
  let checks0 = 0;
  let checksP = 0;
  let cashTotal = 0;
  let openingTotal = 0;
  for (const p of people) {
    const page = (await c.query('select public.person_page($1) j', [p.id])).rows[0].j;
    for (const [half, rows] of [['cash', page.regular_by_currency], ['opening', page.opening_by_currency]]) {
      for (const r of rows) {
        const acc = (sums[half][r.currency] ??= Object.fromEntries(KEYS.map((k) => [k, 0])));
        for (const k of KEYS) acc[k] += Number(r[k]);
      }
    }
    // 0033: the booked figures of the rows ARE the headline — no rate in them.
    for (const [label, rows, position] of [
      ['cash', page.regular_by_currency, page.regular.position],
      ['opening', page.opening_by_currency, page.opening_position.position],
    ]) {
      const booked = rows.reduce((t, r) => t + Number(r.net_ledger_minor ?? NaN), 0);
      checks0++;
      if (rows.length > 0 && booked !== Number(position)) {
        failures++;
        console.log(`  FAIL ${p.name} ${label}: rows booked ${booked} vs headline ${position}`);
      }
    }
    const bal = (
      await c.query(
        'select cash_in_hand_base, opening_net_base from public.person_balances where person_id = $1',
        [p.id],
      )
    ).rows[0];
    for (const [label, split, want] of [
      ['cash', page.regular, bal.cash_in_hand_base],
      ['opening', page.opening_position, bal.opening_net_base],
    ]) {
      const shown = positionInBase(split, page.currency, base);
      checksP++;
      if (shown !== (want == null ? null : Number(want))) {
        failures++;
        console.log(`  FAIL ${p.name} ${label}: person ${shown} vs dashboard ${want}`);
      }
      if (label === 'cash') {
        cashTotal += shown ?? 0;
        const old = oldWorkspaceTotal(page.regular_by_currency, page.currency, base);
        if (page.regular_by_currency.length > 0 && old !== shown) {
          diverged++;
          console.log(`  ${p.name} (${page.currency}): v1.16 showed ${old}, dashboard and now person ${shown}`);
        }
      } else openingTotal += shown ?? 0;
    }
  }
  for (const [label, sum, want] of [
    ['cash in hand', cashTotal, dash.cash_in_hand.position],
    ['opening', openingTotal, dash.opening.position],
  ]) {
    checksP++;
    if (sum !== Number(want)) {
      failures++;
      console.log(`  FAIL Σ ${label}: persons ${sum} vs dashboard ${want}`);
    }
  }

  let checks = 0;
  for (const t of dash.totals_by_currency) {
    for (const half of ['cash', 'opening']) {
      const d = t[half];
      if (!d) continue;
      const s = sums[half][t.currency] ?? Object.fromEntries(KEYS.map((k) => [k, 0]));
      for (const k of KEYS) {
        checks++;
        if (Number(d[k]) !== s[k]) {
          failures++;
          console.log(`  FAIL ${t.currency}.${half}.${k}: dashboard ${d[k]} vs persons ${s[k]}`);
        }
      }
    }
  }
  console.log(
    `${owner}: ${people.length} people, ${checks} dashboard-vs-person checks, ` +
      `${checks0} booked-vs-headline checks, ${checksP} person-vs-dashboard figure checks, ` +
      `${diverged} v1.16 figures corrected`,
  );
  await c.query('rollback');
}
await c.end();
if (failures) {
  console.log(`${failures} FAILED`);
  process.exit(1);
}
console.log('OK — person pages and their workspace figures are exactly the dashboard figures.');
