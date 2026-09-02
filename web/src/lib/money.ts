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
 *
 * How many minor units make a major one is a property of the currency, not a
 * constant: the yen has none and the Gulf dinars have three. Every function
 * here takes the currency for that reason (upgrade §19).
 */

import { decimalsFor, displaySymbol, minorPerMajor, normaliseCode } from '@/lib/currencies';

/**
 * Minor units per major unit for a two-decimal currency.
 *
 * Kept because most of this product is denominated in one and a literal reads
 * better than a lookup in those places. Anything handling a *named* currency
 * must ask minorPerMajor(code) instead.
 */
export const MINOR_PER_MAJOR = 100;

/**
 * The locale each currency's figures are GROUPED by — never the locale its
 * digits are drawn in.
 *
 * Grouping is a property of the money: ₹1,00,000 groups the Indian way and
 * $100,000 the Western one, and a ledger that got that wrong would read as a
 * different amount. Digits are not: `١٬٢٣٤` is the correct Arabic rendering of
 * 1,234 and completely unreadable in a column beside `1,234`. So every locale
 * here is one that draws Latin digits, chosen to match the grouping its
 * currency actually uses — the Gulf currencies group in threes, the South Asian
 * ones in the Indian pattern. The Dart mirror uses the same table.
 */
const CURRENCY_LOCALE: Record<string, string> = {
  INR: 'en-IN',
  USD: 'en-US',
  EUR: 'de-DE',
  GBP: 'en-GB',
  AED: 'en-US',
  AUD: 'en-AU',
  CAD: 'en-CA',
  SGD: 'en-SG',
  JPY: 'ja-JP',
  CNY: 'zh-CN',
  CHF: 'de-CH',
  SAR: 'en-US',
  QAR: 'en-US',
  KWD: 'en-US',
  BHD: 'en-US',
  OMR: 'en-US',
  JOD: 'en-US',
  PKR: 'en-PK',
  BDT: 'en-IN',
  LKR: 'en-IN',
  NPR: 'en-IN',
  MYR: 'ms-MY',
  THB: 'th-TH',
  IDR: 'id-ID',
  PHP: 'en-PH',
  VND: 'vi-VN',
  KRW: 'ko-KR',
  ZAR: 'en-ZA',
  NGN: 'en-NG',
  KES: 'en-KE',
  EGP: 'en-US',
  TRY: 'tr-TR',
  RUB: 'ru-RU',
  BRL: 'pt-BR',
  MXN: 'es-MX',
  SEK: 'sv-SE',
  NOK: 'nb-NO',
  DKK: 'da-DK',
  PLN: 'pl-PL',
  CZK: 'cs-CZ',
  HUF: 'hu-HU',
  RON: 'ro-RO',
  ILS: 'he-IL',
  TWD: 'zh-TW',
  HKD: 'zh-HK',
  NZD: 'en-NZ',
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
 * Accepts "1,234.5", "₹1234", " 1 234.56 ". Rejects more decimal places than the
 * currency actually has, rather than silently rounding away the user's money —
 * which for the yen means rejecting a decimal point at all. Returns null when
 * the input is not a usable amount.
 */
export function parseAmountToMinor(input: string, currency = 'INR'): number | null {
  const decimals = decimalsFor(currency);
  const units = minorPerMajor(currency);

  const cleaned = input
    .replace(/[\s  ,]/g, '')
    .replace(/[^\d.\-]/g, '');

  if (cleaned === '' || cleaned === '-' || cleaned === '.') return null;
  if ((cleaned.match(/\./g)?.length ?? 0) > 1) return null;

  const negative = cleaned.startsWith('-');
  const unsigned = negative ? cleaned.slice(1) : cleaned;
  if (!/^\d*(\.\d*)?$/.test(unsigned)) return null;

  const [whole = '', fraction = ''] = unsigned.split('.');
  if (fraction.length > decimals) return null;
  if (whole === '' && fraction === '') return null;

  const paddedFraction = decimals === 0 ? '' : fraction.padEnd(decimals, '0');
  const minor = Number(whole || '0') * units + Number(paddedFraction || '0');
  if (!Number.isSafeInteger(minor)) return null;

  return negative ? -minor : minor;
}

/** Minor units → a plain editable string, e.g. 1050050 → "10500.50". */
export function minorToInput(minor: number, currency = 'INR'): string {
  assertSafeMinor(minor);
  const units = minorPerMajor(currency);
  const decimals = decimalsFor(currency);
  const negative = minor < 0;
  const abs = Math.abs(minor);
  const whole = Math.trunc(abs / units);
  const fraction = abs % units;
  const body =
    fraction === 0 ? String(whole) : `${whole}.${String(fraction).padStart(decimals, '0')}`;
  return negative ? `-${body}` : body;
}

export interface FormatOptions {
  /** Drop the fraction on whole amounts. Default true — the dashboard reads better. */
  compactDecimals?: boolean;
  /** Render the currency symbol. Default true. */
  withSymbol?: boolean;
  /** Always show a leading + or −. Default false. */
  signed?: boolean;
  /** Append the ISO code, e.g. "AED 41.60 AED". Off by default; see MoneyExact. */
  withCode?: boolean;
  /**
   * The workspace's own currency, when the caller knows it (upgrade §45).
   *
   * An amount already written in the workspace currency does not need its code
   * repeated: in an INR workspace `₹2,537.50 INR` says "rupees" twice, once in
   * the glyph and once in the suffix, and that redundancy is printed on every
   * row of every screen. Passing `base` drops the suffix for that one currency
   * and keeps it for every other, so `500 AED` in the same list still names
   * itself and the contrast between the two is what tells the reader which
   * figures are foreign.
   *
   * The suffix is dropped for presentation only. Exports — CSV, JSON and the
   * PDF statement — never pass `base`, because a document that leaves the app
   * has no workspace around it to supply the missing context.
   *
   * An explicit `withCode` still wins, in both directions.
   */
  base?: string | null;
}

/** Minor units → display string, e.g. 1050050 → "₹10,500.50". */
export function formatMinor(
  minor: number,
  currency = 'INR',
  options: FormatOptions = {},
): string {
  const {
    compactDecimals = true,
    withSymbol = true,
    signed = false,
    base = null,
  } = options;
  assertSafeMinor(minor);

  const code = currency.toUpperCase();
  // `base` only ever *removes* a suffix the caller asked for; it never adds one
  // the caller did not. An explicit withCode wins over both.
  const withCode =
    options.withCode ?? (base ? code !== normaliseCode(base) : false);
  const units = minorPerMajor(code);
  const maxDecimals = decimalsFor(code);
  const abs = Math.abs(minor);
  const hasFraction = abs % units !== 0;
  const digits = compactDecimals && !hasFraction ? 0 : maxDecimals;

  // Decimal formatting plus our own symbol, never Intl's currency style. Intl
  // renders the same currency differently in different locales — and for the
  // right-to-left marks it renders something that cannot sit in a column of
  // figures at all. Grouping still comes from the currency's locale, which is
  // what makes ₹1,00,000 group the Indian way.
  const formatted = new Intl.NumberFormat(localeFor(code), {
    style: 'decimal',
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(abs / units);

  const symbol = withSymbol ? displaySymbol(code) : '';
  const amount = `${symbol}${formatted}`;
  const body = withCode ? `${amount} ${code}` : amount;

  if (signed && minor !== 0) return `${minor > 0 ? '+' : '−'}${body}`;
  if (minor < 0) return `−${body}`;
  return body;
}

/**
 * THE way an amount is written in this product (upgrade §44).
 *
 * One shared presenter, used by every screen on both clients, so that a figure
 * cannot be typed one way on the dashboard and another on a person page:
 *
 *     original amount     $40 USD          strongest
 *     converted amount    ≈ ₹3,817.11 INR  secondary
 *     rate                1 USD = ₹95.4276 INR   tertiary  (rateSentence)
 *
 * The ISO code is always present, because a symbol on its own is ambiguous —
 * `$` is eight currencies and `₹` is two — and because the whole point of the
 * hierarchy is that the reader can tell at a glance which of the two figures
 * they are looking at. `approx` prepends the `≈` that marks a converted figure
 * as a conversion rather than as something that was counted.
 *
 * Unknown, empty and unsupported codes fall through to two decimals and the
 * code as typed, rather than throwing: a ledger that will not render is worse
 * than one that renders a currency it has never heard of.
 */
export function formatMoney(
  minor: number,
  currency: string | null | undefined,
  options: FormatOptions & { approx?: boolean } = {},
): string {
  const { approx = false, ...rest } = options;
  const code = normaliseCode(currency) || 'INR';
  // The code rides along by default — this presenter exists so a mixed-currency
  // ledger names every figure. `base` is the one thing that can take it off,
  // and only for the workspace's own currency.
  const withCode = rest.withCode ?? (rest.base ? code !== normaliseCode(rest.base) : true);
  const body = formatMinor(minor, code, { ...rest, withCode });
  return approx ? `≈ ${body}` : body;
}

/**
 * `≈ ₹3,817.11` — the base-currency equivalent of an original amount.
 *
 * A conversion is always *into* the workspace currency, so the currency being
 * converted to is the one currency the reader never has to be told. The `≈`
 * carries the meaning; the code would only repeat the glyph. Pass `withCode`
 * to force it back for a document that will be read outside the app.
 */
export function formatApprox(
  minor: number,
  currency: string | null | undefined,
  options: { withCode?: boolean } = {},
): string {
  const code = normaliseCode(currency) || 'INR';
  return formatMoney(minor, code, {
    approx: true,
    compactDecimals: false,
    withCode: options.withCode ?? false,
  });
}

/**
 * The bare symbol for a currency, for use in input prefixes.
 *
 * Falls back to the ISO code for every currency whose mark cannot lead a
 * figure — the same rule the formatter uses, so the prefix inside an amount
 * field and the figure it produces agree.
 */
export function currencySymbol(currency = 'INR'): string {
  return displaySymbol(currency) || normaliseCode(currency);
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
