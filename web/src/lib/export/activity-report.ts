import { entryIsReceivable, entryLabel } from '@/lib/direction';
import { transferLabel } from '@/lib/transfers';
import { rateIsManual } from '@/lib/conversion';
import { dayGroupLabel, timeOfDay } from '@/lib/dates';
import { rateSentence } from '@/lib/currencies';
import {
  activityScopeLabel,
  VIEW_LABEL,
  type ActivityRange,
  type ActivityView,
} from '@/lib/export/activity';

import type { ExportBundle, ExportEntry } from '@/lib/export/types';

/**
 * What the Activity report says, before anything is drawn.
 *
 * The Activity screen's own shape, in words: day, then the entries of that day,
 * newest first. It is deliberately NOT `lib/export/report.ts`, which groups the
 * same rows by account for the workspace report on Profile. Both are true; they
 * answer different questions, and this one answers "what happened, and when?"
 *
 * The rules are the same three that govern every other writer here:
 *
 *   * NOTHING IS COMPUTED. Every figure is a field the database returned. There
 *     is no arithmetic in this file — not a sum, not a conversion, not a rate.
 *   * CURRENCY IS NEVER COLLAPSED. A row leads with the amount as ENTERED, in
 *     the currency it was entered in, exactly as the screen does; the base
 *     equivalent and the rate that links them sit underneath as what they are.
 *   * THE ROWS SAY WHAT THE SCREEN SAYS. The labels come from the same
 *     `entryLabel`, `transferLabel` and `rateSentence` the timeline renders
 *     with, so the document and the screen cannot drift into two vocabularies.
 *     That includes the currency rule: the workspace's own currency is written
 *     as `₹500`, because the symbol has already said which currency it is, and
 *     only a foreign one carries its ISO code — `500 AED`.
 *
 * Mirrored by `app/lib/core/activity_report.dart`.
 */

export interface ActivityReportRow {
  /** The account the entry belongs to — the row's heading, as on screen. */
  person: string;
  /** `Credit`, `Debit`, `Settlement received`, `Transfer to …`, `Opening balance`. */
  type: string;
  /** The note, when it says something the label does not. Empty otherwise. */
  description: string;
  /** The figure as entered, in the currency it was entered in. */
  amount: string;
  /** `≈ ₹12,962.50` — the base equivalent, when there is one worth printing. */
  equivalent: string | null;
  /** `1 AED = ₹25.925 INR`, or null when nothing was converted. */
  rate: string | null;
  /** `Custom rate`, `Amount entered by hand`, both, or null. */
  rateNote: string | null;
  /** `Settled`, `Open`, `₹400 of ₹1,000` — for a transaction that can settle. */
  settlement: string | null;
  /** Which way the debt runs. Drives the glyph and the amount's colour. */
  receivable: boolean;
  isSettlement: boolean;
  isOpening: boolean;
  /** `08:42 PM`, from `created_at`: when the row was actually written. */
  time: string;
}

export interface ActivityReportDay {
  /** `2026-09-04` — the day itself, for anything that needs to sort. */
  date: string;
  /** `Today`, `Tuesday`, `28 August` — the screen's own words, and the only
      words: a heading that printed the label and the full date said the same
      thing twice. The date the document was generated is on the cover. */
  label: string;
  /** `3 entries`. */
  count: number;
  rows: ActivityReportRow[];
}

export interface ActivityReport {
  title: string;
  workspaceName: string;
  ownerName: string | null;
  exportedAt: string;
  /** `Everything`, `Transactions`, `Settlements` — the tab this was taken from. */
  category: string;
  /** `All activity`, `04 Sep 2026`, or `28 Aug 2026 → 04 Sep 2026`. */
  scope: string;
  baseCurrency: string;
  days: ActivityReportDay[];
  /** The entries in the document, and the days they fall on. */
  counts: { entries: number; days: number };
  /** Set when the export hit its size cap: printed, never hidden. */
  truncated: boolean;
}

/**
 * How this report writes money.
 *
 * Not `ReportFormatter`: that one names every figure with its ISO code, which
 * is right for the workspace report and wrong here. An Activity row states the
 * base currency constantly, so repeating `INR` after every `₹` is noise — the
 * base is passed in and the presenter drops the code for it, exactly as the
 * screen does.
 */
export interface ActivityFormatter {
  /** `₹500` for the base currency, `500 AED` for anything else. */
  money(minor: number, currency: string | null | undefined, base: string): string;
  /** `≈ ₹12,962.50` — a conversion is always into the base, so no code. */
  approx(minor: number, currency: string | null | undefined): string;
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : null;
}

