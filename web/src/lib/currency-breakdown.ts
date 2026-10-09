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
 * One half of an account (cash in hand or the opening book) in the workspace
 * currency: EXACTLY the figure the dashboard counts for this account.
 *
 * The dashboard's "Total in" line and its net position are sums, over every
 * account, of `person_balances.cash_in_hand_base` / `opening_net_base` — which
 * the person page receives as `regular.position_base` /
 * `opening_position.position_base`. So this returns that figure, untouched:
 *
 * - On an account kept in the workspace currency it is the position itself.
 *   Every foreign entry on it is already summed at the amount the ledger
 *   booked for it (its historical or manual rate) — no rate is applied here.
 * - On an account kept in another currency, the position is a debt in THAT
 *   currency. Its entries were booked into it at their own historical rates;
 *   the one conversion left is the account's balance into the workspace
 *   currency, done by the database exactly as the dashboard does it.
 *
 * It replaced `workspaceTotal`, which added the per-entry-currency nets
 * together instead — workspace-currency entries at face value plus foreign
 * ones at today's rate. On an account holding both, that is a different sum
 * from the one the ledger keeps: the rate movement between the halves turned
 * into money that was never owed. A dirham account settled in rupees (the
 * ledger at exactly zero, the dashboard at zero) read as ₹1,63,116.75 owed.
 *
 * Null means "no rate yet" — not known, never zero.
 * Twin of `PositionSplit.inBaseMinor` in app/lib/data/models.dart.
 */
export function positionInBase(
  split: { position: number; position_base: number | null },
  ledgerCurrency: string,
  baseCurrency: string,
): number | null {
  if (ledgerCurrency === baseCurrency) return split.position;
  return split.position_base;
}
