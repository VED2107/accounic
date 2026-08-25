'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { fail, ok, UNCHANGED } from '@/lib/errors';
import { getRate, rateProvenance, type Rate } from '@/lib/rates';
import { FALLBACK_CURRENCY, normaliseCode } from '@/lib/currencies';
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
} from '@/lib/validation';
import { conversionArgs, manualMinor, type ConversionArgs } from '@/lib/conversion';
import type { ActionResult, ConversionMode, PersonBalance, Person } from '@/lib/types';

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
  opening_direction?: 'none' | 'they_owe_me' | 'i_owe_them';
  opening_amount?: string;
  opening_currency?: string | null;
  opening_rate_e9?: number | null;
  opening_converted_amount?: string | null;
  opening_conversion_mode?: ConversionMode | null;
}): Promise<{ args: Record<string, unknown> } | { error: string }> {
  const direction = person.opening_direction ?? 'none';
  const text = (person.opening_amount ?? '').trim();

  if (direction === 'none' || text === '') {
    return { args: { p_opening_direction: null } };
  }

  const account = normaliseCode(person.currency ?? '') || FALLBACK_CURRENCY;
  const entry = normaliseCode(person.opening_currency ?? '') || account;

  const amount = parseAmountField(text, entry);
  if (!amount.ok) return { error: amount.error };

  let rateE9 = person.opening_rate_e9 ?? null;
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
    'form',
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

  revalidatePath(`/people/${personId}`);
  revalidatePath('/people');
  revalidatePath('/');
  return ok(data as Person);
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
    })
    .safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const opening = await openingArgs(parsed.data);
  if ('error' in opening) return { ok: false, error: opening.error, field: 'opening_amount' };

  const supabase = await createClient();
  const { error } = await supabase.rpc('set_person_opening_balance', {
    p_person_id: personId,
    p_direction: opening.args.p_opening_direction ?? 'none',
    p_amount_minor: opening.args.p_opening_amount_minor ?? null,
    p_entered_amount_minor: opening.args.p_opening_entered_minor ?? null,
    p_entered_currency: opening.args.p_opening_entered_currency ?? null,
    p_rate_e9: opening.args.p_opening_rate_e9 ?? null,
    p_rate_source: opening.args.p_opening_rate_source ?? null,
    p_converted_amount_minor: opening.args.p_opening_converted_minor ?? null,
    p_conversion_mode: opening.args.p_opening_conversion_mode ?? null,
  });
  if (error) return fail(error, 'That opening balance could not be saved. Your balance has not been changed.');

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
