// Person statement = Dashboard, read back from the PDFs themselves.
//
//   PARITY_OUT=<dir> npx vitest run src/lib/pdf/person-parity.test.ts   (in web/)
//   PARITY_OUT=<dir> flutter test test/person_currency_parity_test.dart (in app/)
//   node db/tools/verify-statement-pdfs.mjs <dir>
//
// For each fixture in shared/fixtures (written by smoke-person-parity.mjs) and
// each client's statement of it, extracts the text with `pdftotext` and checks
// that the workspace-currency figure printed is the dashboard's own figure for
// that account — and, for the account settled in rupees, that the figure v1.16
// printed instead appears nowhere.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = process.argv[2];
if (!dir) {
  console.error('usage: node db/tools/verify-statement-pdfs.mjs <dir>');
  process.exit(2);
}
const fixtures = new URL('../../shared/fixtures/', import.meta.url);
const read = (name) => JSON.parse(readFileSync(new URL(name, fixtures), 'utf8'));
const dashboard = read('dashboard-figures.json');

/** Minor units as Indian-grouped rupees: 16491211 -> "1,64,912.11". */
function rupees(minor) {
  const abs = Math.abs(minor);
  const whole = String(Math.floor(abs / 100));
  const paise = String(abs % 100).padStart(2, '0');
  const last3 = whole.slice(-3);
  const rest = whole.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ',');
  return `${rest ? `${rest},` : ''}${last3}.${paise}`;
}
/** Matches the figure with or without a trailing ".00". */
const pattern = (minor) => {
  const s = rupees(minor).replace(/\./g, '\\.');
  return new RegExp(s.endsWith('\\.00') ? `${s.slice(0, -4)}(\\.00)?(?![\\d,])` : s);
};

let failures = 0;
let checks = 0;
const check = (label, ok, detail = '') => {
  checks++;
  if (!ok) failures++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${label}${detail ? ` — ${detail}` : ''}`);
};

for (const name of ['aed-ledger', 'inr-ledger', 'aed-settled']) {
  const page = read(`person-page-${name}.json`);
  const figures = dashboard.people[page.person.name];
  for (const client of ['web', 'flutter']) {
    const pdf = join(dir, `${client}-${name}.pdf`);
    if (!existsSync(pdf)) {
      check(`${client} ${name}: statement exists`, false, pdf);
      continue;
    }
    const text = execFileSync('pdftotext', ['-layout', pdf, '-'], { encoding: 'utf8' });
    // The headline in the account's own currency is the ledger position.
    if (page.currency === 'INR') {
      check(
        `${client} ${page.person.name}: headline = dashboard ₹${rupees(figures.cash_in_hand_base)}`,
        pattern(figures.cash_in_hand_base).test(text),
      );
    } else if (figures.cash_in_hand_base !== 0) {
      check(
        `${client} ${page.person.name}: workspace figure = dashboard ₹${rupees(figures.cash_in_hand_base)}`,
        pattern(figures.cash_in_hand_base).test(text),
      );
    }
    if (page.person.name === 'Gulf Settled') {
      check(
        `${client} Gulf Settled: v1.16's ₹38,157.89 is gone`,
        !pattern(3_815_789).test(text),
      );
    }
    if (figures.opening_net_base !== 0 && (page.opening_by_currency ?? []).length > 0) {
      check(
        `${client} ${page.person.name}: opening total = dashboard ₹${rupees(figures.opening_net_base)}`,
        pattern(figures.opening_net_base).test(text),
      );
    }
  }
}
console.log(`\n${checks} checks, ${failures} failed`);
process.exit(failures ? 1 : 0);
