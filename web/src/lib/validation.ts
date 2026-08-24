import { z } from 'zod';
import { parseAmountToMinor } from '@/lib/money';
import { isSupportedCurrency, normaliseCode } from '@/lib/currencies';

/**
 * Centralised input validation (context.md §32).
 *
 * This is the second of three layers, never the only one: the browser gives
 * fast feedback, this runs on the server, and the database CHECK constraints
 * are the actual guarantee. A request that skips the UI still hits both of the
 * latter.
 */

const trimmedOptional = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .transform((v) => (v === '' ? null : v))
    .nullable()
    .optional();

/**
 * A currency code, validated against the one list every client shares.
 *
 * Optional throughout: a person without one is on the owner's base currency,
 * which is exactly what every person created before this feature meant.
 */
export const currencyCode = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^[A-Z]{3}$/, 'Use a three letter currency code, for example INR')
  .refine(isSupportedCurrency, 'That currency is not supported');

export const optionalCurrencyCode = z
  .union([z.literal(''), currencyCode])
  .transform((v) => (v === '' ? null : v))
  .nullable()
  .optional();

/**
 * Parse a money field for a *named* currency (upgrade §19).
 *
 * The zod schemas below cannot do this themselves: how many decimals are
 * allowed depends on a different field in the same form, and getting it wrong
 * means either rejecting ¥1000 or accepting ₹1.234. The action reads the
 * currency first and then calls this.
 */
export function parseAmountField(
  value: string,
  currency: string,
): { ok: true; minor: number } | { ok: false; error: string } {
  const text = (value ?? '').trim();
  if (text === '') return { ok: false, error: 'Enter an amount' };

  const minor = parseAmountToMinor(text, currency);
  if (minor === null) {
    const code = normaliseCode(currency);
    return {
      ok: false,
      error: `Enter a valid ${code} amount, for example 1500`,
    };
  }
  if (minor <= 0) return { ok: false, error: 'Amount must be more than zero' };
  if (minor > 9_223_372_036_854) return { ok: false, error: 'That amount is too large' };
  return { ok: true, minor };
}

/** A rate as sent by the client: an integer scaled by 1e9, or nothing. */
export const rateE9 = z
  .union([z.literal(''), z.coerce.number().int().positive()])
  .transform((v) => (v === '' ? null : (v as number)))
  .nullable()
  .optional();

/** A money field arrives as text and leaves as integer minor units. */
export const amountMinor = z
  .string()
  .trim()
  .min(1, 'Enter an amount')
  .transform((value, ctx) => {
    const minor = parseAmountToMinor(value);
    if (minor === null) {
      ctx.addIssue({ code: 'custom', message: 'Enter a valid amount, for example 1500 or 1500.50' });
      return z.NEVER;
    }
    if (minor <= 0) {
      ctx.addIssue({ code: 'custom', message: 'Amount must be more than zero' });
      return z.NEVER;
    }
    if (minor > 9_223_372_036_854) {
      ctx.addIssue({ code: 'custom', message: 'That amount is too large' });
      return z.NEVER;
    }
    return minor;
  });

export const isoDate = z
  .string()
  .trim()
  .regex(/^\d{4}-\d{2}-\d{2}$/, 'Enter a valid date')
  .refine((value) => !Number.isNaN(Date.parse(value)), 'Enter a valid date');

export const uuid = z.string().uuid('That record could not be found');

export const signInSchema = z.object({
  email: z.string().trim().min(1, 'Enter your email').email('Enter a valid email address'),
  password: z.string().min(1, 'Enter your password'),
});

