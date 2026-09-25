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
//   2. The workspace-currency figure each person screen now shows
//      (workspaceTotal over its rows) keeps workspace-currency entries at their
//      entered value — it is compared with the old whole-position
//      today's-rate figure and every divergence is printed, so the fix is
//      visible on real data.
import { readFileSync } from 'node:fs';
import pg from 'pg';

const url = readFileSync(new URL('../../web/.env.local', import.meta.url), 'utf8')
  .match(/^DATABASE_URL=(.+)$/m)[1].trim();
const owners = process.argv.slice(2);
if (owners.length === 0) {
  console.error('usage: node db/tools/person-dashboard-parity.mjs <owner-uuid> [...]');
  process.exit(2);
}

const workspaceTotal = (rows, base) => {
  let t = 0;
  for (const r of rows) {
    if (r.currency === base) t += Number(r.net);
    else if (Number(r.net) === 0) continue;
    else if (r.net_base_minor == null) return null;
    else t += Number(r.net_base_minor);
  }
  return t;
};
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
    if (page.currency !== base && Number(page.regular.position) !== 0) {
      const now = workspaceTotal(page.regular_by_currency, base);  // ledger != base here: booked figures do not apply
      const old = page.regular.position_base == null ? null : Number(page.regular.position_base);
      if (now !== old) {
        diverged++;
        console.log(
          `  ${p.name} (${page.currency}): shown in ${base} was ${old} at today's rate, now ${now}` +
            ` [rows: ${page.regular_by_currency.map((r) => `${r.currency} ${r.net}`).join(', ')}]`,
        );
      }
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
      `${checks0} booked-vs-headline checks, ${diverged} headline figures corrected`,
  );
  await c.query('rollback');
}
await c.end();
if (failures) {
  console.log(`${failures} FAILED`);
  process.exit(1);
}
console.log('OK — person pages sum to the dashboard exactly.');
