/**
 * Query benchmark (db/tools/bench.mjs).
 *
 * context.md §23 asks for measurement rather than guesswork. This times the
 * screen-level queries as the app actually issues them — one RPC per screen,
 * under a real user's RLS context — and reports the median and p95 of N runs.
 *
 *   node db/tools/bench.mjs [runs]
 */

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');
const runs = Number(process.argv[2] ?? 30);

function connectionString() {
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;
  const envFile = readFileSync(join(repoRoot, 'web', '.env.local'), 'utf8');
  const match = envFile.match(/^DATABASE_URL=(.+)$/m);
  if (!match) throw new Error('DATABASE_URL not found');
  return match[1].trim();
}

const client = new pg.Client({
  connectionString: connectionString(),
  ssl: { rejectUnauthorized: false },
});
await client.connect();

const { rows: users } = await client.query(
  `select id from auth.users where email = 'demo@example.com'`,
);
if (users.length === 0) throw new Error('Seed data not loaded — run: node db/tools/run-sql.mjs seed');
const ownerId = users[0].id;

const { rows: people } = await client.query(
  `select id from public.people where owner_id = $1 order by created_at limit 1`,
  [ownerId],
);
const personId = people[0].id;

/**
 * Impersonate the user exactly as PostgREST does, so RLS is inside the
 * measurement, and report the server's own execution time.
 *
 * Wall-clock from here would be ~150 ms for everything, because a hosted
 * database is a round trip away and the round trip dwarfs the query. EXPLAIN
 * ANALYZE reports what the server actually spent, which is the number worth
 * optimising.
 */
async function asUser(sql, params = []) {
  await client.query('begin');
  await client.query(`select set_config('request.jwt.claims', $1, true)`, [
    JSON.stringify({ sub: ownerId, role: 'authenticated' }),
  ]);
  await client.query('set local role authenticated');

  const { rows } = await client.query(
    `explain (analyze, buffers, format json) ${sql}`,
    params,
  );
  const plan = rows[0]['QUERY PLAN'][0];

  await client.query('rollback');
  return plan['Execution Time'] + plan['Planning Time'];
}

const cases = [
  { name: 'dashboard()        whole screen, one call', sql: 'select public.dashboard(12, 8)' },
  { name: 'person_page()      balance + timeline + open txns', sql: 'select public.person_page($1, 30, 0)', params: [personId] },
  { name: 'person_balances    full people list', sql: 'select * from public.person_balances where not is_archived order by name' },
  { name: 'activity_page()    paginated feed', sql: 'select public.activity_page(40, 0, null, null, null)' },
  { name: "search_all()       global search", sql: `select public.search_all('rah', 8)` },
  { name: 'owner_summary      headline totals', sql: 'select * from public.owner_summary' },
];

const quantile = (sorted, q) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * q))];

console.log(`\nServer time in ms (planning + execution), ${runs} runs each, under RLS.`);
console.log('Seeded demo workspace: 6 people, 10 transactions, 4 settlements.\n');
console.log('query'.padEnd(46) + 'median'.padStart(10) + 'p95'.padStart(10) + 'max'.padStart(10));
console.log('-'.repeat(76));

for (const testCase of cases) {
  const timings = [];
  await asUser(testCase.sql, testCase.params); // warm the plan cache
  for (let i = 0; i < runs; i++) timings.push(await asUser(testCase.sql, testCase.params));
  timings.sort((a, b) => a - b);

  const fmt = (n) => `${n.toFixed(2)}`.padStart(10);
  console.log(
    testCase.name.padEnd(46) +
      fmt(quantile(timings, 0.5)) +
      fmt(quantile(timings, 0.95)) +
      fmt(timings[timings.length - 1]),
  );
}

console.log(
  '\nServer time only. Add one network round trip per screen for what the user' +
    '\nexperiences - which is why each screen is a single RPC.\n',
);

await client.end();
