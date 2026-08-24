/**
 * Data-safety snapshot (context.md §26; upgrade requirement §21).
 *
 * Counts and checksums the rows that must survive a migration, so "nothing was
 * deleted" is a comparison rather than a claim. Run it before and after:
 *
 *   node db/tools/snapshot.mjs before
 *   node db/tools/snapshot.mjs after
 *   node db/tools/snapshot.mjs diff
 *
 * Snapshots are written next to this file as snapshot-<label>.json.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');

function connectionString() {
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;
  const envFile = readFileSync(join(repoRoot, 'web', '.env.local'), 'utf8');
  const match = envFile.match(/^DATABASE_URL=(.+)$/m);
  if (!match) throw new Error('DATABASE_URL not found.');
  return match[1].trim().replace(/^["']|["']$/g, '');
}

const QUERIES = {
  users: 'select count(*)::int as n from auth.users',
  profiles: 'select count(*)::int as n from public.profiles',
  people: 'select count(*)::int as n from public.people',
  transactions: 'select count(*)::int as n from public.transactions',
  settlements: 'select count(*)::int as n from public.settlements',
  admins: 'select count(*)::int as n from public.app_admins',
  txn_amount_sum: 'select coalesce(sum(amount_minor),0)::text as n from public.transactions where not is_void',
  settle_amount_sum: 'select coalesce(sum(amount_minor),0)::text as n from public.settlements where not is_void',
};

async function snapshot(label) {
  const client = new pg.Client({ connectionString: connectionString() });
  await client.connect();
  const out = { label, taken_at: new Date().toISOString(), counts: {} };
  for (const [key, sql] of Object.entries(QUERIES)) {
    const { rows } = await client.query(sql);
    out.counts[key] = rows[0].n;
  }
  // Per-person balance fingerprint: id -> net_balance. Any change here is a
  // change to somebody's money, which is the thing that must not happen.
  const { rows } = await client.query(
    'select person_id::text as id, net_balance::text as net from public.person_balances order by person_id',
  );
  out.balances = Object.fromEntries(rows.map((r) => [r.id, r.net]));
  await client.end();

  const path = join(here, `snapshot-${label}.json`);
  writeFileSync(path, JSON.stringify(out, null, 2));
  console.log(`snapshot "${label}" written to ${path}`);
  console.table(out.counts);
  console.log(`people with a balance row: ${Object.keys(out.balances).length}`);
}

function diff() {
  const a = JSON.parse(readFileSync(join(here, 'snapshot-before.json'), 'utf8'));
  const b = JSON.parse(readFileSync(join(here, 'snapshot-after.json'), 'utf8'));

  let failed = false;
  for (const key of Object.keys(a.counts)) {
    const before = a.counts[key];
    const after = b.counts[key];
    const ok = String(before) === String(after);
    if (!ok) failed = true;
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${key}: ${before} -> ${after}`);
  }

  const missing = Object.keys(a.balances).filter((id) => !(id in b.balances));
  const changed = Object.keys(a.balances).filter(
    (id) => id in b.balances && a.balances[id] !== b.balances[id],
  );
  if (missing.length) {
    failed = true;
    console.log(`FAIL ${missing.length} person id(s) disappeared: ${missing.join(', ')}`);
  } else {
    console.log('ok   every person id still present');
  }
  if (changed.length) {
    failed = true;
    for (const id of changed) {
      console.log(`FAIL balance changed for ${id}: ${a.balances[id]} -> ${b.balances[id]}`);
    }
  } else {
    console.log('ok   every net balance unchanged');
  }

  if (failed) {
    console.error('\nDATA SAFETY CHECK FAILED — do not release.');
    process.exit(1);
  }
  console.log('\nData safety check passed: nothing was lost or altered.');
}

const mode = process.argv[2] ?? 'before';
if (mode === 'diff') {
  if (!existsSync(join(here, 'snapshot-before.json'))) {
    console.error('No before snapshot. Run: node db/tools/snapshot.mjs before');
    process.exit(1);
  }
  diff();
} else {
  await snapshot(mode);
}
