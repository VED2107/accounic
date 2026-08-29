'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { fail, ok, UNCHANGED } from '@/lib/errors';
import { getRate, rateProvenance, type Rate } from '@/lib/rates';
import { FALLBACK_CURRENCY, normaliseCode, parseRateToE9 } from '@/lib/currencies';
import {
  firstIssue,
  formObject,
  parseAmountField,
  personSchema,
  profileSchema,
  settlementSchema,
  signInSchema,
  transactionEditSchema,
  transactionSchema,
  transferEditSchema,
  transferSchema,
  openingAdjustmentSchema,
  openingSettlementSchema,
} from '@/lib/validation';
import {
  conversionArgs,
  manualMinor,
  MANUAL_RATE_SOURCE,
  type ConversionArgs,
} from '@/lib/conversion';
import type {
  ActionResult,
  ConversionMode,
  PersonBalance,
  Person,
  TransferResult,
} from '@/lib/types';

/**
 * The rate an entry is written at: the one the user typed, or the fetched one.
 *
 * A manual rate is an ordinary rate — stored in `exchange_rate_e9`, frozen on
 * the row, and used by the database to derive the converted amount. Only its
 * source differs, and that is the whole of what makes it visible afterwards.
 */
function resolveRate(
  rateMode: ConversionMode | null | undefined,
  typedRate: string | null | undefined,
  fetchedE9: number | null,
  fetchedSource: string | null,
  from: string,
  to: string,
): { rateE9: number; source: string } | { error: string } | null {
  if (rateMode !== 'manual') {
    return fetchedE9 ? { rateE9: fetchedE9, source: fetchedSource ?? 'unrecorded' } : null;
  }

  const typed = (typedRate ?? '').trim();
  if (typed === '') {
    return { error: `Enter the rate to use for ${from} to ${to}, or switch back to the automatic rate.` };
  }

  const rateE9 = parseRateToE9(typed);
  if (rateE9 === null) {
    return {
      error: `Enter a valid rate — how many ${to} one ${from} is worth, to at most nine decimals.`,
    };
  }
  return { rateE9, source: MANUAL_RATE_SOURCE };
}

/**
 * Turn an amount field and its currency into RPC arguments.
 *
 * The amount is parsed against the currency it was *typed* in, which is what
 * makes ¥1000 and ₹10.00 both correct. If that is not the account currency, a
 * rate has to exist — and if the browser could not fetch one, the server tries
 * its own cache before giving up, because the cache is shared across the user's
 * devices and one of them may have been online more recently than this one.
 */
async function moneyArgs(entry: {
  amount: string;
  entry_currency?: string | null;
  account_currency?: string | null;
  rate_e9?: number | null;
  rate_source?: string | null;
  rate_mode?: ConversionMode | null;
  manual_rate?: string | null;
  converted_amount?: string | null;
  conversion_mode?: ConversionMode | null;
}): Promise<{ args: ConversionArgs } | { error: string }> {
  const account = normaliseCode(entry.account_currency ?? '') || FALLBACK_CURRENCY;
  const typed = normaliseCode(entry.entry_currency ?? '') || account;

  const amount = parseAmountField(entry.amount, typed);
  if (!amount.ok) return { error: amount.error };

  if (typed === account) {
    return { args: conversionArgs(amount.minor, account, account, null, null) };
  }

  let rateE9 = entry.rate_e9 ?? null;
  let source = entry.rate_source ?? null;

  // A hand-typed rate needs no lookup at all, and must not be quietly replaced
  // by one: it is the rate for this entry.
  const chosen = resolveRate(entry.rate_mode, entry.manual_rate, rateE9, source, typed, account);
  if (chosen && 'error' in chosen) return chosen;
  if (chosen) {
    rateE9 = chosen.rateE9;
    source = chosen.source;
  }

  if (!rateE9) {
    const rate = await getRate(typed, account);
    if (!rate) {
      return {
        error: `No exchange rate is available for ${typed} to ${account}. Enter the amount in ${account} instead — nothing has been saved.`,
      };
    }
    rateE9 = rate.rateE9;
    source = rate.source;
  }

  // The manual figure is parsed against the ACCOUNT currency, not the entry
  // one: it is the amount that landed in the account, which is the whole point
  // of it. Getting this pair the wrong way round is how AED 43 becomes Rs 43.
  const override = manualMinor(entry.converted_amount, entry.conversion_mode, account);
  if ('error' in override) return override;

  return { args: conversionArgs(amount.minor, typed, account, rateE9, source, override.minor) };
}

