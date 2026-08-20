/**
 * Money handling (context.md §7).
 *
 * Every amount in this application is an integer number of minor units
 * (paise for INR). Floating point never touches a balance: the only place a
 * decimal exists is at the edges — parsing what the user typed, and formatting
 * for display.
 *
 * The database returns bigint columns as JSON numbers. Balances stay far below
 * Number.MAX_SAFE_INTEGER (9.007e15 minor units ≈ ₹90 trillion) and the
 * amount_minor CHECK constraint caps a single row well under that, so `number`
 * is safe here — asserted by assertSafeMinor().
 */

/** Minor units per major unit. Every currency this app supports uses 2. */
export const MINOR_PER_MAJOR = 100;

const CURRENCY_LOCALE: Record<string, string> = {
  INR: 'en-IN',
  USD: 'en-US',
  EUR: 'de-DE',
  GBP: 'en-GB',
  AED: 'en-AE',
  AUD: 'en-AU',
  CAD: 'en-CA',
  SGD: 'en-SG',
};

export function localeFor(currency: string): string {
  return CURRENCY_LOCALE[currency.toUpperCase()] ?? 'en-US';
}

export function assertSafeMinor(minor: number): number {
  if (!Number.isFinite(minor) || !Number.isInteger(minor)) {
    throw new Error(`Amount must be an integer number of minor units, got ${minor}`);
  }
  if (!Number.isSafeInteger(minor)) {
    throw new Error(`Amount ${minor} exceeds safe integer range`);
  }
  return minor;
}

/**
 * Parse user input into minor units.
 *
 * Accepts "1,234.5", "₹1234", " 1 234.56 ". Rejects anything with more than two
 * decimal places rather than silently rounding away the user's money.
 * Returns null when the input is not a usable amount.
 */
export function parseAmountToMinor(input: string): number | null {
  const cleaned = input
    .replace(/[\s,  ]/g, '')
    .replace(/[^\d.\-]/g, '');

  if (cleaned === '' || cleaned === '-' || cleaned === '.') return null;
  if ((cleaned.match(/\./g)?.length ?? 0) > 1) return null;

  const negative = cleaned.startsWith('-');
  const unsigned = negative ? cleaned.slice(1) : cleaned;
  if (!/^\d*(\.\d*)?$/.test(unsigned)) return null;

  const [whole = '', fraction = ''] = unsigned.split('.');
  if (fraction.length > 2) return null;
  if (whole === '' && fraction === '') return null;

  const paddedFraction = fraction.padEnd(2, '0');
  const minor = Number(whole || '0') * MINOR_PER_MAJOR + Number(paddedFraction || '0');
  if (!Number.isSafeInteger(minor)) return null;

  return negative ? -minor : minor;
}

/** Minor units → a plain editable string, e.g. 1050050 → "10500.50". */
export function minorToInput(minor: number): string {
  assertSafeMinor(minor);
  const negative = minor < 0;
  const abs = Math.abs(minor);
  const whole = Math.trunc(abs / MINOR_PER_MAJOR);
  const fraction = abs % MINOR_PER_MAJOR;
  const body = fraction === 0 ? String(whole) : `${whole}.${String(fraction).padStart(2, '0')}`;
  return negative ? `-${body}` : body;
}

export interface FormatOptions {
  /** Drop ".00" on whole amounts. Default true — the dashboard reads better. */
  compactDecimals?: boolean;
  /** Render the currency symbol. Default true. */
  withSymbol?: boolean;
  /** Always show a leading + or −. Default false. */
  signed?: boolean;
}

/** Minor units → display string, e.g. 1050050 → "₹10,500.50". */
export function formatMinor(
  minor: number,
  currency = 'INR',
  options: FormatOptions = {},
): string {
  const { compactDecimals = true, withSymbol = true, signed = false } = options;
  assertSafeMinor(minor);

  const abs = Math.abs(minor);
  const hasFraction = abs % MINOR_PER_MAJOR !== 0;
  const digits = compactDecimals && !hasFraction ? 0 : 2;

  const formatted = new Intl.NumberFormat(localeFor(currency), {
    style: withSymbol ? 'currency' : 'decimal',
    currency,
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(abs / MINOR_PER_MAJOR);

  if (signed && minor !== 0) return `${minor > 0 ? '+' : '−'}${formatted}`;
  if (minor < 0) return `−${formatted}`;
  return formatted;
}

/** The bare symbol for a currency, for use in input prefixes. */
export function currencySymbol(currency = 'INR'): string {
  const parts = new Intl.NumberFormat(localeFor(currency), {
    style: 'currency',
    currency,
  }).formatToParts(0);
  return parts.find((p) => p.type === 'currency')?.value ?? currency;
}

/**
 * The one place that decides what a net balance *means* (context.md §8).
 * Positive net = they owe the user. Negative = the user owes them.
 */
export type BalanceTone = 'receivable' | 'payable' | 'settled';

export function balanceTone(netMinor: number): BalanceTone {
  if (netMinor > 0) return 'receivable';
  if (netMinor < 0) return 'payable';
  return 'settled';
}

export function balanceLabel(netMinor: number): string {
  switch (balanceTone(netMinor)) {
    case 'receivable':
      return 'You will receive';
    case 'payable':
      return 'You will pay';
    default:
      return 'Settled up';
  }
}

/** Short label for a person row, e.g. "₹12,500 receivable". */
export function netSummary(netMinor: number, currency = 'INR'): string {
  const tone = balanceTone(netMinor);
  if (tone === 'settled') return 'Settled up';
  return `${formatMinor(Math.abs(netMinor), currency)} ${tone}`;
}