/** What a row is called — the same words the timeline uses. */
export function activityRowType(entry: ExportEntry): string {
  if (entry.transfer_id && entry.kind !== 'settlement') {
    return transferLabel(entry.transfer_role as 'source' | 'destination' | null, null);
  }
  if (entry.scope === 'opening') {
    return entry.opening_role === 'adjustment'
      ? `Opening ${entryLabel('transaction', entry.type ?? 'credit').toLowerCase()}`
      : 'Opening balance';
  }
  return entryLabel(entry.kind, entry.type ?? '');
}

/** How much of a transaction is settled, in one phrase, or null. */
export function activitySettlement(
  entry: ExportEntry,
  format: ActivityFormatter,
  base: string,
): string | null {
  if (entry.kind !== 'transaction') return null;
  if (entry.settlement_status === null || entry.settlement_status === undefined) return null;
  if (entry.settlement_status === 'settled') return 'Settled';
  if (entry.settlement_status === 'open') return 'Open';
  return `${format.money(entry.settled_minor ?? 0, entry.ledger_currency, base)} of ${format.money(
    entry.amount_minor,
    entry.ledger_currency,
    base,
  )}`;
}

function toRow(
  entry: ExportEntry,
  format: ActivityFormatter,
  base: string,
): ActivityReportRow {
  const type = activityRowType(entry);
  const note = (entry.note ?? '').trim();

  // The equivalent earns its line only when it says something the primary
  // figure does not — the same test the screen applies.
  const converted =
    entry.amount_base_minor !== null &&
    Boolean(entry.base_currency) &&
    entry.base_currency !== entry.entry_currency;

  const rate = entry.exchange_rate_e9
    ? rateSentence(
        entry.entry_currency,
        entry.ledger_currency,
        entry.exchange_rate_e9,
        entry.entry_amount_minor,
      )
    : null;

  // Both can be true at once and the screen says both: a rate typed by hand,
  // and an amount typed over the one that rate produced. Printing only the
  // first would hide the second on exactly the rows where it matters most.
  const notes: string[] = [];
  if (rateIsManual(entry.exchange_rate_source)) notes.push('Custom rate');
  if (entry.conversion_mode === 'manual') notes.push('Amount entered by hand');
  const rateNote = notes.length > 0 ? notes.join(' · ') : null;

  return {
    person: entry.person_name ?? '—',
    type,
    // An opening balance is stored with "Opening balance" as its note, so a
    // row would otherwise print the phrase twice.
    description: note && note !== type ? note : '',
    amount: format.money(entry.entry_amount_minor, entry.entry_currency, base),
    equivalent: converted
      ? format.approx(entry.amount_base_minor ?? 0, entry.base_currency)
      : null,
    rate,
    rateNote,
    settlement: activitySettlement(entry, format, base),
    receivable: entryIsReceivable(entry.type ?? ''),
    isSettlement: entry.kind === 'settlement',
    isOpening: entry.scope === 'opening',
    time: timeOfDay(entry.created_at),
  };
}

/**
 * The entries, grouped into days, newest first.
 *
 * `export_entries()` returns them oldest-first and deterministically tie-broken;
 * the Activity screen reads newest-first. This reverses that one ordering and
 * changes nothing else — the rows themselves are the database's, untouched.
 */
export function groupEntriesByDay(
  entries: readonly ExportEntry[],
  format: ActivityFormatter,
  base: string,
): ActivityReportDay[] {
  const buckets = new Map<string, ExportEntry[]>();
  for (const entry of entries) {
    const list = buckets.get(entry.date);
    if (list) list.push(entry);
    else buckets.set(entry.date, [entry]);
  }

  return [...buckets.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : a[0] > b[0] ? -1 : 0))
    .map(([date, rows]) => ({
      date,
      label: dayGroupLabel(date),
      count: rows.length,
      rows: rows
        // Within a day the screen shows the most recently written first.
        .slice()
        .reverse()
        .map((entry) => toRow(entry, format, base)),
    }));
}

/** The whole report, ready to draw. */
export function buildActivityReport(
  bundle: ExportBundle,
  format: ActivityFormatter,
  options: { view: ActivityView; range: ActivityRange },
): ActivityReport {
  const { header, entries, truncated } = bundle;
  const base = header.workspace?.base_currency ?? 'INR';
  const days = groupEntriesByDay(entries, format, base);

  return {
    title: 'Activity report',
    workspaceName:
      text(header.workspace?.business_name) ?? text(header.workspace?.name) ?? 'Accounic',
    ownerName: text(header.workspace?.name),
    exportedAt: header.exported_at,
    category: VIEW_LABEL[options.view],
    scope: activityScopeLabel(options.range),
    baseCurrency: base,
    days,
    counts: { entries: entries.length, days: days.length },
    truncated,
  };
}