/**
 * Turn the opening-balance half of the person form into RPC arguments.
 *
 * An opening balance may be stated in a currency other than the account's — "I
 * know I owe him ₹5,000" on a dirham account — so it goes through the same
 * conversion path as a transaction, and the rate it used is stored on the row.
 */
async function openingArgs(person: {
  currency?: string | null;
  /** Overrides `currency` as what the opening balance converts into. */
  opening_account_currency?: string | null;
  opening_direction?: 'none' | 'they_owe_me' | 'i_owe_them';
  opening_amount?: string;
  opening_currency?: string | null;
  opening_rate_e9?: number | null;
  opening_rate_mode?: ConversionMode | null;
  opening_manual_rate?: string | null;
  opening_converted_amount?: string | null;
  opening_conversion_mode?: ConversionMode | null;
}): Promise<{ args: Record<string, unknown> } | { error: string }> {
  const direction = person.opening_direction ?? 'none';
  const text = (person.opening_amount ?? '').trim();

  if (direction === 'none' || text === '') {
    return { args: { p_opening_direction: null } };
  }

  // On an edit this is the account's ledger currency, which is what the
  // database writes the opening row in; on a create the two are the same thing.
  const account =
    normaliseCode(person.opening_account_currency ?? '') ||
    normaliseCode(person.currency ?? '') ||
    FALLBACK_CURRENCY;
  const entry = normaliseCode(person.opening_currency ?? '') || account;

  const amount = parseAmountField(text, entry);
  if (!amount.ok) return { error: amount.error };

  let rateE9 = person.opening_rate_e9 ?? null;
  let rateSource: string = 'form';

  if (entry !== account) {
    const chosen = resolveRate(
      person.opening_rate_mode, person.opening_manual_rate, rateE9, rateSource, entry, account,
    );
    if (chosen && 'error' in chosen) return chosen;
    if (chosen) {
      rateE9 = chosen.rateE9;
      rateSource = chosen.source;
    }
  }

  if (entry !== account && !rateE9) {
    // The form could not reach a rate — it may have been offline when the
    // currency was chosen. Try once more here before refusing, because the
    // server has a cache the browser does not.
    const rate = await getRate(entry, account);
    if (!rate) {
      return {
        error: `No exchange rate is available for ${entry} to ${account}. Enter the opening balance in ${account}.`,
      };
    }
    rateE9 = rate.rateE9;
  }

  const override = manualMinor(
    person.opening_converted_amount,
    person.opening_conversion_mode,
    account,
  );
  if ('error' in override) return override;

  const converted = conversionArgs(
    amount.minor,
    entry,
    account,
    rateE9,
    rateSource,
    override.minor,
  );

  return {
    args: {
      p_opening_direction: direction,
      p_opening_amount_minor: converted.p_amount_minor,
      p_opening_entered_minor: converted.p_entered_amount_minor,
      p_opening_entered_currency: converted.p_entered_currency,
      p_opening_rate_e9: converted.p_exchange_rate_e9,
      p_opening_rate_source: converted.p_rate_source,
      p_opening_converted_minor: converted.p_converted_amount_minor,
      p_opening_conversion_mode: converted.p_conversion_mode,
    },
  };
}

/* --------------------------------------------------------------------------
 * Exchange rates (upgrade §5, §6)
 * ----------------------------------------------------------------------- */

export interface RateQuote {
  from: string;
  to: string;
  rate_e9: number;
  as_of: string;
  source: string;
  cached: boolean;
  stale: boolean;
  /** The line the sheet shows under the converted amount. */
  provenance: string;
}

function quote(rate: Rate): RateQuote {
  return {
    from: rate.from,
    to: rate.to,
    rate_e9: rate.rateE9,
    as_of: rate.asOf,
    source: rate.source,
    cached: rate.cached,
    stale: rate.stale,
    provenance: rateProvenance(rate),
  };
}

/**
 * Look up the rate for one pair, for the transaction sheet's live preview.
 *
 * A failure here is not an error the user has to deal with: it means the amount
 * has to be entered in the account's currency, which the sheet says plainly.
 */
