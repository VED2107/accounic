import type { PostgrestError } from '@supabase/supabase-js';
import type { ActionResult } from '@/lib/types';

/**
 * Error translation (context.md §26).
 *
 * Two rules:
 *   1. Never silently fail — every failed mutation returns a message.
 *   2. Never leak database internals — no table names, no constraint names, no
 *      SQL. The RPCs in db/migrations/0004 already raise human sentences, so
 *      those are passed through; anything else is mapped to a safe fallback.
 */

const SAFE_SQLSTATES = new Set([
  '23514', // check_violation      — raised by our own validation
  '23503', // foreign_key_violation
  '23505', // unique_violation
  'P0002', // no_data_found        — "Person not found."
  '42501', // insufficient_privilege
]);

const FALLBACK_BY_SQLSTATE: Record<string, string> = {
  '23505': 'That record already exists.',
  '23503': 'A referenced record is missing.',
  '42501': 'You are not allowed to do that.',
  'P0002': 'That record could not be found.',
  '23514': 'That change is not valid.',
  '40001': 'Someone else changed this at the same time. Please try again.',
  '57014': 'That took too long. Please try again.',
};

/** Messages raised by our own RPCs read as sentences; DB noise does not. */
function looksLikeOurMessage(message: string): boolean {
  const trimmed = message.trim();
  if (trimmed.length === 0 || trimmed.length > 200) return false;
  if (/^(new row|duplicate key|null value|invalid input|column |relation |permission denied for)/i.test(trimmed)) {
    return false;
  }
  return /[.!?]$/.test(trimmed);
}

/**
 * GoTrue's error codes, translated.
 *
 * Auth errors never reached this function's mapping at all: they carry no
 * SQLSTATE, so every one of them fell through to the caller's fallback. A
 * password change refused because the new password matched the old one was
 * reported as "Your password could not be changed." — true, useless, and
 * unactionable.
 *
 * Unlike a database error, an auth error is safe to relay: it describes the
 * credential the user has just typed, not anything about another account. The
 * one deliberate exception is `invalid_credentials`, which stays vague on
 * purpose so the sign-in form cannot be used to discover which addresses exist.
 *
 * Kept in step with `app/lib/core/failure.dart`.
 */
const AUTH_MESSAGES: Record<string, string> = {
  invalid_credentials: 'That email and password combination is not correct.',
  invalid_grant: 'That email and password combination is not correct.',
  same_password: 'Your new password must be different from your current one.',
  weak_password:
    'That password is too weak. Use at least 10 characters, with an uppercase letter, a lowercase letter and a number.',
  over_request_rate_limit: 'Too many attempts. Wait a minute and try again.',
  over_email_send_rate_limit: 'Too many attempts. Wait a minute and try again.',
  session_not_found: 'Your session has expired. Sign in again and retry.',
  session_expired: 'Your session has expired. Sign in again and retry.',
  refresh_token_not_found: 'Your session has expired. Sign in again and retry.',
  refresh_token_already_used: 'Your session has expired. Sign in again and retry.',
  user_banned: 'This account is disabled. Contact your administrator.',
  email_not_confirmed: 'This email address has not been confirmed yet.',
  reauthentication_needed: 'Sign in again before changing your password.',
};

function authMessage(error: unknown): string | null {
  const auth = error as { code?: unknown; status?: unknown; __isAuthError?: unknown };
  // Only supabase-js auth errors, never a Postgres one — both carry a `code`,
  // and the two namespaces must not be allowed to collide.
  if (!auth?.__isAuthError) return null;
  if (typeof auth.code === 'string') {
    const known = AUTH_MESSAGES[auth.code];
    if (known) return known;
  }
  // An expired or missing token arrives as a bare 401 with no code.
  if (auth.status === 401 || auth.status === 403) {
    return 'Your session has expired. Sign in again and retry.';
  }
  return null;
}

export function friendlyMessage(error: PostgrestError | Error | unknown, fallback: string): string {
  if (!error) return fallback;

  const auth = authMessage(error);
  if (auth) return auth;

  const pgError = error as Partial<PostgrestError>;
  const code = pgError.code;

  if (typeof pgError.message === 'string' && code && SAFE_SQLSTATES.has(code)) {
    if (looksLikeOurMessage(pgError.message)) return pgError.message;
    return FALLBACK_BY_SQLSTATE[code] ?? fallback;
  }

  if (code && FALLBACK_BY_SQLSTATE[code]) return FALLBACK_BY_SQLSTATE[code];

  if (typeof pgError.message === 'string' && /fetch failed|network|ECONNREFUSED/i.test(pgError.message)) {
    return 'Could not reach the server. Check your connection and try again.';
  }

  return fallback;
}

export function fail(error: unknown, fallback: string, field?: string): ActionResult<never> {
  // Full detail stays on the server for diagnosis; only the safe sentence ships.
  if (process.env.NODE_ENV !== 'production') console.error('[action]', error);
  return field
    ? { ok: false, error: friendlyMessage(error, fallback), field }
    : { ok: false, error: friendlyMessage(error, fallback) };
}

export function ok<T>(data: T): ActionResult<T> {
  return { ok: true, data };
}

/** Wording used when a whole operation was rolled back (context.md §26). */
export const UNCHANGED = {
  settlement: 'Settlement could not be completed. Your balance has not been changed.',
  transaction: 'Transaction was not saved. Please try again.',
  person: 'Those details could not be saved. Please try again.',
  profile: 'Your profile could not be saved. Please try again.',
} as const;
