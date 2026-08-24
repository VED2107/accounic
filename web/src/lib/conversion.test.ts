import { describe, expect, it } from 'vitest';
import { conversionArgs, manualMinor } from '@/lib/conversion';
import { convertMinor, rateToE9 } from '@/lib/currencies';

/**
 * The manual converted amount (upgrade §40).
 *
 * The brief's case throughout: an AED account, Rs 1,000 handed over, a rate
 * that makes it AED 44.20, and AED 43 actually given at the counter.
 */

// 1 INR = 0.0442 AED.
const RATE_E9 = rateToE9(0.0442);
const RUPEES_1000 = 100_000; // minor units
const AUTO_AED = convertMinor(RUPEES_1000, 'INR', 'AED', RATE_E9); // 4420
const ACTUAL_AED = 4_300;

describe('automatic conversion', () => {
  it('sends what was entered and the rate, and no converted figure', () => {
    const args = conversionArgs(RUPEES_1000, 'INR', 'AED', RATE_E9, 'open.er-api.com');

    expect(args.p_entered_amount_minor).toBe(RUPEES_1000);
    expect(args.p_entered_currency).toBe('INR');
    expect(args.p_exchange_rate_e9).toBe(RATE_E9);
    expect(args.p_conversion_mode).toBe('automatic');
    // The client never works out the account amount itself (context.md §7).
    expect(args.p_amount_minor).toBeNull();
    expect(args.p_converted_amount_minor).toBeNull();
  });

  it('carries no conversion at all for a same-currency entry', () => {
    const args = conversionArgs(RUPEES_1000, 'INR', 'INR', null, null);

    expect(args.p_amount_minor).toBe(RUPEES_1000);
    expect(args.p_entered_currency).toBeNull();
    expect(args.p_conversion_mode).toBeNull();
    expect(args.p_converted_amount_minor).toBeNull();
  });

  it('ignores an override on a same-currency entry rather than mislabelling it', () => {
    const args = conversionArgs(RUPEES_1000, 'INR', 'INR', null, null, 999);

    expect(args.p_amount_minor).toBe(RUPEES_1000);
    expect(args.p_converted_amount_minor).toBeNull();
    expect(args.p_conversion_mode).toBeNull();
  });
});

describe('manual converted amount', () => {
  it('sends the actual figure alongside the entered one and the rate', () => {
    const args = conversionArgs(RUPEES_1000, 'INR', 'AED', RATE_E9, 'test', ACTUAL_AED);

    expect(args.p_converted_amount_minor).toBe(ACTUAL_AED);
    expect(args.p_conversion_mode).toBe('manual');
    // The rate is not destroyed by the override — it is the audit reference.
    expect(args.p_exchange_rate_e9).toBe(RATE_E9);
    expect(args.p_entered_amount_minor).toBe(RUPEES_1000);
    expect(args.p_entered_currency).toBe('INR');
  });

  it('differs from what the rate said, which is the point of it', () => {
    expect(AUTO_AED).toBe(4_420);
    expect(ACTUAL_AED).not.toBe(AUTO_AED);
  });

  it('is still manual when it happens to equal the automatic figure', () => {
    const args = conversionArgs(RUPEES_1000, 'INR', 'AED', RATE_E9, 'test', AUTO_AED);

    expect(args.p_converted_amount_minor).toBe(AUTO_AED);
    expect(args.p_conversion_mode).toBe('manual');
  });

  it('switching back to automatic drops the figure, not just the label', () => {
    const args = conversionArgs(RUPEES_1000, 'INR', 'AED', RATE_E9, 'test', null);

    expect(args.p_conversion_mode).toBe('automatic');
    expect(args.p_converted_amount_minor).toBeNull();
  });
});

describe('reading the override off the form', () => {
  it('parses the actual amount against the ACCOUNT currency', () => {
    // AED has two decimals: "43" is 4300 minor, not 43.
    expect(manualMinor('43', 'manual', 'AED')).toEqual({ minor: 4_300 });
    expect(manualMinor('43.00', 'manual', 'AED')).toEqual({ minor: 4_300 });
  });

  it('respects a currency with no minor unit', () => {
    expect(manualMinor('4300', 'manual', 'JPY')).toEqual({ minor: 4_300 });
  });

  it('ignores a stale value once the user switches back to automatic', () => {
    expect(manualMinor('43', 'automatic', 'AED')).toEqual({ minor: null });
    expect(manualMinor('43', null, 'AED')).toEqual({ minor: null });
    expect(manualMinor('43', undefined, 'AED')).toEqual({ minor: null });
  });

  it('refuses manual mode with nothing typed', () => {
    const result = manualMinor('   ', 'manual', 'AED');
    expect('error' in result).toBe(true);
    if ('error' in result) expect(result.error).toContain('AED');
  });

  it('refuses text that is not an amount', () => {
    expect('error' in manualMinor('forty three', 'manual', 'AED')).toBe(true);
  });

  it('refuses zero rather than treating it as no override', () => {
    expect('error' in manualMinor('0', 'manual', 'AED')).toBe(true);
  });
});
