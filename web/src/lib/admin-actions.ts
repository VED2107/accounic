'use server';

import { revalidatePath } from 'next/cache';
import { createAdminClient } from '@/lib/supabase/admin';
import { createClient, getMe } from '@/lib/supabase/server';
import { fail, ok } from '@/lib/errors';
import {
  adminCreateUserSchema,
  adminResetPasswordSchema,
  firstIssue,
  formObject,
} from '@/lib/validation';
import type { ActionResult } from '@/lib/types';

/**
 * Admin operations (context.md §25).
 *
 * Kept in their own module, distinct from the user actions, because they are
 * the only code in the product that can touch the service-role client.
 *
 * Authorisation is checked three times over, on purpose:
 *   1. here, before anything happens,
 *   2. by the SECURITY DEFINER admin RPCs, which call is_admin() themselves,
 *   3. by RLS for everything that is not an admin RPC.
 *
 * A normal user flipping client state gains nothing: none of these checks
 * consult anything the client sent.
 */

type Denied = { ok: false; error: string };

async function assertAdmin(): Promise<Denied | null> {
  const me = await getMe();
  if (!me) return { ok: false, error: 'Your session has expired. Please sign in again.' };
  if (!me.is_admin) return { ok: false, error: 'Administrator access is required.' };
  return null;
}

export async function adminCreateUser(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<{ id: string; email: string }>> {
  const denied = await assertAdmin();
  if (denied) return denied;

  const parsed = adminCreateUserSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const admin = createAdminClient();
  const { data, error } = await admin.auth.admin.createUser({
    email: parsed.data.email,
    password: parsed.data.password,
    // There is no public signup and no email flow, so the address is confirmed
    // at creation time by the administrator (context.md §2).
    email_confirm: true,
    user_metadata: {
      name: parsed.data.name,
      business_name: parsed.data.business_name ?? null,
      currency: parsed.data.currency,
    },
  });

  if (error) {
    if (/already (been )?registered|already exists/i.test(error.message)) {
      return { ok: false, error: 'A user with that email already exists.', field: 'email' };
    }
    return fail(error, 'That user could not be created.');
  }
  if (!data.user) return { ok: false, error: 'That user could not be created.' };

  revalidatePath('/admin');
  return ok({ id: data.user.id, email: data.user.email ?? parsed.data.email });
}

export async function adminResetPassword(
  _prev: unknown,
  formData: FormData,
): Promise<ActionResult<null>> {
  const denied = await assertAdmin();
  if (denied) return denied;

  const parsed = adminResetPasswordSchema.safeParse(formObject(formData));
  if (!parsed.success) return { ok: false, ...firstIssue(parsed.error) };

  const admin = createAdminClient();
  const { error } = await admin.auth.admin.updateUserById(parsed.data.user_id, {
    password: parsed.data.password,
  });
  if (error) return fail(error, 'That password could not be updated.');

  revalidatePath('/admin');
  return ok(null);
}

export async function adminSetUserActive(
  userId: string,
  active: boolean,
): Promise<ActionResult<null>> {
  const denied = await assertAdmin();
  if (denied) return denied;

  // Goes through the anon client so the SECURITY DEFINER RPC sees the calling
  // admin's identity and can enforce "you cannot disable yourself".
  const supabase = await createClient();
  const { error } = await supabase.rpc('admin_set_user_active', {
    p_user_id: userId,
    p_active: active,
  });
  if (error) {
    return fail(error, active ? 'That user could not be enabled.' : 'That user could not be disabled.');
  }

  revalidatePath('/admin');
  return ok(null);
}

/**
 * Grant or revoke the administrator role.
 *
 * Unlike the other admin RPCs, `grant_admin` and `revoke_admin` are granted to
 * `service_role` **only** — `authenticated` is explicitly revoked in
 * `0007_admin.sql`. So this is one of the few operations that genuinely cannot
 * be performed by a client holding nothing but the anon key, and it has to run
 * through the service-role client here on the server.
 *
 * The RPC keeps its own guard against removing the last administrator; the
 * self-check below is separate, so an admin cannot strand themselves even while
 * others remain.
 */
export async function adminSetUserAdmin(
  email: string,
  isAdmin: boolean,
): Promise<ActionResult<null>> {
  const denied = await assertAdmin();
  if (denied) return denied;

  const me = await getMe();
  if (me && me.email.toLowerCase() === email.toLowerCase() && !isAdmin) {
    return {
      ok: false,
      error: 'You cannot remove your own administrator access.',
    };
  }

  const admin = createAdminClient();
  const { error } = await admin.rpc(isAdmin ? 'grant_admin' : 'revoke_admin', {
    p_email: email,
  });
  if (error) {
    return fail(
      error,
      isAdmin
        ? 'That user could not be made an administrator.'
        : 'That user could not have administrator access removed.',
    );
  }

  revalidatePath('/admin');
  return ok(null);
}

/**
 * Permanent deletion. Cascades through profiles → people → transactions →
 * settlements, so it destroys that user's entire ledger. Disabling is the
 * default path in the UI; this exists for a genuine removal request
 * (context.md §2, §17).
 */
export async function adminDeleteUser(userId: string): Promise<ActionResult<null>> {
  const denied = await assertAdmin();
  if (denied) return denied;

  const me = await getMe();
  if (me?.id === userId) {
    return { ok: false, error: 'You cannot delete your own account.' };
  }

  const admin = createAdminClient();
  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) return fail(error, 'That user could not be deleted.');

  revalidatePath('/admin');
  return ok(null);
}
