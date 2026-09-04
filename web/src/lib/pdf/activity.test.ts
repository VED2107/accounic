import { describe, expect, it } from 'vitest';
import { PDFDocument } from 'pdf-lib';

import { renderActivityPdf } from '@/lib/pdf/activity';
import { ALL_ACTIVITY, dayRange } from '@/lib/export/activity';
import type { ExportBundle, ExportEntry, ExportHeader } from '@/lib/export/types';

/**
 * The Activity PDF.
 *
 * A PDF that is not a PDF is worse than none: it opens to an error in whatever
 * reader the user has and looks like our fault twice. These check that it is a
 * real file, that it paginates rather than drawing off the bottom of the page,
 * and that it names itself after the feed rather than after the ledger.
 */

function header(): ExportHeader {
  return {
    schema_version: 1,
    generator: 'accounic',
    exported_at: '2026-09-04T10:00:00Z',
    filters: {
      from: null,
      to: null,
      person_id: null,
      currency: null,
      kinds: null,
      scope: 'all',
      include_void: false,
    },
    workspace: {
      owner_id: 'o1',
      name: 'Ved',
      business_name: 'Chauhan Trading',
      email: null,
      phone: null,
      base_currency: 'INR',
      member_since: null,
    },
    summary: null,
    totals_by_currency: [],
    currencies: [],
    people: [],
    counts: {
      people: 2,
      entries: 0,
      transactions: 0,
      settlements: 0,
      transfers: 0,
      opening: 0,
      voided: 0,
    },
  };
}

function entry(index: number, date: string): ExportEntry {
  return {
    id: `e${index}`,
    kind: index % 4 === 0 ? 'settlement' : 'transaction',
    type: index % 4 === 0 ? 'in' : index % 2 === 0 ? 'credit' : 'debit',
    direction: null,
    date,
    person_id: 'p1',
    person_name: index % 3 === 0 ? 'Nirali Bhatt' : 'sayan',
    note: `consignment ${index}`,
    is_void: false,
    scope: 'regular',
    opening_role: null,
    transfer_id: null,
    transfer_role: null,
    transfer_counterparty_id: null,
    related_transaction_id: null,
    entry_amount_minor: 50000 + index,
    entry_currency: index % 5 === 0 ? 'AED' : 'INR',
    amount_minor: 50000 + index,
    ledger_currency: 'INR',
    amount_base_minor: index % 5 === 0 ? 1_296_250 : 50000 + index,
    base_currency: 'INR',
    exchange_rate_e9: index % 5 === 0 ? 25_925_000_000 : null,
    exchange_rate_source: index % 5 === 0 ? 'manual-rate' : null,
    exchange_rate_at: null,
    conversion_mode: null,
    settled_minor: 0,
    remaining_minor: 50000,
    settlement_status: 'open',
    created_at: `${date}T0${index % 9}:00:00Z`,
  };
}

function bundle(entries: ExportEntry[], truncated = false): ExportBundle {
  return { header: header(), entries, truncated };
}

describe('rendering the Activity report', () => {
  it('is a PDF', async () => {
    const bytes = await renderActivityPdf(
      bundle([entry(1, '2026-09-04'), entry(2, '2026-09-02')]),
      { view: 'all', range: ALL_ACTIVITY },
    );

    expect(bytes.length).toBeGreaterThan(1000);
    expect(Buffer.from(bytes.slice(0, 4)).toString()).toBe('%PDF');
  });

  it('titles itself the activity report, not the accounting export', async () => {
    const bytes = await renderActivityPdf(bundle([entry(1, '2026-09-04')]), {
      view: 'transaction',
      range: dayRange('2026-09-04'),
    });

    const doc = await PDFDocument.load(bytes);
    expect(doc.getTitle()).toBe('Chauhan Trading — activity report');
  });

  it('paginates a long feed instead of drawing off the page', async () => {
    // Sixty days of three entries each: far more than one A4 page holds.
    const entries: ExportEntry[] = [];
    for (let day = 1; day <= 60; day += 1) {
      const date = `2026-07-${String((day % 28) + 1).padStart(2, '0')}`;
      for (let n = 0; n < 3; n += 1) entries.push(entry(day * 3 + n, date));
    }

    const bytes = await renderActivityPdf(bundle(entries), {
      view: 'all',
      range: ALL_ACTIVITY,
    });
    const doc = await PDFDocument.load(bytes);
    expect(doc.getPageCount()).toBeGreaterThan(1);
  });

  it('still renders when there is nothing in the view', async () => {
    const bytes = await renderActivityPdf(bundle([]), {
      view: 'settlement',
      range: ALL_ACTIVITY,
    });

    expect(Buffer.from(bytes.slice(0, 4)).toString()).toBe('%PDF');
    expect((await PDFDocument.load(bytes)).getPageCount()).toBe(1);
  });

  it('a truncated export is still a valid file', async () => {
    const bytes = await renderActivityPdf(bundle([entry(1, '2026-09-04')], true), {
      view: 'all',
      range: ALL_ACTIVITY,
    });

    expect(Buffer.from(bytes.slice(0, 4)).toString()).toBe('%PDF');
  });
});