export const personSchema = z.object({
  name: z.string().trim().min(1, 'Enter a name').max(120, 'That name is too long'),
  type: z.enum(['person', 'business']),
  currency: optionalCurrencyCode,
  // Opening balance (upgrade §3, §4). The amount stays text here and is parsed
  // against the chosen currency by the action.
  opening_direction: z.enum(['none', 'they_owe_me', 'i_owe_them']).default('none'),
  opening_amount: z.string().trim().optional(),
  opening_currency: optionalCurrencyCode,
  opening_rate_e9: rateE9,
  opening_converted_amount: z.string().trim().optional(),
  opening_conversion_mode: z.enum(['automatic', 'manual']).optional(),
  // Changing the currency of an account that already holds entries changes what
  // future entries default to and leaves every recorded one alone. The user is
  // told that before it happens, and the form sends the acknowledgement back.
  currency_change_confirmed: z
    .union([z.literal('on'), z.literal('true'), z.literal('')])
    .transform((v) => v === 'on' || v === 'true')
    .optional(),
  phone: trimmedOptional(32),
  email: z
    .union([z.literal(''), z.string().trim().email('Enter a valid email address')])
    .transform((v) => (v === '' ? null : v))
    .nullable()
    .optional(),
  address: trimmedOptional(500),
  notes: trimmedOptional(2000),
});

export const transactionSchema = z.object({
  person_id: uuid,
  type: z.enum(['credit', 'debit']),
  /** Raw text: parsed against `entry_currency`, which may not be the account's. */
  amount: z.string().trim().min(1, 'Enter an amount'),
  /** The currency the user typed in. Defaults to the account currency. */
  entry_currency: optionalCurrencyCode,
  /** The account currency, sent by the form so validation matches the server. */
  account_currency: optionalCurrencyCode,
  rate_e9: rateE9,
  rate_source: trimmedOptional(60),
  /** The actual converted amount, when the user overrode the rate (upgrade §40). */
  converted_amount: z.string().trim().optional(),
  conversion_mode: z.enum(['automatic', 'manual']).optional(),
  date: isoDate,
  description: trimmedOptional(500),
});

export const transactionEditSchema = transactionSchema.omit({ person_id: true }).extend({
  transaction_id: uuid,
});

export const settlementSchema = z.object({
  person_id: uuid,
  amount: z.string().trim().min(1, 'Enter an amount'),
  entry_currency: optionalCurrencyCode,
  account_currency: optionalCurrencyCode,
  rate_e9: rateE9,
  rate_source: trimmedOptional(60),
  /** The actual converted amount, when the user overrode the rate (upgrade §40). */
  converted_amount: z.string().trim().optional(),
  conversion_mode: z.enum(['automatic', 'manual']).optional(),
  direction: z.enum(['in', 'out']).optional(),
  transaction_id: z.union([uuid, z.literal('')]).optional(),
  date: isoDate,
  note: trimmedOptional(500),
});

export const profileSchema = z.object({
  name: z.string().trim().min(1, 'Enter your name').max(120),
  phone: trimmedOptional(32),
  business_name: trimmedOptional(120),
  currency: currencyCode,
});

export const adminCreateUserSchema = z.object({
  email: z.string().trim().toLowerCase().email('Enter a valid email address'),
  password: z
    .string()
    .min(10, 'Use at least 10 characters')
    .max(72, 'Use at most 72 characters')
    .refine((v) => /[a-z]/.test(v) && /[A-Z]/.test(v) && /\d/.test(v), {
      message: 'Include an uppercase letter, a lowercase letter and a number',
    }),
  name: z.string().trim().min(1, 'Enter a name').max(120),
  business_name: trimmedOptional(120),
  currency: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z]{3}$/, 'Use a three letter currency code')
    .default('INR'),
});

export const adminResetPasswordSchema = z.object({
  user_id: uuid,
  password: adminCreateUserSchema.shape.password,
});

/** Pull the first message out of a ZodError for the uniform ActionResult. */
export function firstIssue(error: z.ZodError): { error: string; field?: string } {
  const issue = error.issues[0];
  if (!issue) return { error: 'Please check the form and try again.' };
  const field = issue.path[0];
  return typeof field === 'string'
    ? { error: issue.message, field }
    : { error: issue.message };
}

/** Read a FormData into a plain object zod can parse. */
export function formObject(formData: FormData): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of formData.entries()) {
    if (typeof value === 'string') out[key] = value;
  }
  return out;
}
