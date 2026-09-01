import { minorToInput } from '@/lib/money';

import type { ExportEntry } from '@/lib/export/types';

/**
 * The workspace export as CSV (milestone 1.9.0, Phase 5).
 *
 * A spreadsheet, not a printout: one row per ledger entry, one column per
 * fact, nothing merged, nothing styled, no totals row. Anything that wants to
 * look like a document is the PDF's job.
 *
 * Two decisions worth stating, because both are easy to get wrong:
 *
 *   * MONEY IS WRITTEN TWICE. `amount_minor` is the integer the database
 *     stores — the only figure that survives a round trip without a rounding
 *     argument — and `amount` is that integer rendered with the currency's own
 *     minor-unit exponent (JPY has none, Gulf dinars have three). A reader can
 *     use whichever it trusts, and they cannot disagree.
 *   * CURRENCY IS NEVER COLLAPSED. Every row states the currency the entry was
 *     MADE in beside its amount, and the base equivalent in its own pair of
 *     columns. Summing the `amount` column across currencies is meaningless and
 *     the header says so by naming the currency column next to it.
 *
 * Mirrored by `app/lib/core/export_csv.dart`.
 */

/** RFC 4180 columns, in the order they are written. */
export const CSV_COLUMNS = [
  'entry_id',
  'date',
  'kind',
  'type',
  'direction',
  'scope',
  'person_id',
  'person_name',
  'currency',
  'amount',
  'amount_minor',
  'ledger_currency',
  'ledger_amount',
  'ledger_amount_minor',
  'base_currency',
  'base_amount',
  'base_amount_minor',
  'exchange_rate',
  'exchange_rate_source',
  'conversion_mode',
  'settled_minor',
  'remaining_minor',
  'settlement_status',
  'is_void',
  'transfer_id',
  'transfer_role',
  'note',
  'created_at',
] as const;

/**
 * One CSV field.
 *
 * Quoted whenever it contains a delimiter, a quote, a newline, or leading or
 * trailing space — and a quote inside is doubled, which is the whole of RFC
 * 4180's escaping. A name written in Devanagari or Arabic needs no escaping at
 * all; it needs the file to be UTF-8, which `csvBlob()` handles.
 */
export function csvField(value: unknown): string {
  if (value === null || value === undefined) return '';
  const text = typeof value === 'boolean' ? (value ? 'true' : 'false') : String(value);
  if (text === '') return '';
  const needsQuotes = /[",\r\n]/.test(text) || text !== text.trim();
  return needsQuotes ? `"${text.replaceAll('"', '""')}"` : text;
}

/** One row from already-stringified fields. */
export function csvRow(fields: readonly unknown[]): string {
  return fields.map(csvField).join(',');
}

function rateText(rateE9: number | null | undefined): string {
  if (rateE9 === null || rateE9 === undefined) return '';
  // Nine decimals, trailing zeros trimmed: the same figure the ledger stores,
  // not a rounded display version of it.
  const whole = Math.trunc(rateE9 / 1_000_000_000);
  const fraction = String(Math.abs(rateE9) % 1_000_000_000)
    .padStart(9, '0')
    .replace(/0+$/, '');
  return fraction === '' ? String(whole) : `${whole}.${fraction}`;
}

function amount(minor: number | null | undefined, currency: string | null | undefined): string {
  if (minor === null || minor === undefined) return '';
  return minorToInput(minor, currency ?? 'INR');
}

/** One entry as a row of fields, in `CSV_COLUMNS` order. */
export function entryToFields(entry: ExportEntry): unknown[] {
  return [
    entry.id,
    entry.date,
    entry.kind,
    entry.type,
    entry.direction,
    entry.scope,
    entry.person_id,
    entry.person_name,
    entry.entry_currency,
    amount(entry.entry_amount_minor, entry.entry_currency),
    entry.entry_amount_minor,
    entry.ledger_currency,
    amount(entry.amount_minor, entry.ledger_currency),
    entry.amount_minor,
    entry.base_currency,
    amount(entry.amount_base_minor, entry.base_currency),
    entry.amount_base_minor,
    rateText(entry.exchange_rate_e9),
    entry.exchange_rate_source,
    entry.conversion_mode,
    entry.settled_minor,
    entry.remaining_minor,
    entry.settlement_status,
    entry.is_void,
    entry.transfer_id,
    entry.transfer_role,
    entry.note,
    entry.created_at,
  ];
}

/**
 * Every entry as a CSV document.
 *
 * CRLF line endings, because that is what RFC 4180 says and what Excel expects
 * from a file it did not write itself.
 */
export function entriesToCsv(entries: readonly ExportEntry[]): string {
  const lines = [csvRow(CSV_COLUMNS), ...entries.map((entry) => csvRow(entryToFields(entry)))];
  return `${lines.join('\r\n')}\r\n`;
}

/**
 * The same document with a UTF-8 byte-order mark.
 *
 * Excel on Windows reads a BOM-less UTF-8 CSV in the system codepage, which
 * turns every non-Latin name in the file into mojibake. The BOM costs three
 * bytes and every other reader ignores it.
 */
export function csvWithBom(csv: string): string {
  return `﻿${csv}`;
}
