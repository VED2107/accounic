/**
 * Reading a rate provider's answer (upgrade §6, §7).
 *
 * Split out of `rates.ts` for one reason: `rates.ts` is `server-only` and
 * cannot be imported by a test, and the interesting failures here are the ones
 * a provider hands you rather than the ones the network does — a 200 with
 * `result: "error"`, a rates map of strings, a zero, a null. This module is
 * pure, so all of that is testable, and `rates.ts` keeps the fetching.
 *
 * Mirrored by `app/lib/data/rate_source.dart`.
 */

export const PRIMARY_URL = 'https://open.er-api.com/v6/latest';
export const FALLBACK_URL = 'https://api.frankfurter.dev/v1/latest';

export interface RateTable {
  /** Decimal rates as published: one base unit costs this many of the quote. */
  rates: Record<string, number>;
  asOf: string;
  source: string;
}

function isoDay(value: unknown): string {
  if (typeof value === 'string') {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) return parsed.toISOString().slice(0, 10);
  }
  return new Date().toISOString().slice(0, 10);
}

/**
 * Keep only the entries that are actually numbers.
 *
 * A provider that sends `"84.2"` as a string, or `null` for a currency it has
 * stopped publishing, is not an error worth failing the whole table over — the
 * other 160 rates are still good. The unusable entry is dropped, and the caller
 * discovers there is no rate for that one pair, which is the truth.
 */
function numbersOnly(raw: unknown): Record<string, number> {
  if (!raw || typeof raw !== 'object') return {};
  const out: Record<string, number> = {};
  for (const [code, value] of Object.entries(raw as Record<string, unknown>)) {
    if (typeof value === 'number' && Number.isFinite(value)) out[code.toUpperCase()] = value;
  }
  return out;
}

/** open.er-api.com's payload as a table, or null when it is not one. */
export function parsePrimary(payload: unknown): RateTable | null {
  if (!payload || typeof payload !== 'object') return null;
  const body = payload as { result?: unknown; rates?: unknown; time_last_update_utc?: unknown };
  if (body.result !== 'success') return null;
  const rates = numbersOnly(body.rates);
  if (Object.keys(rates).length === 0) return null;
  return { rates, asOf: isoDay(body.time_last_update_utc), source: 'open.er-api.com' };
}

/** frankfurter.dev's payload as a table, or null when it is not one. */
export function parseFallback(payload: unknown): RateTable | null {
  if (!payload || typeof payload !== 'object') return null;
  const body = payload as { rates?: unknown; date?: unknown };
  const rates = numbersOnly(body.rates);
  if (Object.keys(rates).length === 0) return null;
  return {
    rates,
    asOf: typeof body.date === 'string' ? body.date : isoDay(null),
    source: 'frankfurter.dev (ECB)',
  };
}
