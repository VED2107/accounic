import { writeFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { buildPersonStatement } from '@/lib/pdf/statement';
import { baseEquivalent, orderCurrencyRows, positionInBase } from '@/lib/currency-breakdown';
import type { PersonPage } from '@/lib/types';

import aedLedger from '../../../../shared/fixtures/person-page-aed-ledger.json';
import inrLedger from '../../../../shared/fixtures/person-page-inr-ledger.json';
import aedSettled from '../../../../shared/fixtures/person-page-aed-settled.json';
import dashboard from '../../../../shared/fixtures/dashboard-figures.json';

/**
 * Dashboard = Person Details = Person statement.
 *
 * The fixtures are real `person_page()` responses, and the dashboard's own
 * per-account figures, from db/tools/smoke-person-parity.mjs: an INR workspace
 * whose history was entered at 1 AED = ₹22.50 and ₹24.00 while today's cached
 * rate is ₹26.32.
 *
 * - Dubai Traders, kept in AED: rupee entries (one manual), a dirham entry, a
 *   rupee opening balance, a partial settlement paid in rupees, a transfer in.
 * - Mumbai Supplier, kept in INR: dirham entries at two old rates and one
 *   manual, a dirham opening balance, a partial settlement, a transfer out.
 * - Gulf Settled, kept in AED: AED 10,000 owed, repaid as ₹2,25,000 at ₹22.50.
 *
 * The bug: v1.16 showed each account in the workspace currency by re-adding its
 * per-currency rows — rupees at face, dirhams at today's rate. On an account
 * holding both, that is not the sum the ledger keeps, and it is not the figure
 * the dashboard counts: Gulf Settled, at zero on the dashboard, read ₹38,157.89.
 */
const aed = aedLedger as unknown as PersonPage;
const inr = inrLedger as unknown as PersonPage;
const settled = aedSettled as unknown as PersonPage;
const people = dashboard.people as Record<string, { cash_in_hand_base: number; opening_net_base: number }>;

const pages = [aed, inr, settled];

describe('person workspace figure = the dashboard’s', () => {
  for (const page of pages) {
    it(`${page.person.name}: cash in hand and opening`, () => {
      const d = people[page.person.name]!;
      expect(positionInBase(page.regular, page.currency, 'INR')).toBe(d.cash_in_hand_base);
      expect(positionInBase(page.opening_position, page.currency, 'INR')).toBe(d.opening_net_base);
    });
  }

  it('summed over the workspace, is the dashboard’s Total in INR', () => {
    const cash = pages.reduce((t, p) => t + positionInBase(p.regular, p.currency, 'INR')!, 0);
    const opening = pages.reduce(
      (t, p) => t + positionInBase(p.opening_position, p.currency, 'INR')!,
      0,
    );
    expect(cash).toBe(dashboard.cash_in_hand);
    expect(opening).toBe(dashboard.opening);
  });

  it('an AED account settled in rupees reads zero, as on the dashboard', () => {
    expect(settled.regular.position).toBe(0);
    expect(positionInBase(settled.regular, 'AED', 'INR')).toBe(0);
    // What v1.16 printed: ₹2,25,000 entered, less AED 10,000 at today's rate.
    const rows = settled.regular_by_currency;
    const rupees = rows.find((r) => r.currency === 'INR')!;
    const dirhams = rows.find((r) => r.currency === 'AED')!;
    expect(rupees.net + dirhams.net_base_minor!).toBe(-3_815_789);
  });

  it('a rupee account sums its dirham entries at the rupees booked, never today', () => {
    const dirhams = inr.regular_by_currency.find((r) => r.currency === 'AED')!;
    expect(dirhams.net_ledger_minor).not.toBe(dirhams.net_base_minor);
    expect(positionInBase(inr.regular, 'INR', 'INR')).toBe(inr.regular.position);
    const booked = inr.regular_by_currency.reduce((t, r) => t + r.net_ledger_minor!, 0);
    expect(booked).toBe(inr.regular.position);
    expect(baseEquivalent(dirhams, 'INR')).toEqual({ minor: dirhams.net_ledger_minor, asBooked: true });
  });

  it('a dirham account’s position is the sum of what each entry booked', () => {
    const booked = aed.regular_by_currency.reduce((t, r) => t + r.net_ledger_minor!, 0);
    expect(booked).toBe(aed.regular.position);
    const manual = aed.timeline.find((t) => t.conversion_mode === 'manual')!;
    expect(manual.amount_minor).toBe(260_000);
  });

  it('is unknown, not zero, when there is no rate', () => {
    expect(positionInBase({ ...aed.regular, position_base: null }, 'AED', 'INR')).toBeNull();
  });

  it('orders the workspace currency first, as the page and dashboard do', () => {
    expect(orderCurrencyRows(aed.regular_by_currency, 'INR').map((r) => r.currency)).toEqual([
      'INR',
      'AED',
    ]);
  });
});

describe('person statement renders over real data', () => {
  for (const [name, page] of [
    ['aed-ledger', aed],
    ['inr-ledger', inr],
    ['aed-settled', settled],
  ] as const) {
    it(`builds the ${name} statement`, async () => {
      const bytes = await buildPersonStatement({
        page,
        me: null,
        truncated: false,
        rowsCovered: page.timeline.length,
      });
      expect(bytes.byteLength).toBeGreaterThan(1000);
      // Set PARITY_OUT to keep the file; db/tools/verify-statement-pdfs.mjs
      // reads its text back and checks every figure against the dashboard's.
      if (process.env.PARITY_OUT) {
        writeFileSync(`${process.env.PARITY_OUT}/web-${name}.pdf`, bytes);
      }
    });
  }
});
