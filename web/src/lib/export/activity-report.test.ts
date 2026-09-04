import { describe, expect, it } from 'vitest';

import {
  activityExportFilename,
  activityExportRequest,
  activityScopeLabel,
  ALL_ACTIVITY,
  dayRange,
  parseDay,
  parseRange,
  parseView,
  rangeIsBackwards,
} from '@/lib/export/activity';
import { buildActivityReport } from '@/lib/export/activity-report';
import { activityEntriesToCsv, ACTIVITY_CSV_COLUMNS } from '@/lib/export/activity-csv';
import type { ExportBundle, ExportEntry, ExportHeader } from '@/lib/export/types';

/**
 * The Activity export.
 *
 * What these pin is the one thing that makes it this feature rather than the
 * workspace report with a new title: **it is grouped by day, newest first, and
 * never by account.** Around that, the promises the dialog makes — the category
 * is the tab it came from, a day is a day, and the currency an entry was
 * written in survives into the file.
 */

/**
 * A stand-in for the real presenter that keeps the one rule under test: the
 * base currency is written without its code, anything else keeps it.
 */
const format = {
  money: (minor: number, currency: string | null | undefined, base: string) =>
    currency === base
      ? `#${(minor / 100).toFixed(2)}`
      : `${(minor / 100).toFixed(2)} ${currency}`,
  approx: (minor: number, _currency: string | null | undefined) =>
    `≈ #${(minor / 100).toFixed(2)}`,
};

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
      name: 'Tester',
      business_name: null,
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
      entries: 4,
      transactions: 3,
      settlements: 1,
      transfers: 0,
      opening: 0,
      voided: 0,
    },
  };
}

function entry(overrides: Partial<ExportEntry>): ExportEntry {
  return {
    id: 'e',
    kind: 'transaction',
    type: 'debit',
    direction: 'out',
    date: '2026-09-04',
    person_id: 'p1',
    person_name: 'sayan',
    note: null,
    is_void: false,
    scope: 'regular',
    opening_role: null,
    transfer_id: null,
    transfer_role: null,
    transfer_counterparty_id: null,
    related_transaction_id: null,
    entry_amount_minor: 50000,
    entry_currency: 'INR',
    amount_minor: 50000,
    ledger_currency: 'INR',
    amount_base_minor: 50000,
    base_currency: 'INR',
    exchange_rate_e9: null,
    exchange_rate_source: null,
    exchange_rate_at: null,
    conversion_mode: null,
    settled_minor: 0,
    remaining_minor: 50000,
    settlement_status: 'open',
    created_at: '2026-09-04T09:00:00Z',
    ...overrides,
  };
}

/**
 * The shape the brief describes: three days, a settlement pair on the newest, a
 * converted AED entry at a custom rate on the middle one, a plain entry on the
 * oldest. Oldest-first, as `export_entries()` returns them.
 */
function bundle(): ExportBundle {
  return {
    header: header(),
    entries: [
      entry({
        id: 'old',
        date: '2026-08-30',
        person_name: 'sayan',
        entry_amount_minor: 50000,
        entry_currency: 'AED',
        amount_base_minor: 1210000,
        exchange_rate_e9: 24_200_000_000,
        exchange_rate_source: 'ecb',
        created_at: '2026-08-30T11:00:00Z',
      }),
      entry({
        id: 'mid',
        date: '2026-09-02',
        person_name: 'ved',
        entry_amount_minor: 50000,
        entry_currency: 'AED',
        amount_base_minor: 1400000,
        exchange_rate_e9: 28_000_000_000,
        exchange_rate_source: 'manual-rate',
        conversion_mode: 'manual',
        created_at: '2026-09-02T08:00:00Z',
      }),
      entry({
        id: 'today-txn',
        date: '2026-09-04',
        person_name: 'sayan',
        created_at: '2026-09-04T08:00:00Z',
      }),
      entry({
        id: 'today-settle',
        kind: 'settlement',
        type: 'in',
        direction: 'in',
        date: '2026-09-04',
        person_name: 'ved',
        entry_amount_minor: 703750,
        amount_minor: 703750,
        amount_base_minor: 703750,
        settled_minor: null,
        remaining_minor: null,
        settlement_status: null,
        created_at: '2026-09-04T09:30:00Z',
      }),
    ],
    truncated: false,
  };
}