export async function lookupRate(from: string, to: string): Promise<ActionResult<RateQuote | null>> {
  try {
    const rate = await getRate(from, to);
    return ok(rate ? quote(rate) : null);
  } catch {
    return ok(null);
  }
}

/**
 * Server actions — the only write path in the web client (context.md §12, §21).
 *
 * Every one of them:
 *   1. validates with the shared zod schema,
 *   2. calls the matching RPC, which is where ownership, integrity and
 *      over-settlement rules actually live,
 *   3. returns a uniform ActionResult so the UI never has to guess,
 *   4. revalidates exactly the paths whose numbers changed.
 *
 * owner_id is never sent from here: the database stamps it from the session.
 */

/* --------------------------------------------------------------------------
 * Auth (context.md §2)
 * ----------------------------------------------------------------------- */

export async function signIn(_prev: unknown, formData: FormData): Promise<ActionResult<null>> {
  const parsed = signInSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({
    email: parsed.data.email,
    password: parsed.data.password,
  });

  if (error) {
    // Deliberately identical for "no such user" and "wrong password" so the
    // form cannot be used to enumerate accounts.
    return { ok: false, error: 'That email and password combination is not correct.' };
  }

  const { data } = await supabase.rpc('me');
  if (!data || (data as { is_active: boolean }).is_active === false) {
    await supabase.auth.signOut();
    return { ok: false, error: 'This account has been disabled. Contact your administrator.' };
  }

  return ok(null);
}

export async function signOut(): Promise<never> {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect('/login');
}

/* --------------------------------------------------------------------------
 * People (context.md §5)
 * ----------------------------------------------------------------------- */

export async function createPerson(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<Person>> {
  const parsed = personSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const opening = await openingArgs(parsed.data);
  if ('error' in opening) return { ok: false, error: opening.error, field: 'opening_amount' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_person', {
    p_name: parsed.data.name,
    p_type: parsed.data.type,
    p_phone: parsed.data.phone ?? null,
    p_email: parsed.data.email ?? null,
    p_address: parsed.data.address ?? null,
    p_notes: parsed.data.notes ?? null,
    p_currency: parsed.data.currency ?? null,
    ...opening.args,
  });
  if (error) return fail(error, UNCHANGED.person);

  revalidatePath('/people');
  revalidatePath('/');
  return ok(data as Person);
}

