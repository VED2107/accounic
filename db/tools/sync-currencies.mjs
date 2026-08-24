/**
 * Regenerates every copy of the currency list from shared/currencies.json.
 *
 *   node db/tools/sync-currencies.mjs          # rewrite the generated blocks
 *   node db/tools/sync-currencies.mjs --check  # fail if any copy is stale
 *
 * There are four copies because there are four runtimes that need the list
 * without a network call: Postgres, the web client, the Flutter client, and the
 * test suites that pin them together. Only this script writes them, and only
 * shared/currencies.json is edited by hand (upgrade §19).
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..', '..');
const check = process.argv.includes('--check');

const { currencies } = JSON.parse(readFileSync(join(root, 'shared', 'currencies.json'), 'utf8'));

const sqlLiteral = (value) => `'${String(value).replace(/'/g, "''")}'`;
const tsLiteral = (value) => `'${String(value).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
// Dart interpolates on a bare $, so a dollar sign in a symbol has to be escaped
// or the generated file does not compile — 'A$' is a syntax error, 'A\$' is not.
const dartLiteral = (value) => `'${String(tsLiteral(value)).slice(1, -1).replace(/\$/g, '\\$')}'`;

/* -------------------------------------------------------------------------- */

const sqlBlock = [
  'insert into public.currencies (code, name, symbol, decimals) values',
  currencies
    .map(
      (c) =>
        `  (${sqlLiteral(c.code)}, ${sqlLiteral(c.name)}, ${sqlLiteral(c.symbol)}, ${c.decimals})`,
    )
    .join(',\n'),
  'on conflict (code) do update',
  '  set name      = excluded.name,',
  '      symbol    = excluded.symbol,',
  '      decimals  = excluded.decimals,',
  '      is_active = true;',
].join('\n');

const tsBlock = currencies
  .map(
    (c) =>
      `  { code: ${tsLiteral(c.code)}, name: ${tsLiteral(c.name)}, ` +
      `symbol: ${tsLiteral(c.symbol)}, decimals: ${c.decimals} },`,
  )
  .join('\n');

const dartBlock = currencies
  .map(
    (c) =>
      `  Currency(${dartLiteral(c.code)}, ${dartLiteral(c.name)}, ` +
      `${dartLiteral(c.symbol)}, ${c.decimals}),`,
  )
  .join('\n');

/* -------------------------------------------------------------------------- */

const targets = [
  {
    path: join(root, 'db', 'migrations', '0010_currency.sql'),
    start: '-- @@CURRENCY_SEED_START@@',
    end: '-- @@CURRENCY_SEED_END@@',
    body: sqlBlock,
  },
  {
    path: join(root, 'web', 'src', 'lib', 'currencies.ts'),
    start: '// @@CURRENCY_LIST_START@@',
    end: '// @@CURRENCY_LIST_END@@',
    body: tsBlock,
  },
  {
    path: join(root, 'app', 'lib', 'core', 'currencies.dart'),
    start: '// @@CURRENCY_LIST_START@@',
    end: '// @@CURRENCY_LIST_END@@',
    body: dartBlock,
  },
];

let stale = 0;

for (const target of targets) {
  const source = readFileSync(target.path, 'utf8');
  const startAt = source.indexOf(target.start);
  const endAt = source.indexOf(target.end);
  if (startAt < 0 || endAt < 0) {
    throw new Error(`Markers not found in ${target.path}`);
  }

  const head = source.slice(0, startAt + target.start.length);
  const tail = source.slice(endAt);
  const next = `${head}\n${target.body}\n${tail}`;

  if (next === source) {
    console.log(`ok    ${target.path.replace(root, '.')}`);
    continue;
  }
  stale += 1;
  if (check) {
    console.log(`STALE ${target.path.replace(root, '.')}`);
  } else {
    writeFileSync(target.path, next);
    console.log(`wrote ${target.path.replace(root, '.')}`);
  }
}

if (check && stale > 0) {
  console.error(`\n${stale} generated currency list(s) are out of date. Run: node db/tools/sync-currencies.mjs`);
  process.exit(1);
}
console.log(`\n${currencies.length} currencies.`);