describe('the Activity filter contract', () => {
  it('maps each tab onto the kinds the database already understands', () => {
    expect(activityExportRequest('all', ALL_ACTIVITY).kinds).toBeNull();
    expect(activityExportRequest('transaction', ALL_ACTIVITY).kinds).toEqual([
      'credit',
      'debit',
    ]);
    expect(activityExportRequest('settlement', ALL_ACTIVITY).kinds).toEqual(['settlement']);
  });

  it('keeps the feed whole: the opening book is in, voided history is out', () => {
    const request = activityExportRequest('all', ALL_ACTIVITY);
    expect(request.scope).toBe('all');
    expect(request.includeVoid).toBe(false);
  });

  it('treats a day as a one-day range, not a new kind of filter', () => {
    const request = activityExportRequest('all', dayRange('2026-09-04'));
    expect(request.from).toBe('2026-09-04');
    expect(request.to).toBe('2026-09-04');
  });

  it('carries an arbitrary range through untouched', () => {
    const request = activityExportRequest('settlement', {
      from: '2026-08-28',
      to: '2026-09-04',
    });
    expect(request.from).toBe('2026-08-28');
    expect(request.to).toBe('2026-09-04');
    expect(request.kinds).toEqual(['settlement']);
  });

  it('refuses a range whose ends are the wrong way round', () => {
    expect(rangeIsBackwards({ from: '2026-09-04', to: '2026-08-28' })).toBe(true);
    expect(rangeIsBackwards({ from: '2026-08-28', to: '2026-09-04' })).toBe(false);
    expect(rangeIsBackwards(dayRange('2026-09-04'))).toBe(false);
    expect(rangeIsBackwards(ALL_ACTIVITY)).toBe(false);
  });

  it('says what it is showing, without saying "everything to date"', () => {
    expect(activityScopeLabel(ALL_ACTIVITY)).toBe('All activity');
    expect(activityScopeLabel(dayRange('2026-09-04'))).toBe('04 Sep 2026');
    expect(activityScopeLabel({ from: '2026-08-28', to: '2026-09-04' })).toBe(
      '28 Aug 2026 → 04 Sep 2026',
    );
  });

  it('reads a range out of a query string, and ignores nonsense', () => {
    expect(parseRange('2026-08-28', '2026-09-04')).toEqual({
      from: '2026-08-28',
      to: '2026-09-04',
    });
    expect(parseRange('last week', null)).toEqual({ from: null, to: null });
  });

  it('reads the tab and the day the way the page writes them', () => {
    expect(parseView('transaction')).toBe('transaction');
    expect(parseView('settlement')).toBe('settlement');
    expect(parseView(undefined)).toBe('all');
    expect(parseView('nonsense')).toBe('all');

    expect(parseDay('2026-09-04')).toBe('2026-09-04');
    expect(parseDay('yesterday')).toBeNull();
    expect(parseDay(null)).toBeNull();
  });

  it('names the file after what is in it', () => {
    const today = new Date('2026-09-04T00:00:00Z');
    expect(activityExportFilename('pdf', 'all', ALL_ACTIVITY, today)).toBe(
      'accounic-activity-2026-09-04.pdf',
    );
    expect(activityExportFilename('csv', 'settlement', ALL_ACTIVITY, today)).toBe(
      'accounic-activity-settlements-2026-09-04.csv',
    );
    expect(activityExportFilename('csv', 'all', dayRange('2026-08-30'), today)).toBe(
      'accounic-activity-2026-08-30.csv',
    );
    expect(
      activityExportFilename(
        'pdf',
        'transaction',
        { from: '2026-08-28', to: '2026-09-04' },
        today,
      ),
    ).toBe('accounic-activity-transactions-2026-08-28-to-2026-09-04.pdf');
  });
});

