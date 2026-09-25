import { writeFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { buildPersonStatement } from '@/lib/pdf/statement';
import { orderCurrencyRows, workspaceTotal } from '@/lib/currency-breakdown';
import type { PersonPage } from '@/lib/types';

import aedLedger from '../../../../shared/fixtures/person-page-aed-ledger.json';
import inrLedger from '../../../../shared/fixtures/person-page-inr-ledger.json';

/**
 * Dashboard = Person Details = Person statement.
 *
 * The fixtures are real `person_page()` responses from
 * db/tools/smoke-person-parity.mjs: a workspace in INR whose history was entered
 * at 1 AED = ₹22.50 while today's cached rate is ₹26.32. The dirham account
 * holds ₹1,05,000 entered as rupees and AED 1,000 entered as dirhams.
 *
 * The bug: the person page and its statement printed the whole dirham position
 * re-converted at today's rate (₹96,491.05), re-pricing rupees that had been
 * typed as rupees. The dashboard counts those rupees as the rupees they were;
 * so must everything else.
 */
const aed = aedLedger as unknown as PersonPage;
const inr = inrLedger as unknown as PersonPage;

describe('person workspace figure', () => {
  it('keeps rupees entered as rupees, as the dashboard does', () => {
    const rows = aed.regular_by_currency;
    const rupees = rows.find((r) => r.currency === 'INR')!;
    const dirhams = rows.find((r) => r.currency === 'AED')!;
    expect(rupees.net).toBe(10_500_000);
    expect(workspaceTotal(rows, 'AED', 'INR')).toBe(rupees.net + dirhams.net_base_minor!);
    expect(workspaceTotal(rows, 'AED', 'INR')).toBe(7_868_421);
  });

  it('is no longer the whole position re-converted at today’s rate', () => {
    expect(aed.regular.position_base).toBe(9_649_105);
    expect(workspaceTotal(aed.regular_by_currency, 'AED', 'INR')).not.toBe(aed.regular.position_base);
  });

  it('is unknown, not zero, when a foreign row has no rate', () => {
    const rows = aed.regular_by_currency.map((r) =>
      r.currency === 'AED' ? { ...r, net_base_minor: null } : r,
    );
    expect(workspaceTotal(rows, 'AED', 'INR')).toBeNull();
  });

  it('on a rupee account, uses the rupees the ledger booked — equal to the headline', () => {
    // A dirham entry booked at ₹22.50 is not re-priced at today's ₹26.32.
    const rows = inr.regular_by_currency;
    const dirhams = rows.find((r) => r.currency === 'AED')!;
    expect(dirhams.net_ledger_minor).not.toBe(dirhams.net_base_minor);
    expect(workspaceTotal(rows, 'INR', 'INR')).toBe(inr.regular.position);
    expect(workspaceTotal(inr.opening_by_currency, 'INR', 'INR')).toBe(
      inr.opening_position.position,
    );
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
  ] as const) {
    it(`builds the ${name} statement`, async () => {
      const bytes = await buildPersonStatement({
        page,
        me: null,
        truncated: false,
        rowsCovered: page.timeline.length,
      });
      expect(bytes.byteLength).toBeGreaterThan(1000);
      // Set PARITY_OUT to keep the file, so its text can be read back and
      // compared with the screen (see docs/currency-parity.md).
      if (process.env.PARITY_OUT) {
        writeFileSync(`${process.env.PARITY_OUT}/web-${name}.pdf`, bytes);
      }
    });
  }
});