export async function updatePerson(
  personId: string,
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<Person>> {
  const parsed = personSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  // Parsed before the write, so a malformed opening amount is refused with the
  // form intact rather than after the name has already been saved.
  const opening = parsed.data.opening_changed ? await openingArgs(parsed.data) : null;
  if (opening && 'error' in opening) {
    return { ok: false, error: opening.error, field: 'opening_amount' };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('update_person', {
    p_person_id: personId,
    p_name: parsed.data.name,
    p_type: parsed.data.type,
    p_phone: parsed.data.phone ?? null,
    p_email: parsed.data.email ?? null,
    p_address: parsed.data.address ?? null,
    p_notes: parsed.data.notes ?? null,
    p_currency: parsed.data.currency ?? null,
    p_currency_change_confirmed: parsed.data.currency_change_confirmed ?? false,
  });
  if (error) return fail(error, UNCHANGED.person);

  // Then the opening balance, through the same RPC the create path uses. The
  // database retracts the old one rather than editing it, so the correction is
  // visible in the history instead of quietly rewriting what the account opened
  // with. 'none' clears it, which is how removing one works.
  if (opening) {
    const openingError = await writeOpeningBalance(supabase, personId, opening.args);
    if (openingError) return openingError;
  }

  revalidatePath(`/people/${personId}`);
  revalidatePath('/people');
  revalidatePath('/');
  return ok(data as Person);
}

/**
 * The one call to `set_person_opening_balance`, shared by the edit form and the
 * standalone action so the two can never disagree about how one is written.
 *
 * Returns a failed `ActionResult` or null when it went through.
 */
async function writeOpeningBalance(
  supabase: Awaited<ReturnType<typeof createClient>>,
  personId: string,
  args: Record<string, unknown>,
): Promise<ActionResult<never> | null> {
  const { error } = await supabase.rpc('set_person_opening_balance', {
    p_person_id: personId,
    p_direction: args.p_opening_direction ?? 'none',
    p_amount_minor: args.p_opening_amount_minor ?? null,
    p_entered_amount_minor: args.p_opening_entered_minor ?? null,
    p_entered_currency: args.p_opening_entered_currency ?? null,
    p_rate_e9: args.p_opening_rate_e9 ?? null,
    p_rate_source: args.p_opening_rate_source ?? null,
    p_converted_amount_minor: args.p_opening_converted_minor ?? null,
    p_conversion_mode: args.p_opening_conversion_mode ?? null,
  });
  if (error) {
    return fail(
      error,
      'That opening balance could not be saved. Your balance has not been changed.',
    );
  }
  return null;
}

/**
 * Set, change or clear a person's opening balance after the fact (upgrade §3).
 *
 * Replacing one retracts the previous entry rather than editing it, so the
 * correction is visible in the history instead of quietly rewriting what the
 * account was opened with. That is the database's behaviour, not this action's.
 */
export async function setOpeningBalance(
  personId: string,
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<null>> {
  const parsed = personSchema
    .pick({
      currency: true,
      opening_direction: true,
      opening_amount: true,
      opening_currency: true,
      opening_rate_e9: true,
      opening_converted_amount: true,
      opening_conversion_mode: true,
      opening_account_currency: true,
    })
    .safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const opening = await openingArgs(parsed.data);
  if ('error' in opening) return { ok: false, error: opening.error, field: 'opening_amount' };

  const supabase = await createClient();
  const openingError = await writeOpeningBalance(supabase, personId, opening.args);
  if (openingError) return openingError;

  revalidatePath(`/people/${personId}`);
  revalidatePath('/people');
  revalidatePath('/');
  return ok(null);
}

export async function setPersonArchived(
  personId: string,
  archived: boolean,
): Promise<ActionResult<Person>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('set_person_archived', {
    p_person_id: personId,
    p_archived: archived,
  });
  if (error) {
    return fail(error, archived ? 'This person could not be archived.' : 'This person could not be restored.');
  }

  revalidatePath(`/people/${personId}`);
  revalidatePath('/people');
  revalidatePath('/');
  return ok(data as Person);
}

export async function deletePerson(personId: string): Promise<ActionResult<null>> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('delete_person', { p_person_id: personId });
  if (error) return fail(error, 'This person could not be deleted.');

  revalidatePath('/people');
  revalidatePath('/');
  return ok(null);
}

/**
 * Retract a person's whole history in one call (db/migrations/0014).
 *
 * A void, not a delete. Every row stays in the database with its amount, date
 * and rate intact; the balance goes to zero and the entries leave the activity
 * feed, while the person's own timeline keeps showing them marked voided.
 *
 * The reason is stored on each row, so a later reader can tell a bulk
 * retraction apart from thirty individual ones.
 */
export async function voidPersonHistory(
  personId: string,
  reason?: string,
): Promise<ActionResult<null>> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('void_person_history', {
    p_person_id: personId,
    p_reason: reason?.trim() || null,
  });
  if (error) return fail(error, 'That history could not be retracted.');

  revalidatePath('/people');
  revalidatePath(`/people/${personId}`);
  revalidatePath('/activity');
  revalidatePath('/');
  return ok(null);
}

/* --------------------------------------------------------------------------
 * Transactions (context.md §7, §14)
 * ----------------------------------------------------------------------- */

interface LedgerMutation {
  balance: PersonBalance | null;
}

export async function createTransaction(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<LedgerMutation>> {
  const parsed = transactionSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const money = await moneyArgs(parsed.data);
  if ('error' in money) return { ok: false, error: money.error, field: 'amount' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_transaction', {
    p_person_id: parsed.data.person_id,
    p_type: parsed.data.type,
    p_date: parsed.data.date,
    p_description: parsed.data.description ?? null,
    ...money.args,
  });
  if (error) return fail(error, UNCHANGED.transaction);

  revalidatePath(`/people/${parsed.data.person_id}`);
  revalidatePath('/people');
  revalidatePath('/activity');
  revalidatePath('/');
  return ok(data as LedgerMutation);
}

