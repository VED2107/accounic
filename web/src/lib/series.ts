import type { ActivityBucket } from '@/lib/queries';
import { isReceivable } from '@/lib/direction';
import type { PersonBalance, TimelineEntry } from '@/lib/types';

/**
 * Series maths for the small trend graphics (context.md §13, §30).
 *
 * Everything here is derived from figures the app already fetched — no extra
 * query, no invented data point. Where a number cannot be derived honestly it is
 * not shown, which is why every function can return null.
 */

export interface Trend {
  /** Cumulative series, oldest first, in minor units. */
  points: number[];
  /** Movement of the last half of the window against the half before it. */
  changePercent: number | null;
  /** Total flow across the whole window. */
  total: number;
}

function cumulative(values: number[]): number[] {
  let running = 0;
  return values.map((value) => (running += value));
}

/**
 * Momentum, not growth: the second half of the window against the first. It is
 * the only honest comparison available from a 30-day flow series, so the label
 * beside it says exactly that.
 */
function halfOverHalf(values: number[]): number | null {
  if (values.length < 4) return null;
  const mid = Math.floor(values.length / 2);
  const first = values.slice(0, mid).reduce((a, b) => a + b, 0);
  const second = values.slice(mid).reduce((a, b) => a + b, 0);
  if (first === 0) return second === 0 ? 0 : null;
  return ((second - first) / first) * 100;
}

/** Cumulative credit, debit, settled and net across the buckets, oldest first. */
export function trendsFromBuckets(buckets: ActivityBucket[]): {
  credit: Trend;
  debit: Trend;
  settled: Trend;
  net: Trend;
} {
  // The RPC returns newest first; a chart reads left to right in time order.
  const ordered = [...buckets].sort((a, b) => (a.bucket < b.bucket ? -1 : 1));
  const credit = ordered.map((bucket) => bucket.credit);
  const debit = ordered.map((bucket) => bucket.debit);
  const settled = ordered.map((bucket) => bucket.settled);
  const net = ordered.map((_, index) => (credit[index] ?? 0) - (debit[index] ?? 0));

  const make = (values: number[]): Trend => ({
    points: cumulative(values),
    changePercent: halfOverHalf(values),
    total: values.reduce((a, b) => a + b, 0),
  });

  return { credit: make(credit), debit: make(debit), settled: make(settled), net: make(net) };
}

/**
 * How one entry moves the net balance.
 *
 * A receivable transaction pushes the balance up; a payable one pulls it down.
 * Settlements move it back towards zero from whichever side they close: money
 * arriving retires a receivable, money paid retires a payable. Voided entries
 * move nothing — that is the whole point of voiding.
 */
export function netDelta(entry: TimelineEntry): number {
  if (entry.is_void) return 0;
  if (entry.entry_kind === 'transaction') {
    return isReceivable(entry.entry_type as 'credit' | 'debit')
      ? entry.amount_minor
      : -entry.amount_minor;
  }
  return entry.money_direction === 'in' ? -entry.amount_minor : entry.amount_minor;
}

/**
 * The running net balance behind a person's visible history, oldest first.
 *
 * Walked backwards from the balance the database reports, so the series ends on
 * the figure printed above it rather than on an approximation of it. Only the
 * entries on screen are covered, so it is labelled as recent history, not as the
 * account's whole life.
 */
export function personBalanceSeries(
  entries: TimelineEntry[],
  balance: PersonBalance,
): number[] | null {
  const live = entries.filter((entry) => !entry.is_void);
  if (live.length < 3) return null;

  const series: number[] = [balance.net_balance];
  let running = balance.net_balance;
  // `entries` arrives newest first.
  for (const entry of live) {
    running -= netDelta(entry);
    series.push(running);
  }
  return series.reverse();
}
