import { describe, expect, it } from 'vitest';
import { bookedEquivalent, outstandingOf, positionInBase } from '@/lib/currency-breakdown';
import type { PersonPage } from '@/lib/types';

import aedLedger from '../../../shared/fixtures/person-page-aed-ledger.json';
import inrLedger from '../../../shared/fixtures/person-page-inr-ledger.json';
import aedSettled from '../../../shared/fixtures/person-page-aed-settled.json';

/**
 * Every historical figure on the person page is the one BOOKED when the entry
 * was made (db/migrations/0034) — never re-priced at today's rate.
 *
 * Fixtures: real person_page() responses (db/tools/smoke-person-parity.mjs) for
 * an INR workspace whose history was entered at 1 AED = ₹22.50 and ₹24.00 while
 * today's cached rate is ₹26.32.
 */
const aed = aedLedger as unknown as PersonPage;
const inr = inrLedger as unknown as PersonPage;
const settled = aedSettled as unknown as PersonPage;

const row = (page: PersonPage, note: string) => page.timeline.find((t) => t.note === note)!;

describe('timeline rows keep the rate they were entered at', () => {
  it('a dirham entry on a rupee account is the rupees it was booked at', () => {
    // 2,000 AED at ₹22.50 = ₹45,000, not 2,000 × today's ₹26.32 = ₹52,640.
    const entry = row(inr, 'dirhams at 22.50');
    expect(entry.entry_amount_minor).toBe(200_000);
    expect(entry.amount_minor).toBe(4_500_000);
    expect(entry.amount_base_minor).toBe(4_500_000);
  });

  it('a manual conversion stays the figure typed', () => {
    expect(row(inr, 'dirhams, manual 2,700 rupees').amount_base_minor).toBe(270_000);
  });

  it('a rupee entry on a dirham account is its rupees at face', () => {
    expect(row(aed, 'rupees at 22.50').amount_base_minor).toBe(10_000_000);
    expect(row(aed, 'part paid in rupees at 24.00').amount_base_minor).toBe(2_000_000);
  });

  it('a dirham entry on a dirham account has no rupee figure — none was ever recorded', () => {
    expect(row(aed, 'dirhams, native').amount_base_minor).toBeNull();
    expect(row(settled, 'dirhams borrowed').amount_base_minor).toBeNull();
  });

  it('every row the screen sums is the ledger figure, so rows reconcile to the headline', () => {
    for (const page of [aed, inr, settled]) {
      const sum = page.regular_by_currency.reduce((t, r) => t + (r.net_ledger_minor ?? 0), 0);
      expect(sum).toBe(page.regular.position);
    }
  });
});

describe('per-currency rows show what was booked, in the account’s currency', () => {
  it('a dirham row on a rupee account: the rupees booked, not today’s conversion', () => {
    const dirhams = inr.regular_by_currency.find((r) => r.currency === 'AED')!;
    expect(dirhams.net_base_minor).not.toBe(dirhams.net_ledger_minor); // today's rate differs
    expect(bookedEquivalent(dirhams, 'INR')).toEqual({ minor: 3_970_000, currency: 'INR' });
  });

  it('a rupee row on a dirham account: the dirhams it was booked at', () => {
    const rupees = settled.regular_by_currency.find((r) => r.currency === 'INR')!;
    expect(bookedEquivalent(rupees, 'AED')).toEqual({ minor: 1_000_000, currency: 'AED' });
  });

  it('a row in the account’s own currency has no equivalent', () => {
    const dirhams = aed.regular_by_currency.find((r) => r.currency === 'AED')!;
    expect(bookedEquivalent(dirhams, 'AED')).toBeNull();
  });

  it('says nothing rather than re-price when the booked figure is missing', () => {
    expect(bookedEquivalent({ currency: 'AED', net_ledger_minor: null }, 'INR')).toBeNull();
  });

  it('a changed market rate cannot move a booked figure', () => {
    const dirhams = inr.regular_by_currency.find((r) => r.currency === 'AED')!;
    const repriced = { ...dirhams, net_base_minor: dirhams.net_base_minor! * 2 };
    expect(bookedEquivalent(repriced, 'INR')).toEqual(bookedEquivalent(dirhams, 'INR'));
  });
});

describe('outstanding is the net position, as the dashboard counts it', () => {
  it('a fully settled account shows nothing to receive or pay', () => {
    // Gulf Settled: AED 10,000 borrowed, repaid ₹2,25,000. Both rows stay open
    // in the engine's gross figures; the account is square.
    expect(settled.regular.receivable).toBe(1_000_000);
    expect(settled.regular.payable).toBe(1_000_000);
    expect(outstandingOf(settled.regular.position)).toEqual({ receivable: 0, payable: 0 });
    expect(positionInBase(settled.regular, 'AED', 'INR')).toBe(0);
  });

  it('a partial settlement leaves exactly the remainder', () => {
    expect(outstandingOf(inr.regular.position)).toEqual({ receivable: 2_470_000, payable: 0 });
  });

  it('mixed currencies net to the booked position', () => {
    expect(outstandingOf(aed.regular.position)).toEqual({ receivable: 626_666, payable: 0 });
    expect(outstandingOf(-500)).toEqual({ receivable: 0, payable: 500 });
  });

  it('the opening book is counted on its own, never inside cash in hand', () => {
    expect(aed.opening_position.position).not.toBe(0);
    expect(outstandingOf(aed.regular.position).receivable).toBe(aed.regular.position);
  });
});
