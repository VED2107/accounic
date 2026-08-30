import type { CurrencyHalfBreakdown, CurrencyTotals } from '@/lib/types';

/**
 * Pulling the per-currency cash / opening breakdown out of `totals_by_currency`
 * (db/migrations/0024) and ordering it the way the brief asks: the workspace
 * (base) currency first, then the rest alphabetically, and never a currency
 * that carries no data.
 *
 * These are pure so they can be pinned by a test without rendering anything.
 */

/** A currency half carries data when any of its three totals is non-zero. */
export function halfHasData(row: CurrencyHalfBreakdown): boolean {
  return row.credit !== 0 || row.debit !== 0 || row.settled !== 0;
}

/**
 * The `cash` or `opening` object of every currency row that has one — a
 * database that has not run 0024 has neither, and this returns [].
 */
export function currencyRowsFor(
  totals: CurrencyTotals[],
  half: 'cash' | 'opening',
): CurrencyHalfBreakdown[] {
  const out: CurrencyHalfBreakdown[] = [];
  for (const row of totals) {
    const part = half === 'cash' ? row.cash : row.opening;
    if (part) out.push(part);
  }
  return out;
}

/** Base currency first, then alphabetical. Empty currencies dropped. */
export function orderCurrencyRows(
  rows: CurrencyHalfBreakdown[],
  baseCurrency: string,
): CurrencyHalfBreakdown[] {
  return rows
    .filter(halfHasData)
    .slice()
    .sort((a, b) => {
      if (a.currency === b.currency) return 0;
      if (a.currency === baseCurrency) return -1;
      if (b.currency === baseCurrency) return 1;
      return a.currency.localeCompare(b.currency);
    });
}
