import 'server-only';

import { createClient } from '@/lib/supabase/server';
import {
  invertRateE9,
  isSupportedCurrency,
  isUsableRateE9,
  normaliseCode,
  RATE_SCALE,
  usableRateToE9,
} from '@/lib/currencies';
import {
  FALLBACK_URL,
  parseFallback,
  parsePrimary,
  PRIMARY_URL,
  type RateTable,
} from '@/lib/rate-source';

/**
 * Exchange rates (upgrade §6, §7).
 *
 * Two free, key-less sources, in this order:
 *
 *   1. open.er-api.com — the open endpoint of ExchangeRate-API. Daily rates,
 *      no key, no attribution requirement, and 160-odd currencies, which is
 *      what settles it: the Gulf currencies this product is actually used with
 *      (AED, SAR, QAR, KWD) are not published by the ECB at all.
 *   2. api.frankfurter.dev — ECB reference rates. Narrower coverage, but an
 *      impeccable source, and a useful second opinion when the first is down.
 *
 * Neither is paid and neither needs an account, which was a requirement rather
 * than a preference.
 *
 * The rules that matter more than the source:
 *   * A rate is fetched at most once a day per base currency. Everything else
 *     is served from `public.exchange_rates`, which is per-owner and therefore
 *     shared across that user's web, Windows and Android clients.
 *   * A cached rate is used when the network is unavailable, and is labelled as
 *     cached so the user knows what they are looking at.
 *   * A missing rate never blocks a save. It blocks *conversion*, and the user
 *     is told to enter the amount in the account's currency instead.
 */

/** How long a cached rate is considered current before a refresh is attempted. */
const FRESH_FOR_MS = 12 * 60 * 60 * 1000;

/** Requests are given a short leash: a slow rate API must not slow down a save. */
const TIMEOUT_MS = 4000;

export interface Rate {
  from: string;
  to: string;
  /** One `from` costs rateE9/1e9 `to`. */
  rateE9: number;
  asOf: string;
  source: string;
  /** True when this came from the cache without a successful refresh. */
  cached: boolean;
  /** True when the cached rate is older than a day and could not be refreshed. */
  stale: boolean;
}

interface RateRow {
  base: string;
  quote: string;
  rate_e9: number;
  as_of: string;
  source: string;
  fetched_at: string;
}

async function fetchJson(url: string): Promise<unknown | null> {
  try {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(TIMEOUT_MS),
      // Rates change once a day; Next's default caching would be wrong in both
      // directions, so the freshness decision is made here and only here.
      cache: 'no-store',
    });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    // Offline, DNS failure, timeout, malformed JSON — all the same answer to
    // the caller: no rate from this source right now.
    return null;
  }
}

/**
 * Pull a full rate table for one base currency. Null when both sources fail —
 * including when they answer with something that is not a rate table at all.
 * The shape rules live in `rate-source.ts`, where they can be tested.
 */
export async function fetchRateTable(base: string): Promise<RateTable | null> {
  const code = normaliseCode(base);
  if (!isSupportedCurrency(code)) return null;

  const primary = parsePrimary(await fetchJson(`${PRIMARY_URL}/${code}`));
  if (primary) return primary;

  return parseFallback(await fetchJson(`${FALLBACK_URL}?base=${code}`));
}

async function cachedRow(base: string, quote: string): Promise<RateRow | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from('exchange_rates')
    .select('base, quote, rate_e9, as_of, source, fetched_at')
    .in('base', [base, quote])
    .in('quote', [base, quote])
    .limit(2);

  const rows = (data ?? []) as RateRow[];
  return (
    rows.find((r) => r.base === base && r.quote === quote) ??
    rows.find((r) => r.base === quote && r.quote === base) ??
    null
  );
}

/**
 * A cached row as a usable rate, or null when the row cannot be trusted.
 *
 * A stored zero, a negative, or a figure so large that inverting it overflows
 * is not a rate — it is a bad row, and using it would quietly change the money.
 * Refusing it here puts the caller on the same path as "no rate at all", which
 * the UI already handles honestly.
 */
function rowToRate(row: RateRow, from: string, to: string, cached: boolean): Rate | null {
  const direct = row.base === from && row.quote === to;
  const stored = Number(row.rate_e9);
  if (!isUsableRateE9(stored)) return null;

  const rateE9 = direct ? stored : invertRateE9(stored);
  if (rateE9 === null) return null;

  const age = Date.now() - new Date(row.fetched_at).getTime();
  return {
    from,
    to,
    rateE9,
    asOf: row.as_of,
    source: row.source,
    cached,
    stale: cached && age > FRESH_FOR_MS,
  };
}

/** Store a fetched table against the caller's workspace. */
async function cacheTable(base: string, table: RateTable): Promise<void> {
  const supabase = await createClient();
  await supabase.rpc('upsert_exchange_rates', {
    p_base: base,
    p_rates: table.rates,
    p_as_of: table.asOf,
    p_source: table.source,
  });
}

/**
 * The rate to use for `from` -> `to` right now.
 *
 * Cache first, network only when the cache is missing or a day old, and the
 * cached value again if the network says nothing. Returns null only when there
 * has never been a rate for this pair and there is no way to get one — which
 * the UI turns into "enter the amount in the account's currency", not into a
 * failed save.
 */
export async function getRate(from: string, to: string): Promise<Rate | null> {
  const source = normaliseCode(from);
  const target = normaliseCode(to);

  if (!source || !target) return null;
  if (source === target) {
    return {
      from: source,
      to: target,
      rateE9: RATE_SCALE,
      asOf: new Date().toISOString().slice(0, 10),
      source: 'identity',
      cached: false,
      stale: false,
    };
  }
  if (!isSupportedCurrency(source) || !isSupportedCurrency(target)) return null;

  const existing = await cachedRow(source, target);
  const cached = existing ? rowToRate(existing, source, target, true) : null;
  const fresh =
    existing && Date.now() - new Date(existing.fetched_at).getTime() < FRESH_FOR_MS;

  if (cached && fresh) return cached;

  const table = await fetchRateTable(source);
  const live = table ? usableRateToE9(table.rates[target]) : null;
  if (table && live !== null) {
    await cacheTable(source, table);
    return {
      from: source,
      to: target,
      rateE9: live,
      asOf: table.asOf,
      source: table.source,
      cached: false,
      stale: false,
    };
  }

  // Offline, the source does not publish this pair, or it published a figure
  // that is not a rate. Whatever is cached is better than refusing to show the
  // user a number — but only if the cache itself is usable.
  return cached;
}

/** A short line for the UI: where this number came from and how old it is. */
export function rateProvenance(rate: Rate): string {
  if (rate.source === 'identity') return 'Same currency';
  if (!rate.cached) return `Live rate · ${rate.source} · ${rate.asOf}`;
  if (rate.stale) return `Cached rate from ${rate.asOf} · offline`;
  return `Cached rate · ${rate.asOf}`;
}
