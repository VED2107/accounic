import { describe, expect, it } from 'vitest';
import {
  currencyRowsFor,
  halfHasData,
  orderCurrencyRows,
} from '@/lib/currency-breakdown';
import type { CurrencyHalfBreakdown, CurrencyTotals } from '@/lib/types';

/**
 * The dashboard leads with the currency the money was entered in
 * (db/migrations/0024). `db/tests/12_dashboard_currency_breakdown.sql` proves
 * the figures; this pins the half the web client owns — which rows it pulls
 * from `totals_by_currency`, and the order it shows them in.
 */

function half(over: Partial<CurrencyHalfBreakdown> = {}): CurrencyHalfBreakdown {
  return {
    currency: 'AED',
    base_currency: 'INR',
    credit: 6000,
    debit: 0,
    settled: 0,
    receivable: 6000,
    payable: 0,
    net: 6000,
    net_base_minor: 144000,
    today: 0,
    today_count: 0,
    entry_count: 2,
    people_count: 2,
    ...over,
  };
}

function totals(over: Partial<CurrencyTotals> = {}): CurrencyTotals {
  return {
    currency: 'AED',
    base_currency: 'INR',
    gross_credit: 21000,
    gross_debit: 0,
    gross_settled: 0,
    net_position: 21000,
    net_base_minor: 504000,
    entry_count: 4,
    people_count: 2,
    ...over,
  };
}

describe('currencyRowsFor', () => {
  it('returns the cash or opening object of every row that has one', () => {
    const rows: CurrencyTotals[] = [
      totals({ currency: 'INR', cash: half({ currency: 'INR' }), opening: half({ currency: 'INR', credit: 3000 }) }),
      totals({ currency: 'AED', cash: half({ currency: 'AED' }), opening: half({ currency: 'AED', credit: 15000 }) }),
    ];
    expect(currencyRowsFor(rows, 'cash').map((r) => r.currency)).toEqual(['INR', 'AED']);
    expect(currencyRowsFor(rows, 'opening').map((r) => r.credit)).toEqual([3000, 15000]);
  });

  it('returns nothing for a database that has not run 0024 (no cash/opening objects)', () => {
    expect(currencyRowsFor([totals(), totals({ currency: 'USD' })], 'cash')).toEqual([]);
  });
});

describe('halfHasData', () => {
  it('is false only when credit, debit and settled are all zero', () => {
    expect(halfHasData(half({ credit: 0, debit: 0, settled: 0 }))).toBe(false);
    expect(halfHasData(half({ credit: 0, debit: 0, settled: 10 }))).toBe(true);
    expect(halfHasData(half({ credit: 6000 }))).toBe(true);
  });
});

describe('orderCurrencyRows', () => {
  it('puts the base currency first, then the rest alphabetically', () => {
    const rows = [
      half({ currency: 'USD' }),
      half({ currency: 'AED' }),
      half({ currency: 'INR' }),
      half({ currency: 'EUR' }),
    ];
    expect(orderCurrencyRows(rows, 'INR').map((r) => r.currency)).toEqual([
      'INR',
      'AED',
      'EUR',
      'USD',
    ]);
  });

  it('drops currencies that carry no data, keeping the rest in order', () => {
    const rows = [
      half({ currency: 'INR', credit: 0, debit: 0, settled: 0 }),
      half({ currency: 'AED', credit: 6000 }),
      half({ currency: 'USD', credit: 0, debit: 0, settled: 0 }),
    ];
    expect(orderCurrencyRows(rows, 'INR').map((r) => r.currency)).toEqual(['AED']);
  });

  it('never mutates its input', () => {
    const rows = [half({ currency: 'USD' }), half({ currency: 'INR' })];
    orderCurrencyRows(rows, 'INR');
    expect(rows.map((r) => r.currency)).toEqual(['USD', 'INR']);
  });

  it('20 AED + 40 AED is one AED row of 60 — never split, never reconverted', () => {
    // The two entries have already been summed by the database into one
    // `cash` object; the client just renders it. `net` is the original-currency
    // figure and `net_base_minor` is the only converted number.
    const aed = half({ currency: 'AED', credit: 6000, receivable: 6000, net: 6000, net_base_minor: 144000 });
    const [row] = orderCurrencyRows([aed], 'INR');
    expect(row!.net).toBe(6000);
    expect(row!.currency).toBe('AED');
  });
});
