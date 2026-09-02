import { describe, expect, it } from 'vitest';
import { padDailyBuckets } from '@/lib/series';
import type { ActivityBucket } from '@/lib/queries';

const day = (bucket: string, credit = 0, debit = 0): ActivityBucket => ({
  bucket,
  credit,
  debit,
  settled: 0,
  entries: credit || debit ? 1 : 0,
});

/**
 * The bug this pins: a month with five active days drew five columns, each a
 * fifth of the card wide, because the chart gave every returned bucket an equal
 * share of the width. A day with no movement is a fact about the month and has
 * to take up its own width.
 */
describe('padding a daily series', () => {
  it('returns one entry per day across the window', () => {
    expect(padDailyBuckets([day('2026-09-01', 500)], 30)).toHaveLength(30);
  });

  it('keeps the real buckets and zero-fills the rest', () => {
    const padded = padDailyBuckets([day('2026-09-01', 500), day('2026-08-30', 0, 200)], 5);
    expect(padded.map((b) => b.bucket)).toEqual([
      '2026-08-28',
      '2026-08-29',
      '2026-08-30',
      '2026-08-31',
      '2026-09-01',
    ]);
    expect(padded.map((b) => b.credit)).toEqual([0, 0, 0, 0, 500]);
    expect(padded.map((b) => b.debit)).toEqual([0, 0, 200, 0, 0]);
  });

  it('ends on the newest day in the data, not on today', () => {
    // Stale data still draws a chart that ends where the data ends.
    const padded = padDailyBuckets([day('2020-01-05', 100)], 3);
    expect(padded.at(-1)!.bucket).toBe('2020-01-05');
    expect(padded).toHaveLength(3);
  });

  it('crosses a month boundary without dropping or repeating a day', () => {
    const padded = padDailyBuckets([day('2026-03-02', 1)], 4);
    expect(padded.map((b) => b.bucket)).toEqual([
      '2026-02-27',
      '2026-02-28',
      '2026-03-01',
      '2026-03-02',
    ]);
  });

  it('tolerates a full timestamp from the RPC', () => {
    const padded = padDailyBuckets([day('2026-09-01T00:00:00+00:00', 700)], 2);
    expect(padded.at(-1)).toMatchObject({ bucket: '2026-09-01', credit: 700 });
  });

  it('is empty for an empty window rather than throwing', () => {
    expect(padDailyBuckets([], 0)).toEqual([]);
  });
});
