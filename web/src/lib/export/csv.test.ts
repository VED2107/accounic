import { describe, expect, it } from 'vitest';

import { csvField, CSV_COLUMNS, entriesToCsv, csvWithBom } from './csv';
import { buildExportDocument, exportFilename } from './json';
import type { ExportBundle, ExportEntry, ExportHeader } from './types';

/**
 * The two machine-readable exports (milestone 1.9.0, Phase 5).
 *
 * The interesting cases are all about not corrupting somebody's books on the
 * way out: a note with a comma in it, a name in Devanagari, a yen amount that
 * has no minor unit, and a file that must never claim to be complete when it
 * is not.
 */

function entry(overrides: Partial<ExportEntry> = {}): ExportEntry {
  return {
    id: '11111111-1111-1111-1111-111111111111',
    kind: 'transaction',
    type: 'credit',
    direction: 'in',
    date: '2026-08-30',
    person_id: '22222222-2222-2222-2222-222222222222',
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
    exchange_rate_source: 'open.er-api.com',
    exchange_rate_at: '2026-08-30T00:00:00Z',
    conversion_mode: 'automatic',
    settled_minor: 0,
    remaining_minor: 48000,
    settlement_status: 'open',
    created_at: '2026-08-30T09:12:00Z',
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
      owner_id: '33333333-3333-3333-3333-333333333333',
      name: 'Export Tester',
      business_name: null,
      email: 'owner@example.com',
      phone: null,
      base_currency: 'INR',
      member_since: '2026-01-01T00:00:00Z',
    },
    summary: { net_position: 48000 },
    totals_by_currency: [],
    currencies: [{ code: 'INR', name: 'Indian Rupee', symbol: '₹', decimals: 2 }],
    people: [],
    counts: {
      people: 1,
      entries: 1,
      transactions: 1,
      settlements: 0,
      transfers: 0,
      opening: 0,
      voided: 0,
    },
    ...overrides,
  };
}

describe('csvField — RFC 4180 escaping', () => {
  it('leaves an ordinary value alone', () => {
    expect(csvField('rent')).toBe('rent');
    expect(csvField(48000)).toBe('48000');
    expect(csvField(true)).toBe('true');
  });

  it('writes null and undefined as empty, not as the words', () => {
    expect(csvField(null)).toBe('');
    expect(csvField(undefined)).toBe('');
  });

  it('quotes a comma, so one field does not become two', () => {
    expect(csvField('rent, August')).toBe('"rent, August"');
  });

  it('doubles a quote inside a quoted field', () => {
    expect(csvField('the "final" instalment')).toBe('"the ""final"" instalment"');
  });

  it('quotes a newline, so one row does not become two', () => {
    expect(csvField('first line\nsecond line')).toBe('"first line\nsecond line"');
    expect(csvField('with\r\ncrlf')).toBe('"with\r\ncrlf"');
  });

  it('quotes leading and trailing space, which a reader would otherwise trim', () => {
    expect(csvField('  padded  ')).toBe('"  padded  "');
  });

  it('leaves Unicode exactly as it is — the file is UTF-8, not the field', () => {
    expect(csvField('वेद चौहान')).toBe('वेद चौहान');
    expect(csvField('عبد الله')).toBe('عبد الله');
    expect(csvField('日本の取引')).toBe('日本の取引');
  });

  it('quotes a Unicode value that also contains a delimiter', () => {
    expect(csvField('वेद, चौहान')).toBe('"वेद, चौहान"');
  });
});

