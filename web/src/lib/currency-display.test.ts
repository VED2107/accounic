import { describe, expect, it } from 'vitest';

import {
  convertMinor,
  displaySymbol,
  parseRateToE9,
  rateDecimals,
  rateSentence,
  rateToE9,
  rateToInput,
} from '@/lib/currencies';
import { formatApprox, formatMoney } from '@/lib/money';
import { MANUAL_RATE_SOURCE, rateIsManual } from '@/lib/conversion';

/**
 * The currency presentation rules (upgrade §44, §45).
 *
 * The bug these pin: a screen showed `400 AED`, a rate of `1 AED = ₹25.9842`
 * and a converted `₹10,393.69`, and 400 × 25.9842 is ₹10,393.68. The
 * conversion was right — the stored rate is 25.984225 and the arithmetic runs
 * on all nine decimals of it. What was wrong is that the printed rate could not
 * reproduce the printed amount. Nothing here converts at a rounded rate; the
 * printed rate grows until it agrees.
 */

// The rates from the report, at the precision the database stores.
const AED_INR = rateToE9(25.984225);
const USD_INR = rateToE9(95.427612);

describe('conversion arithmetic', () => {
  it('converts 400 AED at the full stored rate, rounding only at the end', () => {
    expect(convertMinor(40_000, 'AED', 'INR', AED_INR)).toBe(1_039_369);
  });

  it('and ₹10,393.68 is what rounding the rate first would have given', () => {
    expect(convertMinor(40_000, 'AED', 'INR', rateToE9(25.9842))).toBe(1_039_368);
  });

  it('converts $40 at the full stored rate', () => {
    expect(convertMinor(4_000, 'USD', 'INR', USD_INR)).toBe(381_710);
  });

  it('agrees with the database for every documented case', () => {
    // public.convert_amount_minor(), same inputs, same answers.
    expect(convertMinor(100_000, 'INR', 'AED', rateToE9(0.0416))).toBe(4_160);
    expect(convertMinor(100_000, 'INR', 'JPY', rateToE9(1.78))).toBe(1_780);
    expect(convertMinor(12_345, 'INR', 'INR', null)).toBe(12_345);
    expect(convertMinor(100_000, 'INR', 'AED', null)).toBeNull();
  });
});

describe('rateSentence', () => {
  it('reads in the direction the user reads it', () => {
    expect(rateSentence('AED', 'INR', rateToE9(24.01))).toBe('1 AED = ₹24.01 INR');
  });

  it('shows enough of the rate to reproduce the amount printed beside it', () => {
    const sentence = rateSentence('AED', 'INR', AED_INR, 40_000);
    // Four decimals cannot: 400 × 25.9842 is ₹10,393.68, not ₹10,393.69.
    expect(sentence).not.toBe('1 AED = ₹25.9842 INR');

    const shown = Number(sentence.replace(/^1 AED = ₹/, '').replace(/ INR$/, ''));
    expect(convertMinor(40_000, 'AED', 'INR', rateToE9(shown))).toBe(
      convertMinor(40_000, 'AED', 'INR', AED_INR),
    );
  });

  it('does the same for the dollar case', () => {
    const sentence = rateSentence('USD', 'INR', USD_INR, 4_000);
    const shown = Number(sentence.replace(/^1 USD = ₹/, '').replace(/ INR$/, ''));
    expect(convertMinor(4_000, 'USD', 'INR', rateToE9(shown))).toBe(
      convertMinor(4_000, 'USD', 'INR', USD_INR),
    );
  });

  it('stays short when short is already exact', () => {
    expect(rateDecimals('AED', 'INR', rateToE9(25.5), 40_000)).toBe(4);
    expect(rateSentence('AED', 'INR', rateToE9(25.5), 40_000)).toBe('1 AED = ₹25.50 INR');
  });

  it('never asks for more precision than the column stores', () => {
    expect(rateDecimals('AED', 'INR', AED_INR, 999_999_999)).toBeLessThanOrEqual(9);
  });

  it('falls back to a readable precision when no amount is in hand', () => {
    expect(rateSentence('AED', 'INR', AED_INR)).toBe('1 AED = ₹25.9842 INR');
  });
  it('prints the rate it actually tested, not a float a hair away from it', () => {
    // The live rate that exposed this: 1 AED = 25.984215 INR. The precision
    // search accepted five decimals on 25.98422, while the text was rendered
    // from the raw double and came out 25.98421 — which multiplies out to
    // ₹10,393.68 under a printed ₹10,393.69. Both now come from the integer.
    const stored = 25_984_215_000;
    const sentence = rateSentence('AED', 'INR', stored, 40_000);
    const shown = Number(sentence.replace(/^1 AED = ₹/, '').replace(/ INR$/, ''));

    expect(convertMinor(40_000, 'AED', 'INR', stored)).toBe(1_039_369);
    expect(convertMinor(40_000, 'AED', 'INR', rateToE9(shown))).toBe(1_039_369);
    expect(sentence).toBe('1 AED = ₹25.98422 INR');
  });

  it('holds for every stored rate and amount on this ledger', () => {
    // The invariant, stated once: whatever precision is chosen, re-converting
    // at the printed rate must land on the printed amount.
    const cases: Array<[number, number, string]> = [
      [40_000, 25_984_215_000, 'AED'],
      [4_000, 95_427_628_000, 'USD'],
      [200_000, 25_984_215_000, 'AED'],
      [1, 95_427_628_000, 'USD'],
      [99_999_999, 25_984_215_000, 'AED'],
    ];

    for (const [amount, stored, from] of cases) {
      const sentence = rateSentence(from, 'INR', stored, amount);
      const shown = Number(
        sentence.replace(new RegExp(`^1 ${from} = ₹`), '').replace(/ INR$/, '').replace(/,/g, ''),
      );
      expect(convertMinor(amount, from, 'INR', rateToE9(shown))).toBe(
        convertMinor(amount, from, 'INR', stored),
      );
    }
  });
});

