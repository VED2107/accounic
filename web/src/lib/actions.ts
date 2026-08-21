'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { fail, ok, UNCHANGED } from '@/lib/errors';
import {
  firstIssue,
  formObject,
  personSchema,
  profileSchema,
  settlementSchema,
  signInSchema,
  transactionEditSchema,
  transactionSchema,
} from '@/lib/validation';
import type { ActionResult, PersonBalance, Person } from '@/lib/types';

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

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_person', {
    p_name: parsed.data.name,
    p_type: parsed.data.type,
    p_phone: parsed.data.phone ?? null,
    p_email: parsed.data.email ?? null,
    p_address: parsed.data.address ?? null,
    p_notes: parsed.data.notes ?? null,
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
  });
  if (error) return fail(error, UNCHANGED.person);

  revalidatePath(`/people/${personId}`);
  revalidatePath('/people');
  revalidatePath('/');
  return ok(data as Person);
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

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_transaction', {
    p_person_id: parsed.data.person_id,
    p_type: parsed.data.type,
    p_amount_minor: parsed.data.amount,
    p_date: parsed.data.date,
    p_description: parsed.data.description ?? null,
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

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('update_transaction', {
    p_transaction_id: parsed.data.transaction_id,
    p_type: parsed.data.type,
    p_amount_minor: parsed.data.amount,
    p_date: parsed.data.date,
    p_description: parsed.data.description ?? null,
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

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_settlement', {
    p_person_id: parsed.data.person_id,
    p_amount_minor: parsed.data.amount,
    // Omitted when a transaction is named: the database derives it from the
    // transaction type, which removes a whole class of client mistakes.
    p_direction: transactionId ? null : (parsed.data.direction ?? null),
    p_transaction_id: transactionId,
    p_date: parsed.data.date,
    p_note: parsed.data.note ?? null,
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