describe('entriesToCsv', () => {
  it('writes the header row first, in the declared order', () => {
    const csv = entriesToCsv([]);
    expect(csv.split('\r\n')[0]).toBe(CSV_COLUMNS.join(','));
  });

  it('ends every line with CRLF, including the last', () => {
    expect(entriesToCsv([entry()]).endsWith('\r\n')).toBe(true);
  });

  it('states the amount as entered and as an integer, and never collapses currency', () => {
    const [, row] = entriesToCsv([entry()]).split('\r\n');
    const fields = row!.split(',');
    const columns = CSV_COLUMNS as readonly string[];

    expect(fields[columns.indexOf('currency')]).toBe('AED');
    expect(fields[columns.indexOf('amount')]).toBe('20');
    expect(fields[columns.indexOf('amount_minor')]).toBe('2000');
    expect(fields[columns.indexOf('ledger_currency')]).toBe('INR');
    expect(fields[columns.indexOf('ledger_amount')]).toBe('480');
    expect(fields[columns.indexOf('base_amount_minor')]).toBe('48000');
  });

  it('renders a yen amount with no minor unit and a dinar with three', () => {
    const yen = entriesToCsv([
      entry({ entry_currency: 'JPY', entry_amount_minor: 5000 }),
    ]).split('\r\n')[1]!;
    const dinar = entriesToCsv([
      entry({ entry_currency: 'KWD', entry_amount_minor: 5000 }),
    ]).split('\r\n')[1]!;

    const columns = CSV_COLUMNS as readonly string[];
    expect(yen.split(',')[columns.indexOf('amount')]).toBe('5000');
    expect(dinar.split(',')[columns.indexOf('amount')]).toBe('5');
  });

  it('writes the stored rate at full precision, trailing zeros trimmed', () => {
    const columns = CSV_COLUMNS as readonly string[];
    const row = entriesToCsv([entry({ exchange_rate_e9: 23_912_345_678 })]).split('\r\n')[1]!;
    expect(row.split(',')[columns.indexOf('exchange_rate')]).toBe('23.912345678');
  });

  it('keeps a note with a comma, a quote and a newline in one field', () => {
    const csv = entriesToCsv([entry({ note: 'part "final", see\nnote' })]);
    expect(csv).toContain('"part ""final"", see\nnote"');
    // Header, the opening of the row, the continuation, and the trailing empty.
    expect(csv.split('\r\n')).toHaveLength(3);
  });

  it('adds a BOM when asked, and only then', () => {
    const csv = entriesToCsv([]);
    expect(csv.charCodeAt(0)).not.toBe(0xfeff);
    expect(csvWithBom(csv).charCodeAt(0)).toBe(0xfeff);
  });
});

describe('the JSON backup', () => {
  const bundle: ExportBundle = {
    header: header(),
    entries: [
      entry({ id: 'a', scope: 'opening', kind: 'transaction' }),
      entry({ id: 'b', kind: 'transaction' }),
      entry({ id: 'c', kind: 'settlement', type: null }),
    ],
    truncated: false,
  };

  it('leads with its schema version', () => {
    const document = buildExportDocument(bundle);
    expect(Object.keys(document)[0]).toBe('schema_version');
    expect(document.schema_version).toBe(1);
  });

  it('keeps the three books apart rather than shipping one flat feed', () => {
    const document = buildExportDocument(bundle);
    expect(document.opening_balances.map((e) => e.id)).toEqual(['a']);
    expect(document.transactions.map((e) => e.id)).toEqual(['b']);
    expect(document.settlements.map((e) => e.id)).toEqual(['c']);
  });

  it('defines every currency it uses, exponent included', () => {
    const document = buildExportDocument(bundle);
    expect(document.currencies).toEqual([
      { code: 'INR', name: 'Indian Rupee', symbol: '₹', decimals: 2 },
    ]);
  });

  it('says outright when it is not the whole workspace', () => {
    expect(buildExportDocument({ ...bundle, truncated: true }).truncated).toBe(true);
    expect(buildExportDocument(bundle).truncated).toBe(false);
  });

  it('carries no key, token or password anywhere in it', () => {
    const text = JSON.stringify(buildExportDocument(bundle));
    expect(text).not.toMatch(/password|secret|token|service_role|anon_key|jwt/i);
  });

  it('names the file after what is in it, and dates it', () => {
    const date = new Date('2026-09-01T00:00:00Z');
    expect(exportFilename('csv', { date })).toBe('accounic-export-2026-09-01.csv');
    expect(exportFilename('json', { scope: 'VED Kumar', date })).toBe(
      'accounic-ved-kumar-2026-09-01.json',
    );
  });
});