export async function updateTransaction(
  personId: string,
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<LedgerMutation>> {
  const parsed = transactionEditSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const money = await moneyArgs(parsed.data);
  if ('error' in money) return { ok: false, error: money.error, field: 'amount' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('update_transaction', {
    p_transaction_id: parsed.data.transaction_id,
    p_type: parsed.data.type,
    p_date: parsed.data.date,
    p_description: parsed.data.description ?? null,
    ...money.args,
  });
  if (error) return fail(error, UNCHANGED.transaction);

  revalidatePath(`/people/${personId}`);
  revalidatePath('/people');
  revalidatePath('/activity');
  revalidatePath('/');
  return ok(data as LedgerMutation);
}

export async function voidTransaction(
  personId: string,
  transactionId: string,
  reason?: string,
): Promise<ActionResult<LedgerMutation>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('void_transaction', {
    p_transaction_id: transactionId,
    p_reason: reason ?? null,
  });
  if (error) {
    return fail(error, 'This transaction could not be voided. Your balance has not been changed.');
  }

  revalidatePath(`/people/${personId}`);
  revalidatePath('/people');
  revalidatePath('/activity');
  revalidatePath('/');
  return ok(data as LedgerMutation);
}

/* --------------------------------------------------------------------------
 * Settlements (context.md §9)
 * ----------------------------------------------------------------------- */

export async function createSettlement(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<LedgerMutation>> {
  const parsed = settlementSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const transactionId = parsed.data.transaction_id ? parsed.data.transaction_id : null;

  const money = await moneyArgs(parsed.data);
  if ('error' in money) return { ok: false, error: money.error, field: 'amount' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_settlement', {
    p_person_id: parsed.data.person_id,
    // Omitted when a transaction is named: the database derives it from the
    // transaction type, which removes a whole class of client mistakes.
    p_direction: transactionId ? null : (parsed.data.direction ?? null),
    p_transaction_id: transactionId,
    p_date: parsed.data.date,
    p_note: parsed.data.note ?? null,
    ...money.args,
  });
  if (error) return fail(error, UNCHANGED.settlement);

  revalidatePath(`/people/${parsed.data.person_id}`);
  revalidatePath('/people');
  revalidatePath('/activity');
  revalidatePath('/');
  return ok(data as LedgerMutation);
}

/**
 * Settle the opening balance — that entry, and nothing else (upgrade §48).
 *
 * The direction is not sent: `settle_opening_balance()` derives it from the
 * opening entry, so a client cannot record money coming in against a balance
 * the user owes. The ceiling, the conversion path and the ledger denomination
 * are all `create_settlement()`'s, unchanged.
 */
export async function settleOpeningBalance(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<LedgerMutation>> {
  const parsed = openingSettlementSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const money = await moneyArgs(parsed.data);
  if ('error' in money) return { ok: false, error: money.error, field: 'amount' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('settle_opening_balance', {
    p_person_id: parsed.data.person_id,
    p_date: parsed.data.date,
    p_note: parsed.data.note ?? null,
    ...money.args,
  });
  if (error) return fail(error, UNCHANGED.settlement);

  revalidatePath(`/people/${parsed.data.person_id}`);
  revalidatePath('/people');
  revalidatePath('/activity');
  revalidatePath('/');
  return ok(data as LedgerMutation);
}

/**
 * Credit or debit against the opening balance (db/migrations/0022).
 *
 * Deliberately NOT `createTransaction`. What this records is not a transaction:
 * it is a correction to the figure the account was carried in with, and it must
 * never appear among the regular transactions, never move cash in hand, and
 * never be counted twice on the dashboard. `adjust_opening_balance()` enforces
 * all four — this action's only job is to hand it what the form said.
 *
 * The conversion path is `moneyArgs`, the same one every other money action
 * uses: the client sends what was typed, its currency and the rate; the
 * database does the arithmetic and freezes the rate on the row.
 */
export async function adjustOpeningBalance(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<LedgerMutation>> {
  const parsed = openingAdjustmentSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const money = await moneyArgs(parsed.data);
  if ('error' in money) return { ok: false, error: money.error, field: 'amount' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('adjust_opening_balance', {
    p_person_id: parsed.data.person_id,
    p_type: parsed.data.type,
    p_date: parsed.data.date,
    p_note: parsed.data.note ?? null,
    ...money.args,
  });
  if (error) {
    return fail(
      error,
      'That opening balance entry could not be saved. Your balance has not been changed.',
    );
  }

  revalidatePath(`/people/${parsed.data.person_id}`);
  revalidatePath('/people');
  revalidatePath('/activity');
  revalidatePath('/');
  return ok(data as LedgerMutation);
}

export async function voidSettlement(
  personId: string,
  settlementId: string,
  reason?: string,
): Promise<ActionResult<LedgerMutation>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('void_settlement', {
    p_settlement_id: settlementId,
    p_reason: reason ?? null,
  });
  if (error) {
    return fail(error, 'This settlement could not be reversed. Your balance has not been changed.');
  }

  revalidatePath(`/people/${personId}`);
  revalidatePath('/people');
  revalidatePath('/activity');
  revalidatePath('/');
  return ok(data as LedgerMutation);
}

/* --------------------------------------------------------------------------
 * Transfers (upgrade §46)
 *
 * A transfer is ONE logical record with two linked ledger entries, and every
 * one of these actions operates on the whole of it. There is deliberately no
 * action here that touches a single leg: the database refuses that outright,
 * and offering it would be offering a way to lose money from one account
 * without it arriving in the other.
 * ----------------------------------------------------------------------- */

/**
 * Resolve a transfer's two conversions into RPC arguments.
 *
 * Two steps, each skipped when its currencies agree:
 *
 *     entry currency --entry rate--> source ledger --rate--> destination ledger
 *
 * The amount is parsed against the currency it was TYPED in. Neither converted
 * figure is computed here: the entered amount and the rates travel, and the
 * database derives both. The single exception is the manual arrival amount,
 * which is not derived from anything — it is what the user says reached the
 * other account.
 */
async function transferArgs(entry: {
  amount: string;
  entry_currency?: string | null;
  from_currency?: string | null;
  to_currency?: string | null;
  entry_rate_e9?: number | null;
  entry_rate_source?: string | null;
  entry_rate_mode?: ConversionMode | null;
  entry_manual_rate?: string | null;
  rate_e9?: number | null;
  rate_source?: string | null;
  rate_mode?: ConversionMode | null;
  manual_rate?: string | null;
  converted_amount?: string | null;
  conversion_mode?: ConversionMode | null;
}): Promise<{ args: Record<string, unknown> } | { error: string; field?: string }> {
  const from = normaliseCode(entry.from_currency ?? '') || FALLBACK_CURRENCY;
  const to = normaliseCode(entry.to_currency ?? '') || from;
  const typed = normaliseCode(entry.entry_currency ?? '') || from;

  const amount = parseAmountField(entry.amount, typed);
  if (!amount.ok) return { error: amount.error, field: 'amount' };

  // Step one: what the user typed, in the source account's denomination.
  let entryRateE9: number | null = null;
  if (typed !== from) {
    const chosen = resolveRate(
      entry.entry_rate_mode,
      entry.entry_manual_rate,
      entry.entry_rate_e9 ?? null,
      entry.entry_rate_source ?? null,
      typed,
      from,
    );
    if (chosen && 'error' in chosen) return chosen;
    entryRateE9 = chosen?.rateE9 ?? null;

    if (!entryRateE9) {
      const rate = await getRate(typed, from);
      if (!rate) {
        return {
          error: `No exchange rate is available for ${typed} to ${from}. Enter the amount in ${from} instead — nothing has been saved.`,
          field: 'amount',
        };
      }
      entryRateE9 = rate.rateE9;
    }
  }

  // Step two: what reaches the destination account.
  let rateE9: number | null = null;
  let rateSource: string | null = null;
  if (from !== to) {
    const chosen = resolveRate(
      entry.rate_mode,
      entry.manual_rate,
      entry.rate_e9 ?? null,
      entry.rate_source ?? null,
      from,
      to,
    );
    if (chosen && 'error' in chosen) return chosen;
    if (chosen) {
      rateE9 = chosen.rateE9;
      rateSource = chosen.source;
    }

    if (!rateE9) {
      const rate = await getRate(from, to);
      if (!rate) {
        return {
          error: `No exchange rate is available for ${from} to ${to}. Nothing has been saved.`,
          field: 'amount',
        };
      }
      rateE9 = rate.rateE9;
      rateSource = rate.source;
    }
  }

  // The arrival override is parsed against the DESTINATION currency: it is the
  // amount that landed there, which is the whole point of it.
  const override = manualMinor(entry.converted_amount, entry.conversion_mode, to);
  if ('error' in override) return { error: override.error, field: 'converted_amount' };

  return {
    args: {
      p_amount_minor: amount.minor,
      p_currency: typed,
      p_entry_rate_e9: entryRateE9,
      p_exchange_rate_e9: rateE9,
      p_rate_source: rateSource,
      p_converted_amount_minor: override.minor,
      p_conversion_mode: override.minor === null ? null : 'manual',
    },
  };
}

/** Every screen a transfer can change. Both people, and both totals. */
function revalidateTransfer(fromPersonId?: string | null, toPersonId?: string | null) {
  if (fromPersonId) revalidatePath(`/people/${fromPersonId}`);
  if (toPersonId) revalidatePath(`/people/${toPersonId}`);
  revalidatePath('/people');
  revalidatePath('/activity');
  revalidatePath('/');
}

export async function createTransfer(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<TransferResult>> {
  const parsed = transferSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  if (parsed.data.from_person_id === parsed.data.to_person_id) {
    return {
      ok: false,
      error:
        'Choose two different people — money cannot be transferred to the account it came from.',
      field: 'to_person_id',
    };
  }

  const money = await transferArgs(parsed.data);
  if ('error' in money) return { ok: false, error: money.error, field: money.field };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_transfer', {
    p_from_person_id: parsed.data.from_person_id,
    p_to_person_id: parsed.data.to_person_id,
    p_date: parsed.data.date,
    p_note: parsed.data.note ?? null,
    // The database returns the transfer this token already made rather than
    // making a second one, so a double submit moves the money once.
    p_client_token: parsed.data.client_token ?? null,
    ...money.args,
  });
  if (error) {
    return fail(error, 'That transfer could not be recorded. No balance has been changed.');
  }

  revalidateTransfer(parsed.data.from_person_id, parsed.data.to_person_id);
  return ok(data as TransferResult);
}

export async function updateTransfer(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<TransferResult>> {
  const parsed = transferEditSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const money = await transferArgs(parsed.data);
  if ('error' in money) return { ok: false, error: money.error, field: money.field };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('update_transfer', {
    p_transfer_id: parsed.data.transfer_id,
    p_date: parsed.data.date,
    p_note: parsed.data.note ?? null,
    ...money.args,
  });
  if (error) {
    return fail(error, 'That transfer could not be changed. No balance has been changed.');
  }

  const result = data as TransferResult;
  revalidateTransfer(result?.transfer?.from_person_id, result?.transfer?.to_person_id);
  return ok(result);
}

/**
 * Retract a transfer — both sides, in one operation.
 *
 * A void, not a delete: both entries stay on both timelines with their amounts
 * and dates intact, and both balances return to where they were. The database
 * voids the two legs together and refuses any commit that would leave one
 * without the other, so this cannot half-succeed.
 */
export async function voidTransfer(
  transferId: string,
  reason?: string,
): Promise<ActionResult<TransferResult>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('void_transfer', {
    p_transfer_id: transferId,
    p_reason: reason?.trim() || null,
  });
  if (error) {
    return fail(error, 'That transfer could not be retracted. No balance has been changed.');
  }

  const result = data as TransferResult;
  revalidateTransfer(result?.transfer?.from_person_id, result?.transfer?.to_person_id);
  return ok(result);
}

/* --------------------------------------------------------------------------
 * Profile (context.md §4)
 * ----------------------------------------------------------------------- */

export async function updateProfile(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<null>> {
  const parsed = profileSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const supabase = await createClient();
  const { error } = await supabase.rpc('update_my_profile', {
    p_name: parsed.data.name,
    p_phone: parsed.data.phone ?? null,
    p_business_name: parsed.data.business_name ?? null,
    p_currency: parsed.data.currency,
    p_avatar_url: null,
  });
  if (error) return fail(error, UNCHANGED.profile);

  revalidatePath('/profile');
  revalidatePath('/');
  return ok(null);
}

export async function changeMyPassword(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<null>> {
  const password = String(formData.get('password') ?? '');
  const confirm = String(formData.get('confirm') ?? '');

  if (password.length < 10) {
    return { ok: false, error: 'Use at least 10 characters.', field: 'password' };
  }
  if (!/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/\d/.test(password)) {
    return {
      ok: false,
      error: 'Include an uppercase letter, a lowercase letter and a number.',
      field: 'password',
    };
  }
  if (password !== confirm) {
    return { ok: false, error: 'Those passwords do not match.', field: 'confirm' };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password });
  if (error) return fail(error, 'Your password could not be changed.');

  return ok(null);
}
