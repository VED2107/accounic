import { describe, expect, it } from 'vitest';
import { PDFDocument } from 'pdf-lib';

import { renderWorkspacePdf } from '@/lib/pdf/workspace';
import type { ExportEntry, ExportHeader } from '@/lib/export/types';

/**
 * The workspace export, actually rendered (Phase 4).
 *
 * `export/report.test.ts` checks what the document says. This checks that it
 * can be produced at all — fonts embedded, glyphs present, pages laid out,
 * bytes written — because every one of those failures is a runtime one that no
 * typecheck catches: a missing glyph makes pdf-lib throw mid-draw, and a
 * pagination bug loops rather than failing to compile.
 */

function entry(overrides: Partial<ExportEntry> = {}): ExportEntry {
  return {
    id: 'e1',
    kind: 'transaction',
    type: 'credit',
    direction: 'in',
    date: '2026-08-30',
    person_id: 'p1',
    person_name: 'VED',
    note: 'rent for August',
    is_void: false,
    scope: 'regular',
    opening_role: null,
    transfer_id: null,
    transfer_role: null,
    transfer_counterparty_id: null,
    related_transaction_id: null,
    entry_amount_minor: 2000,
    entry_currency: 'AED',
    amount_minor: 48000,
    ledger_currency: 'INR',
    amount_base_minor: 48000,
    base_currency: 'INR',
    exchange_rate_e9: 24_000_000_000,
    exchange_rate_source: 'open.er-api.com',
    exchange_rate_at: null,
    conversion_mode: 'automatic',
    settled_minor: 0,
    remaining_minor: 48000,
    settlement_status: 'open',
    created_at: '2026-08-30T09:00:00Z',
    ...overrides,
  };
}

function person(id: string, name: string) {
  return {
    id,
    name,
    type: 'person',
    phone: null,
    email: null,
    address: null,
    notes: null,
    is_archived: false,
    currency: 'INR',
    ledger_currency: 'INR',
    created_at: '2026-01-01T00:00:00Z',
    balance: {
      currency: 'INR',
      net_balance: 100000,
      outstanding_receivable: 120000,
      outstanding_payable: 20000,
      opening_net_minor: 40000,
    },
    opening: null,
  };
}

function header(people = [person('p1', 'VED')]): ExportHeader {
  return {
    schema_version: 1,
    generator: 'accounic',
    exported_at: '2026-09-01T10:00:00Z',
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
      name: 'Ved Chauhan',
      business_name: 'Accounic Test Workspace',
      email: 'owner@example.com',
      phone: null,
      base_currency: 'INR',
      member_since: null,
    },
    summary: { net_position: 100000 },
    totals_by_currency: [
      {
        currency: 'INR',
        receivable: 120000,
        payable: 20000,
        net: 100000,
        cash: { net: 60000 },
        opening: { net: 40000 },
      },
      { currency: 'AED', receivable: 5000, payable: 0, net: 5000 },
    ],
    currencies: [{ code: 'INR', name: 'Indian Rupee', symbol: '₹', decimals: 2 }],
    people,
    counts: {
      people: people.length,
      entries: 2,
      transactions: 2,
      settlements: 0,
      transfers: 0,
      opening: 1,
      voided: 0,
    },
  };
}

async function pageCount(bytes: Uint8Array): Promise<number> {
  const doc = await PDFDocument.load(bytes);
  return doc.getPageCount();
}

describe('rendering the workspace export', () => {
  it('produces a PDF', async () => {
    const bytes = await renderWorkspacePdf({
      header: header(),
      entries: [entry({ scope: 'opening' }), entry({ id: 'e2' })],
      truncated: false,
    });

    expect(bytes.length).toBeGreaterThan(1000);
    expect(String.fromCharCode(...bytes.slice(0, 4))).toBe('%PDF');
    expect(await pageCount(bytes)).toBeGreaterThanOrEqual(1);
  });

  it('renders an empty workspace without throwing', async () => {
    const bytes = await renderWorkspacePdf({
      header: header([]),
      entries: [],
      truncated: false,
    });

    expect(await pageCount(bytes)).toBe(1);
  });

  it('prints the truncation notice without breaking the cover', async () => {
    const bytes = await renderWorkspacePdf({
      header: header(),
      entries: [entry()],
      truncated: true,
    });

    expect(String.fromCharCode(...bytes.slice(0, 4))).toBe('%PDF');
  });

  it('paginates a long ledger instead of drawing off the page', async () => {
    const many = Array.from({ length: 260 }, (_, index) =>
      entry({ id: `e${index}`, note: `entry number ${index}` }),
    );

    const bytes = await renderWorkspacePdf({
      header: header(),
      entries: many,
      truncated: false,
    });

    expect(await pageCount(bytes)).toBeGreaterThan(4);
  });

  it('draws names and notes in scripts the embedded face covers', async () => {
    const bytes = await renderWorkspacePdf({
      header: header([person('p1', 'वेद चौहान')]),
      entries: [entry({ person_name: 'वेद चौहान', note: 'किराया — अगस्त' })],
      truncated: false,
    });

    expect(String.fromCharCode(...bytes.slice(0, 4))).toBe('%PDF');
  });

  it('survives a currency whose symbol the face cannot draw', async () => {
    const bytes = await renderWorkspacePdf({
      header: header(),
      entries: [entry({ entry_currency: 'VND', entry_amount_minor: 500000 })],
      truncated: false,
    });

    expect(String.fromCharCode(...bytes.slice(0, 4))).toBe('%PDF');
  });
});