describe('the Activity report', () => {
  const report = buildActivityReport(bundle(), format, {
    view: 'all',
    range: ALL_ACTIVITY,
  });

  it('groups by day, newest first — never by account', () => {
    expect(report.days.map((day) => day.date)).toEqual([
      '2026-09-04',
      '2026-09-02',
      '2026-08-30',
    ]);
  });

  it('puts a day’s own entries under it, most recent first', () => {
    const today = report.days[0]!;
    expect(today.count).toBe(2);
    // Written at 09:30 and 08:00 — the later one leads, as on screen.
    expect(today.rows.map((row) => row.person)).toEqual(['ved', 'sayan']);
    expect(today.rows[0]!.isSettlement).toBe(true);
    expect(today.rows[0]!.type).toBe('Settlement received');
  });

  it('counts the entries and the days it actually holds', () => {
    expect(report.counts).toEqual({ entries: 4, days: 3 });
  });

  it('names every day once, in the vocabulary the screen uses', () => {
    // "28 AUGUST" beside "28 August 2026" said the same thing twice.
    for (const day of report.days) {
      expect(day).not.toHaveProperty('fullLabel');
      expect(day.label).toBeTruthy();
    }
  });

  it('writes the base currency without its code, and a foreign one with it', () => {
    // The base-currency row: the symbol has already said which currency it is.
    expect(report.days[0]!.rows[1]!.amount).toBe('#500.00');
    // The foreign row: there the code is the whole point.
    expect(report.days[1]!.rows[0]!.amount).toBe('500.00 AED');
    // A conversion is always into the base, so it needs no code either.
    expect(report.days[1]!.rows[0]!.equivalent).toBe('≈ #14000.00');
  });

  it('keeps the currency an entry was written in, and what it converts to', () => {
    const row = report.days[1]!.rows[0]!;
    expect(row.amount).toBe('500.00 AED');
    expect(row.equivalent).toBe('≈ #14000.00');
    expect(row.rate).toContain('1 AED');
    expect(row.rateNote).toBe('Custom rate · Amount entered by hand');
  });

  it('marks a fetched rate as a fetched rate', () => {
    expect(report.days[2]!.rows[0]!.rateNote).toBeNull();
    expect(report.days[2]!.rows[0]!.rate).toContain('1 AED');
  });

  it('says which view it was taken from, and over what', () => {
    expect(report.title).toBe('Activity report');
    expect(report.category).toBe('Everything');
    expect(report.scope).toBe('All activity');

    const oneDay = buildActivityReport(bundle(), format, {
      view: 'settlement',
      range: dayRange('2026-09-04'),
    });
    expect(oneDay.category).toBe('Settlements');
    expect(oneDay.scope).toBe('04 Sep 2026');

    const window = buildActivityReport(bundle(), format, {
      view: 'transaction',
      range: { from: '2026-08-28', to: '2026-09-04' },
    });
    expect(window.category).toBe('Transactions');
    expect(window.scope).toBe('28 Aug 2026 → 04 Sep 2026');
  });
});

describe('the Activity CSV', () => {
  const csv = activityEntriesToCsv(bundle().entries, format, 'INR');
  const lines = csv.trimEnd().split('\r\n');

  it('is chronological like the screen, not grouped by person', () => {
    expect(lines[0]).toBe(ACTIVITY_CSV_COLUMNS.join(','));
    const dates = lines.slice(1).map((line) => line.split(',')[0]);
    expect(dates).toEqual(['2026-09-04', '2026-09-04', '2026-09-02', '2026-08-30']);
  });

  it('carries the day beside the date, so a reader keeps the feed’s shape', () => {
    expect(lines[1]!.split(',')[1]).toBeTruthy();
  });

  it('writes the entered amount and its currency side by side', () => {
    const row = lines[3]!.split(',');
    // amount, currency, base_amount, base_currency
    expect(row[6]).toBe('500');
    expect(row[7]).toBe('AED');
    expect(row[8]).toBe('14000');
    expect(row[9]).toBe('INR');
    expect(row[10]).toBe('28');
    expect(row[11]).toBe('manual-rate');
  });
});
