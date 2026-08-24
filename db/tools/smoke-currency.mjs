/**
 * End-to-end check of the multi-currency feature over real HTTP (upgrade §20).
 *
 *   node db/tools/smoke-currency.mjs
 *
 * The database tests in db/tests/04_currency.sql run inside a transaction that
 * rolls back, which proves the arithmetic but not the wire: PostgREST argument
 * binding, the anon key path, and RLS as an ordinary signed-in user are all
 * outside that. This exercises them.
 *
 * It creates its own throwaway user with the service role, does everything as
 * that user with the anon key, and deletes the user at the end — which cascades
 * to exactly the rows it created and nothing else. Existing data is never read
 * or written; `snapshot.mjs` is the independent check on that claim.
 */
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..', '..');
const env = readFileSync(join(root, 'web', '.env.local'), 'utf8');

const pick = (key) => {
  const match = env.match(new RegExp(`^${key}=(.+)$`, 'm'));
  if (!match) throw new Error(`${key} missing from web/.env.local`);
  return match[1].trim();
};

const URL = pick('NEXT_PUBLIC_SUPABASE_URL');
const ANON = pick('NEXT_PUBLIC_SUPABASE_ANON_KEY');
const SERVICE = pick('SUPABASE_SERVICE_ROLE_KEY');

let passed = 0;
let failed = 0;

