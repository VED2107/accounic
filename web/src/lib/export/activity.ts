import { statementDate } from '@/lib/dates';
import type { ExportRequest } from '@/lib/export/load';

/**
 * What the Activity export is (Activity → Export).
 *
 * The Activity screen is a chronological feed: a day, then everything that
 * happened on it, then the day before. The export is that document, not a
 * ledger regrouped by account — the workspace report on Profile is already the
 * per-account view, and producing a second one here would answer a question
 * nobody asked from this screen.
 *
 * Two independent choices describe an export, and they compose freely:
 *
 *     DATE      one day · a range · all activity
 *     CATEGORY  Everything · Transactions · Settlements
 *
 * Both are mappings onto the filter contract `export_entries()` already accepts
 * (0025). Nothing is computed here and nothing is filtered on the client:
 *
 *   * THE CATEGORY IS THE ACTIVITY TAB'S OWN FILTER. `activity_page()` filters
 *     on `entry_kind`; `export_entries()` filters on the same column expressed
 *     as `kinds`, because a transaction's kind is its `txn_type` and a
 *     settlement's is the word "settlement".
 *   * THE DATE IS `from`/`to`. One day is a range whose ends are equal. No new
 *     filter was invented for either.
 *   * VOIDED HISTORY IS OUT, because `activity_page()` excludes it too. The
 *     export must not show what the screen does not.
 *   * SCOPE STAYS `all`. The Activity feed includes the opening book, so the
 *     export of that feed does as well — labelled as an opening balance, the
 *     way the screen labels it.
 *
 * Mirrored by `app/lib/data/export_models.dart` (`ExportFilters.activity`).
 */

/** The three tabs on the Activity screen, as the URL spells them. */
export type ActivityView = 'all' | 'transaction' | 'settlement';

/** The dates an export covers. Both null is the whole feed. */
export interface ActivityRange {
  from: string | null;
  to: string | null;
}

/** The whole feed. */
export const ALL_ACTIVITY: ActivityRange = { from: null, to: null };

/** `kinds` for each tab. `null` is "no kind filter" — the Everything tab. */
const KINDS: Record<ActivityView, string[] | null> = {
  all: null,
  transaction: ['credit', 'debit'],
  settlement: ['settlement'],
};

/** How the exported document names the category it holds. */
export const VIEW_LABEL: Record<ActivityView, string> = {
  all: 'Everything',
  transaction: 'Transactions',
  settlement: 'Settlements',
};

/** The Activity URL's `kind` parameter, read the way the page reads it. */
export function parseView(value: string | null | undefined): ActivityView {
  return value === 'transaction' || value === 'settlement' ? value : 'all';
}

/** `YYYY-MM-DD`, or null. Anything else is not a day and is treated as none. */
export function parseDay(value: string | null | undefined): string | null {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
}

/** A range from a query string. An unreadable end is simply no end. */
export function parseRange(
  from: string | null | undefined,
  to: string | null | undefined,
): ActivityRange {
  return { from: parseDay(from), to: parseDay(to) };
}

/** One day, as a range whose ends are the same day. */
export function dayRange(day: string): ActivityRange {
  return { from: day, to: day };
}

/** True when a range names exactly one day. */
export function isSingleDay(range: ActivityRange): boolean {
  return range.from !== null && range.from === range.to;
}

/**
 * True when the ends are the wrong way round.
 *
 * The database would happily return nothing for it, but "nothing" is a bad
 * answer to a question the user did not mean to ask, so both clients refuse to
 * export until it is fixed.
 */
export function rangeIsBackwards(range: ActivityRange): boolean {
  return range.from !== null && range.to !== null && range.from > range.to;
}

/**
 * What the document says it is showing.
 *
 *     All activity
 *     04 Sep 2026
 *     28 Aug 2026 → 04 Sep 2026
 *     Up to 04 Sep 2026
 *     From 28 Aug 2026
 */
export function activityScopeLabel(range: ActivityRange): string {
  const { from, to } = range;
  if (!from && !to) return 'All activity';
  if (from && to) return from === to ? statementDate(from) : `${statementDate(from)} → ${statementDate(to)}`;
  return from ? `From ${statementDate(from)}` : `Up to ${statementDate(to!)}`;
}

/** The filter contract for one Activity export. */
export function activityExportRequest(
  view: ActivityView,
  range: ActivityRange,
): ExportRequest {
  return {
    from: range.from,
    to: range.to,
    kinds: KINDS[view],
    scope: 'all',
    includeVoid: false,
  };
}

/** The filename: named after what is in it, dated, sortable in a folder. */
export function activityExportFilename(
  extension: 'csv' | 'pdf',
  view: ActivityView,
  range: ActivityRange,
  today: Date = new Date(),
): string {
  const parts = ['accounic', 'activity'];
  if (view !== 'all') parts.push(view === 'transaction' ? 'transactions' : 'settlements');

  const { from, to } = range;
  if (from && to && from !== to) parts.push(from, 'to', to);
  else if (from ?? to) parts.push((from ?? to)!);
  else parts.push(today.toISOString().slice(0, 10));

  return `${parts.join('-')}.${extension}`;
}
