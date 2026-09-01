import { describe, expect, it } from 'vitest';

import {
  invertRateE9,
  isUsableRateE9,
  MAX_RATE_E9,
  RATE_SCALE,
  usableRateToE9,
} from './currencies';
import { parseFallback, parsePrimary } from './rate-source';

/**
 * What a rate provider does when it is having a bad day (upgrade §6, §7).
 *
 * These are the cases that never reach a network test: a 200 response whose
 * body is an error, a rates map full of strings, a published zero. Each one is
 * a way for a broken provider to silently change someone's money, so each one
 * has to end at "no rate for this pair" rather than at a number.
 */

describe('parsePrimary — open.er-api.com', () => {
  it('reads a successful table', () => {
    const table = parsePrimary({
      result: 'success',
      time_last_update_utc: 'Mon, 01 Sep 2026 00:00:01 +0000',
      rates: { INR: 23.9, USD: 0.272 },
    });

    expect(table?.source).toBe('open.er-api.com');
    expect(table?.asOf).toBe('2026-09-01');
    expect(table?.rates.INR).toBe(23.9);
  });

  it('refuses a 200 that carries an error', () => {
    expect(parsePrimary({ result: 'error', 'error-type': 'unsupported-code' })).toBeNull();
  });

  it('refuses a payload that is not an object', () => {
    expect(parsePrimary(null)).toBeNull();
    expect(parsePrimary('rates')).toBeNull();
    expect(parsePrimary([1, 2, 3])).toBeNull();
  });

  it('drops entries that are not numbers, and keeps the rest', () => {
    const table = parsePrimary({
      result: 'success',
      rates: { INR: 23.9, USD: '0.272', EUR: null, GBP: Number.NaN },
    });

    expect(Object.keys(table?.rates ?? {})).toEqual(['INR']);
  });

  it('refuses a table with nothing usable left in it', () => {
    expect(parsePrimary({ result: 'success', rates: { INR: '23.9' } })).toBeNull();
    expect(parsePrimary({ result: 'success', rates: {} })).toBeNull();
  });

  it('falls back to today when the timestamp is unreadable', () => {
    const table = parsePrimary({ result: 'success', time_last_update_utc: 'soon', rates: { INR: 1 } });
    expect(table?.asOf).toBe(new Date().toISOString().slice(0, 10));
  });
});

describe('parseFallback — frankfurter.dev', () => {
  it('reads a table and keeps the published date', () => {
    const table = parseFallback({ date: '2026-08-29', rates: { INR: 94.1 } });
    expect(table).toEqual({
      rates: { INR: 94.1 },
      asOf: '2026-08-29',
      source: 'frankfurter.dev (ECB)',
    });
  });

  it('refuses an empty or malformed body', () => {
    expect(parseFallback({})).toBeNull();
    expect(parseFallback({ rates: null })).toBeNull();
    expect(parseFallback(undefined)).toBeNull();
  });
});

describe('a rate has to be usable before it is used', () => {
  it('accepts an ordinary rate', () => {
    expect(isUsableRateE9(RATE_SCALE)).toBe(true);
    expect(usableRateToE9(23.9)).toBe(23_900_000_000);
  });

  it('refuses zero, negatives and nonsense — a zero rate erases an amount', () => {
    expect(usableRateToE9(0)).toBeNull();
    expect(usableRateToE9(-1)).toBeNull();
    expect(usableRateToE9(Number.NaN)).toBeNull();
    expect(usableRateToE9(Number.POSITIVE_INFINITY)).toBeNull();
    expect(usableRateToE9('23.9' as unknown as number)).toBeNull();
  });

  it('refuses a rate so small it has already rounded away', () => {
    expect(usableRateToE9(1e-12)).toBeNull();
  });

  it('refuses a rate no real pair reaches', () => {
    expect(isUsableRateE9(MAX_RATE_E9 + 1)).toBe(false);
  });

  it('inverts a stored rate, and refuses to divide by a bad one', () => {
    expect(invertRateE9(2 * RATE_SCALE)).toBe(RATE_SCALE / 2);
    expect(invertRateE9(0)).toBeNull();
    expect(invertRateE9(-5)).toBeNull();
  });

  it('round-trips an inversion back to where it started', () => {
    const rate = usableRateToE9(23.9)!;
    expect(invertRateE9(invertRateE9(rate)!)).toBeCloseTo(rate, -3);
  });
});
