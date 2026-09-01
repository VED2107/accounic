/**
 * Minimal SQL runner (db/tools/run-sql.mjs).
 *
 * There is no Supabase CLI or docker in this environment, so migrations are
 * applied over a plain Postgres connection instead. Each file is sent as ONE
 * statement batch, which matters: the migrations contain dollar-quoted function
 * bodies that a naive semicolon splitter would tear in half.
 *
 * Usage:
 *   node db/tools/run-sql.mjs migrate            # every file in migrations/
 *   node db/tools/run-sql.mjs file <path> [...]  # specific files, in order
 *   node db/tools/run-sql.mjs seed
 *   node db/tools/run-sql.mjs test
 *
 * Reads DATABASE_URL from web/.env.local (or the environment).
 */

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const here = dirname(fileURLToPath(import.meta.url));
const dbDir = resolve(here, '..');
const repoRoot = resolve(dbDir, '..');

function connectionString() {
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;
  try {
    const envFile = readFileSync(join(repoRoot, 'web', '.env.local'), 'utf8');
    const match = envFile.match(/^DATABASE_URL=(.+)$/m);
    if (match) return match[1].trim().replace(/^["']|["']$/g, '');
  } catch {
    /* fall through */
  }
  throw new Error('DATABASE_URL is not set and web/.env.local does not contain it.');
}

async function runFile(client, path) {
  const sql = readFileSync(path, 'utf8');
  const label = path.replace(repoRoot, '').replace(/\\/g, '/');
  process.stdout.write(`→ ${label}\n`);

  const notices = [];
  const onNotice = (n) => notices.push(n.message);
  client.on('notice', onNotice);

  try {
    await client.query(sql);
    const failures = notices.filter((m) => /^FAIL|SECURITY FAIL/.test(m));
    const oks = notices.filter((m) => m.startsWith('ok '));
    if (oks.length) process.stdout.write(`   ${oks.length} assertions passed\n`);
    for (const message of notices.filter((m) => m.includes('==='))) {
      process.stdout.write(`   ${message.trim()}\n`);
    }
    if (failures.length) {
      for (const f of failures) process.stdout.write(`   ${f}\n`);
      throw new Error(`${failures.length} assertion(s) failed in ${label}`);
    }
    process.stdout.write('   ok\n');
  } finally {
    client.off('notice', onNotice);
  }
}

const [, , command = 'migrate', ...rest] = process.argv;

const url = connectionString();

// Supabase is TLS-only; a throwaway Postgres in CI has no certificate at all.
// Decide from the URL rather than from an environment flag, so the same command
// works in both places without being told which one it is.
function sslFor(target) {
  if (/[?&]sslmode=disable/.test(target)) return false;
  try {
    const host = new URL(target).hostname;
    if (host === 'localhost' || host === '127.0.0.1' || host === '::1') return false;
  } catch {
    /* not a parseable URL — fall through to the secure default */
  }
  return { rejectUnauthorized: false };
}

const client = new pg.Client({
  connectionString: url,
  ssl: sslFor(url),
  // Supabase's pooler can be slow to hand out a session for DDL-heavy batches.
  statement_timeout: 120_000,
});

await client.connect();

try {
  if (command === 'migrate') {
    const dir = join(dbDir, 'migrations');
    for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
      await runFile(client, join(dir, file));
    }
  } else if (command === 'seed') {
    await runFile(client, join(dbDir, 'seed.sql'));
  } else if (command === 'test') {
    const dir = join(dbDir, 'tests');
    for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
      await runFile(client, join(dir, file));
    }
  } else if (command === 'file') {
    for (const path of rest) await runFile(client, resolve(process.cwd(), path));
  } else if (command === 'query') {
    const result = await client.query(rest.join(' '));
    console.log(JSON.stringify(result.rows, null, 2));
  } else {
    throw new Error(`Unknown command: ${command}`);
  }
  process.stdout.write('\nDone.\n');
} catch (error) {
  process.stderr.write(`\nFAILED: ${error.message}\n`);
  if (error.detail) process.stderr.write(`detail: ${error.detail}\n`);
  if (error.hint) process.stderr.write(`hint: ${error.hint}\n`);
  if (error.position) process.stderr.write(`position: ${error.position}\n`);
  // The PL/pgSQL call stack. Without it a failing assertion in a 300-line
  // suite says only what went wrong, never where, which is the difference
  // between a readable CI failure and a bisect.
  if (error.where) process.stderr.write(`where:
${error.where}
`);
  process.exitCode = 1;
} finally {
  await client.end();
}
