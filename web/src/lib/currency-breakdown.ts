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

/**
 * What `row` is worth in the workspace currency on an account kept in
 * `ledgerCurrency`, and whether that figure is the one the ledger BOOKED.
 *
 * - A row already in the workspace currency has no equivalent — it is one.
 * - On an account kept in the workspace currency, the ledger froze every
 *   foreign entry at the rate it was entered at; `net_ledger_minor` is that
 *   frozen figure (db/migrations/0033), used as booked and never re-priced.
 * - Otherwise no workspace-currency figure was ever recorded, and the only one
 *   there is is the dashboard's `net_base_minor`, at today's rate.
 *
 * Twin of `CurrencyHalfBreakdown.baseEquivalent` in app/lib/data/models.dart.
 */
export function baseEquivalent(
  row: CurrencyHalfBreakdown,
  ledgerCurrency: string,
): { minor: number; asBooked: boolean } | null {
  if (row.currency === row.base_currency) return null;
  if (ledgerCurrency === row.base_currency && row.net_ledger_minor != null) {
    return { minor: row.net_ledger_minor, asBooked: true };
  }
  if (row.net_base_minor == null) return null;
  return { minor: row.net_base_minor, asBooked: false };
}

/**
 * The workspace-currency total of `rows` for an account kept in
 * `ledgerCurrency`: each row at `baseEquivalent`, a workspace-currency row at
 * its entered net. Null when a foreign row has no figure — "not known", never
 * zero.
 *
 * This is what the person page and its statement show in the workspace
 * currency. It replaced a whole-position conversion at today's rate, which
 * re-priced rupees that had been entered as rupees: a dirham account holding
 * rupee entries came out lakhs away from the dashboard for the same money. On
 * an account kept in the workspace currency it equals the headline exactly.
 * Twin of `CurrencyHalfBreakdown.workspaceTotal` in app/lib/data/models.dart.
 */
export function workspaceTotal(
  rows: CurrencyHalfBreakdown[],
  ledgerCurrency: string,
  baseCurrency: string,
): number | null {
  let total = 0;
  for (const row of rows) {
    if (row.currency === baseCurrency) {
      total += row.net;
      continue;
    }
    const equivalent = baseEquivalent({ ...row, base_currency: baseCurrency }, ledgerCurrency);
    if (equivalent === null) {
      if (row.net === 0 && row.net_ledger_minor == null) continue;
      return null;
    }
    total += equivalent.minor;
  }
  return total;
}
