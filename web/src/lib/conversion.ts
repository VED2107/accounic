import { normaliseCode } from '@/lib/currencies';
import { parseAmountField } from '@/lib/validation';
import type { ConversionMode } from '@/lib/types';

/**
 * The conversion arguments every money-writing RPC takes (upgrade §5, §40).
 *
 * When the entry currency is the account currency this is all nulls and the
 * database stores a plain amount, exactly as it did before currency existed.
 * When it is not, the *entered* figure is what travels and the database derives
 * the account amount from it — the client never sends a converted number it
 * worked out itself.
 *
 * The one exception is the manual amount, and it is an exception on purpose: it
 * is not derived from anything. It is what the user says actually changed
 * hands, so there is nothing for the database to recompute it from, and it
 * travels beside the automatic figure rather than instead of it.
 *
 * This module is deliberately free of server-only imports so the rule can be
 * tested directly rather than through a server action.
 */
/**
 * The provenance a hand-typed rate is stored under (upgrade §45).
 *
 * One string, defined once, matching `public.rate_is_manual()` in
 * db/migrations/0018. A row carrying it is a row where a human decided the
 * rate: it is stored in `exchange_rate_e9` like any other rate, frozen on the
 * row like any other, and every later automatic rate leaves it alone — no read
 * path re-derives a stored amount from a current rate.
 *
 * Deliberately not the word 'manual': 0011's write RPCs already default a
 * missing source to that, so rows written by a client that sent none carry it
 * without anybody having typed a rate.
 */
export const MANUAL_RATE_SOURCE = 'manual-rate';

/** True when a stored row's rate was typed by a human rather than fetched. */
export function rateIsManual(source: string | null | undefined): boolean {
  return (source ?? '').trim().toLowerCase() === MANUAL_RATE_SOURCE;
}

export interface ConversionArgs {
  p_amount_minor: number | null;
  p_entered_amount_minor: number | null;
  p_entered_currency: string | null;
  p_exchange_rate_e9: number | null;
  p_rate_source: string | null;
  p_converted_amount_minor: number | null;
  p_conversion_mode: ConversionMode | null;
}

export function conversionArgs(
  minor: number,
  entryCurrency: string,
  accountCurrency: string,
  rateE9: number | null | undefined,
  rateSource: string | null | undefined,
  convertedMinor: number | null = null,
): ConversionArgs {
  const entry = normaliseCode(entryCurrency);
  const account = normaliseCode(accountCurrency);

  if (!entry || entry === account) {
    return {
      p_amount_minor: minor,
      p_entered_amount_minor: null,
      p_entered_currency: null,
      p_exchange_rate_e9: null,
      p_rate_source: null,
      p_converted_amount_minor: null,
      p_conversion_mode: null,
    };
  }

  return {
    p_amount_minor: null,
    p_entered_amount_minor: minor,
    p_entered_currency: entry,
    p_exchange_rate_e9: rateE9 ?? null,
    p_rate_source: rateSource ?? null,
    // The mode is stated rather than inferred, so that switching an entry back
    // to automatic is a thing the client can say — not merely the absence of
    // something it forgot to send.
    p_converted_amount_minor: convertedMinor,
    p_conversion_mode: convertedMinor === null ? 'automatic' : 'manual',
  };
}

/**
 * The actual converted amount, when the form says there is one.
 *
 * Only `mode === 'manual'` counts. A stale value left in the input after the
 * user switched back to the automatic conversion must not quietly become the
 * ledger figure, so the mode — not the presence of text — decides.
 *
 * The text is parsed against the ACCOUNT currency, never the entry one: it is
 * the amount that landed in the account, which is the whole point of it.
 * Getting that pair the wrong way round is how AED 43 becomes Rs 43.
 */
export function manualMinor(
  text: string | null | undefined,
  mode: ConversionMode | null | undefined,
  accountCurrency: string,
): { minor: number | null } | { error: string } {
  if (mode !== 'manual') return { minor: null };

  const typed = (text ?? '').trim();
  if (typed === '') {
    return {
      error: `Enter the actual amount in ${normaliseCode(accountCurrency)}, or switch back to the automatic conversion.`,
    };
  }

  const parsed = parseAmountField(typed, accountCurrency);
  if (!parsed.ok) return { error: parsed.error };
  return { minor: parsed.minor };
}
