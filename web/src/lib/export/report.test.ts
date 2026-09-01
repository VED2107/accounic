import { describe, expect, it } from 'vitest';

import { buildWorkspaceReport, reportRowType, reportSettlement } from './report';
import type { ExportBundle, ExportEntry, ExportHeader } from './types';

/**
 * What the workspace report says (Phase 4).
 *
 * The report is where the PDF's words are decided, so these are assertions
 * about the product rather than about a page: the books stay apart, the
 * currencies are not collapsed, a person with no entries in the period still
 * appears, and a truncated export says so.
 */

const format = {
  money: (minor: number, currency: string | null | undefined) =>
    `${currency ?? 'INR'} ${(minor / 100).toFixed(2)}`,
  approx: (minor: number, currency: string | null | undefined) =>
    `~ ${currency ?? 'INR'} ${(minor / 100).toFixed(2)}`,
};

function entry(overrides: Partial<ExportEntry> = {}): ExportEntry {
  return {
    id: 'e1',
    kind: 'transaction',
    type: 'credit',
    direction: 'in',
    date: '2026-08-30',
    person_id: 'p1',
    person_name: 'VED',
    note: 'rent',
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
    exchange_rate_source: 'test',
    exchange_rate_at: null,
    conversion_mode: 'automatic',
    settled_minor: 20000,
    remaining_minor: 28000,
    settlement_status: 'partial',
    created_at: '2026-08-30T09:00:00Z',
    ...overrides,
  };
}

function header(overrides: Partial<ExportHeader> = {}): ExportHeader {
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
      name: 'Export Tester',
      business_name: 'Tester Trading',
      email: null,
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
    people: [
      {
        id: 'p1',
        name: 'VED',
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
      },
      {
        id: 'p2',
        name: 'QUIET ACCOUNT',
        type: 'person',
        phone: null,
        email: null,
        address: null,
        notes: null,
        is_archived: true,
        currency: 'INR',
        ledger_currency: 'INR',
        created_at: '2026-01-01T00:00:00Z',
        balance: {
          currency: 'INR',
          net_balance: -5000,
          outstanding_receivable: 0,
          outstanding_payable: 5000,
          opening_net_minor: 0,
        },
        opening: null,
      },
    ],
    counts: {
      people: 2,
      entries: 3,
      transactions: 2,
      settlements: 1,
      transfers: 0,
      opening: 1,
      voided: 0,
    },
    ...overrides,
  };
}

const bundle: ExportBundle = {
  header: header(),
  entries: [
    entry({ id: 'a', scope: 'opening', note: 'opening ved' }),
    entry({ id: 'b' }),
    entry({ id: 'c', kind: 'settlement', type: 'in', settlement_status: null }),
  ],
  truncated: false,
};

describe('the workspace report', () => {
  it('leads with the business name when there is one', () => {
    const report = buildWorkspaceReport(bundle, format);
    expect(report.workspaceName).toBe('Tester Trading');
    expect(report.ownerName).toBe('Export Tester');
  });

  it('lists the position per currency and never sums across them', () => {
    const report = buildWorkspaceReport(bundle, format);
    expect(report.positions.map((p) => p.currency)).toEqual(['INR', 'AED']);
    expect(report.positions[0]!.net).toBe('INR 1000.00');
    expect(report.positions[0]!.cash).toBe('INR 600.00');
    expect(report.positions[0]!.opening).toBe('INR 400.00');
    // A currency with no cash/opening breakdown says so rather than printing 0.
    expect(report.positions[1]!.cash).toBeNull();
  });

  it('keeps the opening book out of the transactions block', () => {
    const report = buildWorkspaceReport(bundle, format);
    const section = report.sections.find((s) => s.personId === 'p1')!;

    expect(section.openingRows).toHaveLength(1);
    expect(section.rows).toHaveLength(2);
    expect(section.openingRows[0]!.type).toBe('Opening balance');
  });

  it('keeps an account with no entries in the period, with its balance', () => {
    const report = buildWorkspaceReport(bundle, format);
    const quiet = report.people.find((p) => p.name === 'QUIET ACCOUNT')!;

    expect(quiet.netReceivable).toBe(false);
    expect(quiet.payable).toBe('INR 50.00');
    expect(report.sections.some((s) => s.personId === 'p2')).toBe(true);
  });

  it('prints the entered amount, with the base equivalent beside it', () => {
    const report = buildWorkspaceReport(bundle, format);
    const row = report.sections[0]!.rows[0]!;

    expect(row.amount).toBe('AED 20.00');
    expect(row.equivalent).toBe('~ INR 480.00');
  });

  it('says how much of a transaction is settled, and nothing for a settlement', () => {
    expect(reportSettlement(entry(), format)).toBe('INR 200.00 of INR 480.00');
    expect(reportSettlement(entry({ settlement_status: 'settled' }), format)).toBe('Settled');
    expect(reportSettlement(entry({ settlement_status: 'open' }), format)).toBe('Open');
    expect(reportSettlement(entry({ kind: 'settlement' }), format)).toBeNull();
  });

  it('names each row the way the screen names it', () => {
    // The stored enum labels run the OPPOSITE way to the spoken words —
    // docs/accounting-direction.md — so a stored 'credit' is a Debit on screen,
    // and the report has to agree with the screen, not with the column.
    expect(reportRowType(entry())).toBe('Debit');
    expect(reportRowType(entry({ type: 'debit' }))).toBe('Credit');
    expect(reportRowType(entry({ kind: 'settlement', type: 'in' }))).toBe(
      'Settlement received',
    );
    expect(reportRowType(entry({ scope: 'opening' }))).toBe('Opening balance');
    expect(
      reportRowType(entry({ scope: 'opening', opening_role: 'adjustment' })),
    ).toBe('Opening debit');
    expect(reportRowType(entry({ transfer_id: 't1', transfer_role: 'source' }))).toBe(
      'Transfer out',
    );
  });

  it('states the period and the filters in words', () => {
    expect(buildWorkspaceReport(bundle, format).period).toBe('Everything to date');
    expect(buildWorkspaceReport(bundle, format).filters).toBe('Every account, every entry');

    const filtered = buildWorkspaceReport(
      {
        ...bundle,
        header: header({
          filters: {
            from: '2026-01-01',
            to: '2026-06-30',
            person_id: null,
            currency: 'AED',
            kinds: ['credit'],
            scope: 'regular',
            include_void: true,
          },
        }),
      },
      format,
    );

    expect(filtered.period).toContain('2026');
    expect(filtered.filters).toContain('entered in AED');
    expect(filtered.filters).toContain('excluding opening balances');
    expect(filtered.filters).toContain('including voided history');
  });

  it('carries the truncation flag through to the page that prints it', () => {
    expect(buildWorkspaceReport({ ...bundle, truncated: true }, format).truncated).toBe(true);
  });
});