function check(label, condition, detail = '') {
  if (condition) {
    passed += 1;
    console.log(`ok   ${label}${detail ? ` — ${detail}` : ''}`);
  } else {
    failed += 1;
    console.log(`FAIL ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });

const email = `currency-smoke-${Date.now()}@accounic.test`;
const password = 'Smoke@12345';

const created = await admin.auth.admin.createUser({
  email,
  password,
  email_confirm: true,
  user_metadata: { name: 'Currency Smoke', currency: 'INR' },
});
if (created.error) throw created.error;
const userId = created.data.user.id;
console.log(`\n--- throwaway user ${email} ---\n`);

let exitCode = 0;
try {
  const api = createClient(URL, ANON, { auth: { persistSession: false } });
  const signIn = await api.auth.signInWithPassword({ email, password });
  if (signIn.error) throw signIn.error;

  // --- the currency list is readable, and is the shared one -----------------
  const currencies = await api.from('currencies').select('code, decimals').limit(200);
  const shared = JSON.parse(readFileSync(join(root, 'shared', 'currencies.json'), 'utf8'));
  check(
    'the currency list is readable and matches shared/currencies.json',
    (currencies.data ?? []).length === shared.currencies.length,
    `${currencies.data?.length} of ${shared.currencies.length}`,
  );
  check(
    'the yen is stored with no minor unit',
    currencies.data?.find((c) => c.code === 'JPY')?.decimals === 0,
  );

  // --- a person in another currency, with an opening balance ---------------
  const ahmed = await api.rpc('create_person', {
    p_name: 'Ahmed',
    p_currency: 'AED',
    p_opening_direction: 'they_owe_me',
    p_opening_amount_minor: 50000, // AED 500.00
  });
  check('a person can be created in another currency', !ahmed.error && ahmed.data?.currency === 'AED',
    ahmed.error?.message ?? ahmed.data?.currency);

  const personId = ahmed.data?.id;

  const page = await api.rpc('person_page', { p_person_id: personId });
  check('the account is denominated in that currency', page.data?.currency === 'AED');
  check('the base currency travels with it', page.data?.base_currency === 'INR');
  check(
    'the opening balance is on the receivable side',
    page.data?.balance?.outstanding_receivable === 50000,
    String(page.data?.balance?.outstanding_receivable),
  );
  check(
    'and is marked as an opening balance rather than a transaction',
    (page.data?.timeline ?? []).some((entry) => entry.is_opening === true),
  );

  // --- caching a rate, then a cross-currency transaction -------------------
  const cached = await api.rpc('upsert_exchange_rates', {
    p_base: 'INR',
    p_rates: { AED: 0.0416 },
    p_source: 'smoke',
  });
  check('a rate can be cached', !cached.error && cached.data >= 1, cached.error?.message ?? '');

  const txn = await api.rpc('create_transaction', {
    p_person_id: personId,
    p_type: 'credit',
    p_entered_amount_minor: 100000, // ₹1,000.00
    p_entered_currency: 'INR',
    p_exchange_rate_e9: 41600000, // 1 INR = 0.0416 AED
    p_rate_source: 'smoke',
  });
  check(
    'a rupee amount is stored as its dirham equivalent',
    txn.data?.transaction?.amount_minor === 4160,
    String(txn.data?.transaction?.amount_minor),
  );
  check(
    'the original amount and currency are kept on the row',
    txn.data?.transaction?.entered_amount_minor === 100000 &&
      txn.data?.transaction?.entered_currency === 'INR',
  );
  check(
    'so is the rate that was used',
    txn.data?.transaction?.exchange_rate_e9 === 41600000,
  );

  // --- the aggregate converts, and says what it could not convert ----------
  const kenji = await api.rpc('create_person', { p_name: 'Kenji', p_currency: 'JPY' });
  await api.rpc('create_transaction', {
    p_person_id: kenji.data.id,
    p_type: 'credit',
    p_amount_minor: 5000, // ¥5,000
  });

  const dashboard = await api.rpc('dashboard');
  check('the dashboard states its base currency', dashboard.data?.base_currency === 'INR');
  check(
    'the dirham account is converted into it',
    dashboard.data?.summary?.total_receivable > 0,
    `₹${(dashboard.data?.summary?.total_receivable ?? 0) / 100}`,
  );
  check(
    'and the account with no rate is counted, not silently dropped',
    dashboard.data?.summary?.unconverted_people === 1,
    String(dashboard.data?.summary?.unconverted_people),
  );

  // --- a foreign amount with no rate is refused, and nothing is written ----
  const refused = await api.rpc('create_transaction', {
    p_person_id: kenji.data.id,
    p_type: 'credit',
    p_entered_amount_minor: 100000,
    p_entered_currency: 'INR',
  });
  check('a foreign entry with no rate is refused', refused.error !== null,
    refused.error?.message ?? 'it was allowed');

  const after = await api.rpc('person_page', { p_person_id: kenji.data.id });
  check('and the balance is untouched', after.data?.balance?.net_balance === 5000);

  // --- changing an account's currency is refused until it is confirmed -----
  const unconfirmed = await api.rpc('update_person', {
    p_person_id: personId,
    p_name: 'Ahmed',
    p_type: 'person',
    p_currency: 'USD',
  });
  check('changing the currency of an account with history is refused first',
    unconfirmed.error !== null, unconfirmed.error?.message?.slice(0, 60) ?? '');

  const stillAed = await api.rpc('person_page', { p_person_id: personId });
  check('and nothing moved when it was refused', stillAed.data?.currency === 'AED');

  const beforeSwitch = await api.rpc('person_page', { p_person_id: personId });
  const openingBefore = (beforeSwitch.data?.timeline ?? []).find((e) => e.is_opening);

  const confirmed = await api.rpc('update_person', {
    p_person_id: personId,
    p_name: 'Ahmed',
    p_type: 'person',
    p_currency: 'USD',
    p_currency_change_confirmed: true,
  });
  check('confirming it moves the default for new entries',
    !confirmed.error && confirmed.data?.currency === 'USD',
    confirmed.error?.message ?? '');

  const switched = await api.rpc('person_page', { p_person_id: personId });
  const opening = (switched.data?.timeline ?? []).find((entry) => entry.is_opening);

  // The point of v1.1.1: the change rewrote nothing.
  check('the history stays denominated where it was written',
    switched.data?.currency === 'AED', String(switched.data?.currency));
  check('and the entry default is the new currency',
    switched.data?.default_currency === 'USD', String(switched.data?.default_currency));
  check('the opening balance is still the AED 500 that was entered',
    opening?.amount_minor === 50000, String(opening?.amount_minor));
  check('not one historical figure moved',
    opening?.amount_minor === openingBefore?.amount_minor
      && opening?.entered_amount_minor === openingBefore?.entered_amount_minor
      && opening?.entered_currency === openingBefore?.entered_currency);
  check('and the balance is unchanged',
    switched.data?.balance?.net_balance === beforeSwitch.data?.balance?.net_balance);

  // --- the actual converted amount, over the wire (upgrade §40) -------------
  //
  // The brief's case: an AED account, ₹1,000 handed over, a rate that makes it
  // AED 41.60, and AED 40 actually given at the counter.
  const manualPerson = await api.rpc('create_person', {
    p_name: 'Manual Conversion',
    p_currency: 'AED',
  });

  const manual = await api.rpc('create_transaction', {
    p_person_id: manualPerson.data.id,
    p_type: 'credit',
    p_entered_amount_minor: 100000, // ₹1,000.00
    p_entered_currency: 'INR',
    p_exchange_rate_e9: 41600000,
    p_rate_source: 'smoke',
    p_converted_amount_minor: 4000, // AED 40.00 actually exchanged
    p_conversion_mode: 'manual',
  });
  check(
    'the ledger takes the amount that actually changed hands',
    manual.data?.transaction?.amount_minor === 4000,
    String(manual.data?.transaction?.amount_minor),
  );
  check(
    'and keeps what the rate said, as the audit reference',
    manual.data?.transaction?.auto_converted_amount_minor === 4160 &&
      manual.data?.transaction?.conversion_mode === 'manual',
    `${manual.data?.transaction?.auto_converted_amount_minor} / ${manual.data?.transaction?.conversion_mode}`,
  );
  check(
    'the rupees and the rate survive the override',
    manual.data?.transaction?.entered_amount_minor === 100000 &&
      manual.data?.transaction?.entered_currency === 'INR' &&
      manual.data?.transaction?.exchange_rate_e9 === 41600000,
  );

  // Editing the note must not restate a manual row at the stored rate.
  const manualId = manual.data.transaction.id;
  const noteEdit = await api.rpc('update_transaction', {
    p_transaction_id: manualId,
    p_type: 'credit',
    p_description: 'note edited',
  });
  check(
    'editing the note leaves the actual amount exactly where it was',
    noteEdit.data?.transaction?.amount_minor === 4000 &&
      noteEdit.data?.transaction?.conversion_mode === 'manual' &&
      noteEdit.data?.transaction?.auto_converted_amount_minor === 4160,
    String(noteEdit.data?.transaction?.amount_minor),
  );

  const backToAuto = await api.rpc('update_transaction', {
    p_transaction_id: manualId,
    p_type: 'credit',
    p_description: 'note edited',
    p_entered_amount_minor: 100000,
    p_entered_currency: 'INR',
    p_exchange_rate_e9: 41600000,
    p_rate_source: 'smoke',
    p_conversion_mode: 'automatic',
  });
  check(
    'switching back to automatic restores the rate-derived amount',
    backToAuto.data?.transaction?.amount_minor === 4160 &&
      backToAuto.data?.transaction?.conversion_mode === 'automatic' &&
      backToAuto.data?.transaction?.auto_converted_amount_minor === null,
    String(backToAuto.data?.transaction?.amount_minor),
  );

  const manualPage = await api.rpc('person_page', { p_person_id: manualPerson.data.id });
  check(
    'the timeline every client reads carries the mode',
    (manualPage.data?.timeline ?? []).some((e) => e.conversion_mode === 'automatic'),
  );

  const manualRefused = await api.rpc('create_transaction', {
    p_person_id: manualPerson.data.id,
    p_type: 'credit',
    p_entered_amount_minor: 100000,
    p_entered_currency: 'INR',
    p_exchange_rate_e9: 41600000,
    p_conversion_mode: 'manual',
  });
  check(
    'manual mode with no actual amount is refused',
    manualRefused.error !== null,
    manualRefused.error?.message ?? 'it was allowed',
  );

  // An opening balance takes the override too.
  const openingOverride = await api.rpc('set_person_opening_balance', {
    p_person_id: manualPerson.data.id,
    p_direction: 'they_owe_me',
    p_entered_amount_minor: 100000,
    p_entered_currency: 'INR',
    p_rate_e9: 41600000,
    p_rate_source: 'smoke',
    p_converted_amount_minor: 4000,
    p_conversion_mode: 'manual',
  });
  check(
    'an opening balance records the actual converted amount',
    openingOverride.data?.transaction?.amount_minor === 4000 &&
      openingOverride.data?.transaction?.conversion_mode === 'manual',
    String(openingOverride.data?.transaction?.amount_minor),
  );

  // --- an old-style client still works --------------------------------------
  // Exactly the arguments v1.0.7 sends: no currency, no conversion.
  const legacy = await api.rpc('create_person', { p_name: 'Legacy', p_type: 'person' });
  const legacyTxn = await api.rpc('create_transaction', {
    p_person_id: legacy.data.id,
    p_type: 'debit',
    p_amount_minor: 250000,
    p_date: new Date().toISOString().slice(0, 10),
    p_description: 'as an older client would send it',
  });
  check('a client built before this release still writes correctly',
    !legacyTxn.error && legacyTxn.data?.transaction?.amount_minor === 250000,
    legacyTxn.error?.message ?? '');
  check('and its person falls back to the base currency',
    (await api.rpc('person_page', { p_person_id: legacy.data.id })).data?.currency === 'INR');
} catch (error) {
  failed += 1;
  console.log(`FAIL unexpected error — ${error.message}`);
} finally {
  const removed = await admin.auth.admin.deleteUser(userId);
  console.log(`\n--- throwaway user removed${removed.error ? ` (FAILED: ${removed.error.message})` : ''} ---`);
  if (removed.error) exitCode = 1;
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : exitCode);
