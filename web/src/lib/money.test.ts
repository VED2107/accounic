import { describe, expect, it } from 'vitest';
import {
  balanceLabel,
  balanceTone,
  formatMinor,
  minorToInput,
  netSummary,
  parseAmountToMinor,
} from './money';

/**
 * Money tests (context.md §7, §33).
 *
 * The same cases as app/test/money_test.dart, deliberately. Web and Flutter
 * must agree on every one of them: if they diverge, a user sees two different
 * balances on two devices for the same ledger.
 */

describe('parseAmountToMinor', () => {
  it('parses whole rupees', () => {
    expect(parseAmountToMinor('5000')).toBe(500_000);
    expect(parseAmountToMinor('0')).toBe(0);
    expect(parseAmountToMinor('1')).toBe(100);
  });

  it('parses paise exactly', () => {
    expect(parseAmountToMinor('100.50')).toBe(10_050);
    expect(parseAmountToMinor('0.01')).toBe(1);
    expect(parseAmountToMinor('0.1')).toBe(10);
    expect(parseAmountToMinor('.5')).toBe(50);
    expect(parseAmountToMinor('12.34')).toBe(1234);
  });

  it('ignores grouping, spaces and currency symbols', () => {
    expect(parseAmountToMinor('1,234.50')).toBe(123_450);
    expect(parseAmountToMinor(' 1 234.56 ')).toBe(123_456);
    expect(parseAmountToMinor('₹10,000')).toBe(1_000_000);
    expect(parseAmountToMinor('1,00,000')).toBe(10_000_000);
  });

  it('refuses more than two decimals rather than rounding money away', () => {
    expect(parseAmountToMinor('10.999')).toBeNull();
    expect(parseAmountToMinor('0.001')).toBeNull();
  });

  it('refuses nonsense', () => {
    for (const input of ['', '   ', 'abc', '.', '-', '1.2.3']) {
      expect(parseAmountToMinor(input)).toBeNull();
    }
  });

  it('keeps the sign for negatives, which callers then reject', () => {
    expect(parseAmountToMinor('-500')).toBe(-50_000);
  });

  it('the classic float trap stays exact', () => {
    // 0.1 + 0.2 !== 0.3 in binary floating point; 10 + 20 === 30 always.
    expect(parseAmountToMinor('0.10')! + parseAmountToMinor('0.20')!).toBe(
      parseAmountToMinor('0.30'),
    );
    expect(0.1 + 0.2).not.toBe(0.3); // the reason this module exists
  });

  it('round-trips through the editable form', () => {
    for (const minor of [1, 99, 100, 12_345, 1_000_000, 999_999_999]) {
      expect(parseAmountToMinor(minorToInput(minor))).toBe(minor);
    }
  });
});

describe('minorToInput', () => {
  it('drops the decimals on whole amounts', () => {
    expect(minorToInput(500_000)).toBe('5000');
    expect(minorToInput(0)).toBe('0');
  });

  it('pads paise', () => {
    expect(minorToInput(10_050)).toBe('100.50');
    expect(minorToInput(1)).toBe('0.01');
    expect(minorToInput(10)).toBe('0.10');
  });
});

describe('formatMinor', () => {
  it('formats rupees with Indian grouping', () => {
    // Indian grouping only diverges from Western above 99,999.
    expect(formatMinor(1_000_000)).toBe('₹10,000');
    expect(formatMinor(10_000_000)).toBe('₹1,00,000');
    expect(formatMinor(100_000_000)).toBe('₹10,00,000');
    expect(formatMinor(123_450)).toBe('₹1,234.50');
  });

  it('shows paise only when there are paise', () => {
    expect(formatMinor(500_000)).toBe('₹5,000');
    expect(formatMinor(500_050)).toBe('₹5,000.50');
  });

  it('honours the profile currency', () => {
    expect(formatMinor(123_450, 'USD')).toBe('$1,234.50');
    expect(formatMinor(500_000, 'GBP')).toBe('£5,000');
  });

  it('renders negatives with a minus sign, never parentheses', () => {
    expect(formatMinor(-500_000)).toBe('−₹5,000');
  });

  it('rejects a non-integer amount instead of displaying a rounded one', () => {
    expect(() => formatMinor(10.5)).toThrow();
  });
});

describe('balance meaning (context.md §8)', () => {
  it('positive net means they owe the user', () => {
    expect(balanceTone(1)).toBe('receivable');
    expect(balanceLabel(1000)).toBe('You will receive');
    expect(netSummary(1_250_000)).toBe('₹12,500 receivable');
  });

  it('negative net means the user owes them', () => {
    expect(balanceTone(-1)).toBe('payable');
    expect(balanceLabel(-1000)).toBe('You will pay');
    expect(netSummary(-600_000)).toBe('₹6,000 payable');
  });

  it('zero is settled', () => {
    expect(balanceTone(0)).toBe('settled');
    expect(netSummary(0)).toBe('Settled up');
  });
});

/**
 * The accounting identities themselves live in SQL and are tested there
 * (db/tests/01_accounting_engine.sql). These assert only that the client's
 * reading of a balance matches the engine's — the direction and the label — so
 * no arithmetic is duplicated here.
 */
describe('reading an engine balance', () => {
  const cases = [
    { label: 'credit only', receivable: 1_000_000, payable: 0, net: 1_000_000, tone: 'receivable' },
    { label: 'debit only', receivable: 0, payable: 500_000, net: -500_000, tone: 'payable' },
    { label: 'mixed, net receivable', receivable: 1_000_000, payable: 400_000, net: 600_000, tone: 'receivable' },
    { label: 'mixed, net payable', receivable: 40_000, payable: 225_000, net: -185_000, tone: 'payable' },
    { label: 'fully settled', receivable: 0, payable: 0, net: 0, tone: 'settled' },
  ] as const;

  for (const testCase of cases) {
    it(testCase.label, () => {
      expect(testCase.receivable - testCase.payable).toBe(testCase.net);
      expect(balanceTone(testCase.net)).toBe(testCase.tone);
    });
  }
});