describe('the amount hierarchy', () => {
  it('writes an original amount with its symbol and its code', () => {
    expect(formatMoney(4_000, 'USD')).toBe('$40 USD');
    expect(formatMoney(500_000, 'INR')).toBe('₹5,000 INR');
    expect(formatMoney(1_000, 'EUR')).toBe('€10 EUR');
  });

  it('drops a symbol that cannot lead a figure, and keeps the code', () => {
    // د.إ is right-to-left and fights the digits beside it.
    expect(formatMoney(40_000, 'AED')).toBe('400 AED');
    expect(displaySymbol('AED')).toBe('');
    expect(displaySymbol('INR')).toBe('₹');
  });

  it('writes a converted amount as an approximation, in full', () => {
    expect(formatApprox(1_039_369, 'INR')).toBe('≈ ₹10,393.69 INR');
    expect(formatApprox(381_710, 'INR')).toBe('≈ ₹3,817.10 INR');
  });

  it('handles the awkward values without special-casing at the call site', () => {
    expect(formatMoney(0, 'INR')).toBe('₹0 INR');
    expect(formatMoney(-500_000, 'INR')).toBe('−₹5,000 INR');
    expect(formatMoney(1_000, 'JPY')).toBe('¥1,000 JPY'); // no decimals, ever
    // Three decimals, the Arabic mark dropped — and Latin digits, because a
    // column of figures that mixes numbering systems cannot be read at all.
    expect(formatMoney(1_234, 'KWD')).toBe('1.234 KWD');
    expect(formatMoney(40_000, 'SAR')).toBe('﷼400 SAR'.replace('﷼', '')); // symbol dropped too
    expect(formatMoney(1_000_000_000, 'INR')).toBe('₹1,00,00,000 INR');
  });

  it('renders an unknown currency rather than throwing', () => {
    expect(formatMoney(1_000, 'ZZZ')).toBe('10 ZZZ'); // two decimals assumed, none needed
    expect(formatMoney(1_000, null)).toBe('₹10 INR');
  });
});

describe('a rate a human typed', () => {
  it('parses to the same nine-decimal scale the column stores', () => {
    expect(parseRateToE9('96.5')).toBe(96_500_000_000);
    expect(parseRateToE9('95.427612')).toBe(USD_INR);
    expect(parseRateToE9(' 1,234.5 ')).toBe(1_234_500_000_000);
  });

  it('refuses what it cannot store exactly, and what is not a rate', () => {
    expect(parseRateToE9('95.4276123456')).toBeNull(); // ten decimals
    expect(parseRateToE9('0')).toBeNull();
    expect(parseRateToE9('-5')).toBeNull();
    expect(parseRateToE9('')).toBeNull();
    expect(parseRateToE9('abc')).toBeNull();
  });

  it('round-trips through the editable form', () => {
    for (const rateE9 of [96_500_000_000, USD_INR, AED_INR, 1_000_000_000]) {
      expect(parseRateToE9(rateToInput(rateE9))).toBe(rateE9);
    }
  });

  it('is recognised by its provenance, and only by that exact marker', () => {
    expect(rateIsManual(MANUAL_RATE_SOURCE)).toBe(true);
    expect(rateIsManual(' Manual-Rate ')).toBe(true);
    // 0011 defaults a missing source to the bare word 'manual', so rows written
    // by a client that sent none must NOT read as hand-rated.
    expect(rateIsManual('manual')).toBe(false);
    expect(rateIsManual('live')).toBe(false);
    expect(rateIsManual(null)).toBe(false);
  });

  it('converts at the typed rate, at full precision', () => {
    expect(convertMinor(4_000, 'USD', 'INR', parseRateToE9('96.5'))).toBe(386_000);
  });
});
