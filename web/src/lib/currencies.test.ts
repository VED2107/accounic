import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  CURRENCIES,
  convertMinor,
  currencyLabel,
  decimalsFor,
  isSupportedCurrency,
  minorPerMajor,
  rateSentence,
  rateToE9,
} from './currencies';
import { formatMinor, minorToInput, parseAmountToMinor } from './money';

/**
 * Currency tests (upgrade §19, §20).
 *
 * The same cases as app/test/currencies_test.dart, deliberately — and the same
 * conversion arithmetic as db/tests/04_currency.sql. Three runtimes convert
 * money; if any two of them disagree by a single minor unit, a user sees two
 * different balances on two devices for the same ledger.
 */

const shared = JSON.parse(
  readFileSync(fileURLToPath(new URL('../../../shared/currencies.json', import.meta.url)), 'utf8'),
) as { currencies: Array<{ code: string; name: string; symbol: string; decimals: number }> };

describe('the generated list', () => {
  it('matches shared/currencies.json exactly', () => {
    expect(CURRENCIES).toEqual(shared.currencies);
  });

  it('has no duplicate codes', () => {
    const codes = CURRENCIES.map((c) => c.code);
    expect(new Set(codes).size).toBe(codes.length);
  });

  it('carries the currencies the product is actually used with', () => {
    for (const code of ['INR', 'AED', 'USD', 'EUR', 'GBP', 'JPY']) {
      expect(isSupportedCurrency(code)).toBe(true);
    }
  });

  it('rejects anything not on the list', () => {
    expect(isSupportedCurrency('XXX')).toBe(false);
    expect(isSupportedCurrency('')).toBe(false);
    expect(isSupportedCurrency(null)).toBe(false);
  });

  it('is case-insensitive about codes', () => {
    expect(isSupportedCurrency('aed')).toBe(true);
    expect(decimalsFor('jpy')).toBe(0);
  });

  it('labels a currency unambiguously — the code first, because $ is four of them', () => {
    expect(currencyLabel('AED')).toBe('AED — UAE Dirham (د.إ)');
  });
});

describe('minor units', () => {
  it('knows the yen has none', () => {
    expect(decimalsFor('JPY')).toBe(0);
    expect(minorPerMajor('JPY')).toBe(1);
  });

  it('knows the Gulf dinars have three', () => {
    expect(decimalsFor('KWD')).toBe(3);
    expect(minorPerMajor('KWD')).toBe(1000);
  });

  it('defaults an unknown code to two rather than throwing', () => {
    expect(decimalsFor('ZZZ')).toBe(2);
  });
});

describe('parsing against a currency', () => {
  it('parses yen as whole units', () => {
    expect(parseAmountToMinor('1000', 'JPY')).toBe(1000);
  });

  it('refuses a fraction of a yen instead of rounding it away', () => {
    expect(parseAmountToMinor('1000.5', 'JPY')).toBeNull();
  });

  it('parses three decimals for a dinar', () => {
    expect(parseAmountToMinor('1.234', 'KWD')).toBe(1234);
    expect(parseAmountToMinor('1.2345', 'KWD')).toBeNull();
  });

  it('still parses rupees the way it always did', () => {
    expect(parseAmountToMinor('1,234.50', 'INR')).toBe(123_450);
    expect(parseAmountToMinor('1,234.50')).toBe(123_450);
  });

  it('round-trips through minorToInput', () => {
    for (const [minor, code] of [
      [123_450, 'INR'],
      [1000, 'JPY'],
      [1234, 'KWD'],
    ] as const) {
      expect(parseAmountToMinor(minorToInput(minor, code), code)).toBe(minor);
    }
  });
});

describe('formatting', () => {
  it('never shows a decimal on a zero-decimal currency', () => {
    expect(formatMinor(1000, 'JPY')).not.toContain('.');
  });

  it('appends the ISO code when asked, because symbols are ambiguous', () => {
    expect(formatMinor(4160, 'AED', { withCode: true })).toContain('AED');
  });
});

describe('conversion', () => {
  it('agrees with public.convert_amount_minor for the documented example', () => {
    // ₹1,000.00 at 1 INR = 0.0416 AED is AED 41.60.
    expect(convertMinor(100_000, 'INR', 'AED', rateToE9(0.0416))).toBe(4160);
  });

  it('shifts the exponent when the decimals differ', () => {
    // ₹1,000.00 at 1 INR = 1.78 JPY is ¥1,780 — 1780 minor units, not 178000.
    expect(convertMinor(100_000, 'INR', 'JPY', rateToE9(1.78))).toBe(1780);
    expect(convertMinor(1780, 'JPY', 'INR', rateToE9(0.561797752))).toBe(100_000);
  });

  it('is the identity for the same currency, with or without a rate', () => {
    expect(convertMinor(12_345, 'INR', 'INR', null)).toBe(12_345);
  });

  it('returns null rather than zero when there is no rate', () => {
    expect(convertMinor(100_000, 'INR', 'AED', null)).toBeNull();
    expect(convertMinor(100_000, 'INR', 'AED', 0)).toBeNull();
  });

  it('states the rate in the direction the user reads it', () => {
    expect(rateSentence('AED', 'INR', rateToE9(24.01))).toBe('1 AED = ₹24.01 INR');
  });
});
