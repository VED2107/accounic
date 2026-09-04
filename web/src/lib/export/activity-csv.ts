import { minorToInput } from '@/lib/money';
import { dayGroupLabel, timeOfDay } from '@/lib/dates';
import { csvRow } from '@/lib/export/csv';
import {
  activityRowType,
  activitySettlement,
  type ActivityFormatter,
} from '@/lib/export/activity-report';

import type { ExportEntry } from '@/lib/export/types';

/**
 * The Activity feed as CSV.
 *
 * A spreadsheet is a table, so this is a table — but it is the *Activity*
 * table, not the workspace one. Two things make it that rather than a rename of
 * `lib/export/csv.ts`:
 *
 *   * THE ORDER IS THE SCREEN'S. Newest first, the way the feed reads. A CSV
 *     that sorted by person would be the workspace export with different
 *     headings, which is the thing this feature exists not to be.
 *   * THE COLUMNS ARE THE ROW'S. Day and time beside the date, the entry's own
 *     words for its type, and the amount as entered next to its currency —
 *     the facts a person reading the screen can see, in the order they read
 *     them. The workspace CSV's job is different: it is the machine-readable
 *     one, and it keeps every id and every minor-unit integer.
 *
 * What both share is the rule that matters: the amount as ENTERED and the
 * currency it was entered in are written side by side and never collapsed into
 * a converted figure. The base equivalent and the rate get their own columns.
 *
 * Mirrored by `app/lib/core/activity_csv.dart`.
 */

/** RFC 4180 columns, in the order they are written. */
export const ACTIVITY_CSV_COLUMNS = [
  'date',
  'day',
  'time',
  'person',
  'type',
  'description',
  'amount',
  'currency',
  'base_amount',
  'base_currency',
  'exchange_rate',
  'rate_source',
  'status',
] as const;

function rateText(rateE9: number | null | undefined): string {
  if (rateE9 === null || rateE9 === undefined) return '';
  // Nine decimals with trailing zeros trimmed: the figure the ledger stores,
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

/** One entry as a row of fields, in `ACTIVITY_CSV_COLUMNS` order. */
export function activityEntryToFields(
  entry: ExportEntry,
  format: ActivityFormatter,
  base: string,
): unknown[] {
  const type = activityRowType(entry);
  const note = (entry.note ?? '').trim();

  return [
    entry.date,
    dayGroupLabel(entry.date),
    timeOfDay(entry.created_at),
    entry.person_name,
    type,
    note === type ? '' : note,
    amount(entry.entry_amount_minor, entry.entry_currency),
    entry.entry_currency,
    amount(entry.amount_base_minor, entry.base_currency),
    entry.amount_base_minor === null ? '' : entry.base_currency,
    rateText(entry.exchange_rate_e9),
    entry.exchange_rate_source,
    activitySettlement(entry, format, base),
  ];
}

/**
 * Every entry as a CSV document, newest first.
 *
 * The reversal is the only reordering: `export_entries()` returns the rows
 * oldest-first, and the feed reads the other way.
 */
export function activityEntriesToCsv(
  entries: readonly ExportEntry[],
  format: ActivityFormatter,
  base: string,
): string {
  const lines = [
    csvRow(ACTIVITY_CSV_COLUMNS),
    ...entries
      .slice()
      .reverse()
      .map((entry) => csvRow(activityEntryToFields(entry, format, base))),
  ];
  // CRLF, because that is what RFC 4180 says and what Excel expects.
  return `${lines.join('\r\n')}\r\n`;
}
