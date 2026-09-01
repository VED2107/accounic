/**
 * The currency list, web side (upgrade §19).
 *
 * GENERATED between the markers from shared/currencies.json by
 * `node db/tools/sync-currencies.mjs`. Edit the JSON, not this file.
 * `currencies.test.ts` fails if the two drift, and the same list is seeded into
 * public.currencies and mirrored in app/lib/core/currencies.dart.
 *
 * `decimals` is the ISO 4217 minor-unit exponent, and it is what an integer
 * amount means: ¥1,000 is 1000 minor units, ₹1,000 is 100000. Nothing in the
 * money path may assume 100.
 */

export interface Currency {
  code: string;
  name: string;
  symbol: string;
  decimals: number;
}

export const CURRENCIES: readonly Currency[] = [
// @@CURRENCY_LIST_START@@
  { code: 'INR', name: 'Indian Rupee', symbol: '₹', decimals: 2 },
  { code: 'AED', name: 'UAE Dirham', symbol: 'د.إ', decimals: 2 },
  { code: 'USD', name: 'US Dollar', symbol: '$', decimals: 2 },
  { code: 'EUR', name: 'Euro', symbol: '€', decimals: 2 },
  { code: 'GBP', name: 'British Pound', symbol: '£', decimals: 2 },
  { code: 'JPY', name: 'Japanese Yen', symbol: '¥', decimals: 0 },
  { code: 'AUD', name: 'Australian Dollar', symbol: 'A$', decimals: 2 },
  { code: 'CAD', name: 'Canadian Dollar', symbol: 'C$', decimals: 2 },
  { code: 'SGD', name: 'Singapore Dollar', symbol: 'S$', decimals: 2 },
  { code: 'CHF', name: 'Swiss Franc', symbol: 'CHF', decimals: 2 },
  { code: 'CNY', name: 'Chinese Yuan', symbol: '¥', decimals: 2 },
  { code: 'HKD', name: 'Hong Kong Dollar', symbol: 'HK$', decimals: 2 },
  { code: 'NZD', name: 'New Zealand Dollar', symbol: 'NZ$', decimals: 2 },
  { code: 'SAR', name: 'Saudi Riyal', symbol: '﷼', decimals: 2 },
  { code: 'QAR', name: 'Qatari Riyal', symbol: '﷼', decimals: 2 },
  { code: 'KWD', name: 'Kuwaiti Dinar', symbol: 'د.ك', decimals: 3 },
  { code: 'BHD', name: 'Bahraini Dinar', symbol: '.د.ب', decimals: 3 },
  { code: 'OMR', name: 'Omani Rial', symbol: '﷼', decimals: 3 },
  { code: 'JOD', name: 'Jordanian Dinar', symbol: 'د.ا', decimals: 3 },
  { code: 'LKR', name: 'Sri Lankan Rupee', symbol: 'Rs', decimals: 2 },
  { code: 'NPR', name: 'Nepalese Rupee', symbol: 'रू', decimals: 2 },
  { code: 'PKR', name: 'Pakistani Rupee', symbol: '₨', decimals: 2 },
  { code: 'BDT', name: 'Bangladeshi Taka', symbol: '৳', decimals: 2 },
  { code: 'MYR', name: 'Malaysian Ringgit', symbol: 'RM', decimals: 2 },
  { code: 'THB', name: 'Thai Baht', symbol: '฿', decimals: 2 },
  { code: 'IDR', name: 'Indonesian Rupiah', symbol: 'Rp', decimals: 2 },
  { code: 'PHP', name: 'Philippine Peso', symbol: '₱', decimals: 2 },
  { code: 'VND', name: 'Vietnamese Dong', symbol: '₫', decimals: 0 },
  { code: 'KRW', name: 'South Korean Won', symbol: '₩', decimals: 0 },
  { code: 'ZAR', name: 'South African Rand', symbol: 'R', decimals: 2 },
  { code: 'NGN', name: 'Nigerian Naira', symbol: '₦', decimals: 2 },
  { code: 'KES', name: 'Kenyan Shilling', symbol: 'KSh', decimals: 2 },
  { code: 'EGP', name: 'Egyptian Pound', symbol: 'E£', decimals: 2 },
  { code: 'TRY', name: 'Turkish Lira', symbol: '₺', decimals: 2 },
  { code: 'RUB', name: 'Russian Ruble', symbol: '₽', decimals: 2 },
  { code: 'BRL', name: 'Brazilian Real', symbol: 'R$', decimals: 2 },
  { code: 'MXN', name: 'Mexican Peso', symbol: 'Mex$', decimals: 2 },
  { code: 'SEK', name: 'Swedish Krona', symbol: 'kr', decimals: 2 },
  { code: 'NOK', name: 'Norwegian Krone', symbol: 'kr', decimals: 2 },
  { code: 'DKK', name: 'Danish Krone', symbol: 'kr', decimals: 2 },
  { code: 'PLN', name: 'Polish Zloty', symbol: 'zł', decimals: 2 },
  { code: 'CZK', name: 'Czech Koruna', symbol: 'Kč', decimals: 2 },
  { code: 'HUF', name: 'Hungarian Forint', symbol: 'Ft', decimals: 2 },
  { code: 'RON', name: 'Romanian Leu', symbol: 'lei', decimals: 2 },
  { code: 'ILS', name: 'Israeli Shekel', symbol: '₪', decimals: 2 },
  { code: 'TWD', name: 'New Taiwan Dollar', symbol: 'NT$', decimals: 2 },
// @@CURRENCY_LIST_END@@
];

const BY_CODE = new Map(CURRENCIES.map((c) => [c.code, c]));

/** The default when a person or profile has not named one. */
export const FALLBACK_CURRENCY = 'INR';

export function normaliseCode(code: string | null | undefined): string {
  return (code ?? '').trim().toUpperCase();
}

export function currencyOf(code: string | null | undefined): Currency | undefined {
  return BY_CODE.get(normaliseCode(code));
}

export function isSupportedCurrency(code: string | null | undefined): boolean {
  return BY_CODE.has(normaliseCode(code));
}

/** Minor units per major unit for this currency: 100 for most, 1 for JPY. */
export function minorPerMajor(code: string | null | undefined): number {
  return 10 ** decimalsFor(code);
}

export function decimalsFor(code: string | null | undefined): number {
  return currencyOf(code)?.decimals ?? 2;
}

export function currencyName(code: string | null | undefined): string {
  return currencyOf(code)?.name ?? normaliseCode(code);
}

/**
 * The symbol, but only when printing it in front of a figure helps.
 *
 * `₹1,000`, `$40`, `฿50` and `zł50` read as money at a glance. `د.إ400` does
 * not: the mark is right-to-left, so it fights the digits beside it, and the
 * same is true of every non-Latin script in this list. Those currencies are
 * written `400 AED` — the ISO code alone, which every reader of a ledger knows.
 *
 * The test is a rune range rather than a script property so that the Dart
 * mirror in app/lib/core/currencies.dart can be character-for-character the
 * same rule. Latin and the Currency Symbols block lead a figure; everything
 * else falls back to the code.
 *
 * Returns '' when there is no usable symbol. One rule, in one place, so no
 * screen invents its own.
 */
export function symbolLeadsFigure(symbol: string): boolean {
  if (symbol === '' || symbol.length > 4) return false;
  for (const rune of symbol) {
    const code = rune.codePointAt(0)!;
    const usable =
      (code >= 0x20 && code <= 0x7e) || // ASCII: $, Rs, kr, A$
      (code >= 0x80 && code <= 0x24f) || // Latin-1 and Latin Extended: zł, Kč
      (code >= 0x20a0 && code <= 0x20bf) || // Currency Symbols: ₹ € ₩ ₺ ₫ ₪ ₨
      code === 0x0e3f; // ฿, the one baht sign outside that block
    if (!usable) return false;
  }
  return true;
}

export function displaySymbol(code: string | null | undefined): string {
  const symbol = currencyOf(code)?.symbol ?? '';
  return symbolLeadsFigure(symbol) ? symbol : '';
}

/** "INR — Indian Rupee (₹)", the label used in every currency picker. */
export function currencyLabel(code: string | null | undefined): string {
  const currency = currencyOf(code);
  if (!currency) return normaliseCode(code);
  return `${currency.code} — ${currency.name} (${currency.symbol})`;
}

/* --------------------------------------------------------------------------
 * Rates
 *
 * A rate is carried as an integer scaled by 1e9 — `rate_e9` — everywhere it
 * crosses a boundary, exactly as the database stores it. One unit of `from`
 * costs rate_e9/1e9 units of `to`.
 * ----------------------------------------------------------------------- */

export const RATE_SCALE = 1_000_000_000;

export function rateToE9(rate: number): number {
  return Math.round(rate * RATE_SCALE);
}

export function rateFromE9(rateE9: number): number {
  return rateE9 / RATE_SCALE;
}

/**
 * The band a rate has to fall in to be arithmetic rather than nonsense.
 *
 * The lower bound is one unit of `rate_e9`: anything smaller has already
 * rounded to zero, and a zero rate does not convert an amount, it erases it.
 * The upper bound is one unit of a currency being worth a million of another —
 * far outside any real pair, and comfortably inside the safe-integer range once
 * multiplied by an amount.
 */
export const MIN_RATE_E9 = 1;
export const MAX_RATE_E9 = 1_000_000 * RATE_SCALE;

/**
 * True when `rate_e9` can be used — and, just as importantly, inverted.
 *
 * A provider that answers with 0, a negative number, NaN or an absurd figure is
 * a provider that is broken, not a provider that is offering a bad deal. The
 * only safe response is to treat the pair as unavailable and say so, because
 * every alternative silently changes the money: a zero rate converts every
 * amount to nothing, and inverting one divides by zero (context.md §7).
 */
export function isUsableRateE9(rateE9: unknown): rateE9 is number {
  return (
    typeof rateE9 === 'number' &&
    Number.isFinite(rateE9) &&
    rateE9 >= MIN_RATE_E9 &&
    rateE9 <= MAX_RATE_E9
  );
}

/** A provider's decimal rate as `rate_e9`, or null when it is unusable. */
export function usableRateToE9(rate: unknown): number | null {
  if (typeof rate !== 'number' || !Number.isFinite(rate)) return null;
  const e9 = rateToE9(rate);
  return isUsableRateE9(e9) ? e9 : null;
}

/** The reciprocal of a stored rate, or null when it cannot be taken safely. */
export function invertRateE9(rateE9: number): number | null {
  if (!isUsableRateE9(rateE9)) return null;
  const inverted = Math.round((RATE_SCALE * RATE_SCALE) / rateE9);
  return isUsableRateE9(inverted) ? inverted : null;
}

/**
 * Parse a rate a user typed — "95.4276", " 1,234.5 " — into `rate_e9`.
 *
 * Read the same way the rate sentence states it: one unit of the original
 * currency costs this many of the base one. Up to nine decimals, which is
 * exactly what the column stores; a tenth would be silently discarded, so it is
 * refused instead. Zero, negative and unparseable input return null.
 *
 * A rate typed here is stored on the entry like any other rate, and the
 * database derives the converted amount from it. The client never sends a
 * converted figure it worked out from a rate itself (context.md §7).
 */
export function parseRateToE9(input: string): number | null {
  const cleaned = (input ?? '').replace(/[\s  ,]/g, '');
  if (cleaned === '') return null;
  if (!/^\d*(\.\d*)?$/.test(cleaned)) return null;

  const [whole = '', fraction = ''] = cleaned.split('.');
  if (whole === '' && fraction === '') return null;
  if (fraction.length > 9) return null;

  const e9 = Number(whole || '0') * RATE_SCALE + Number((fraction || '').padEnd(9, '0') || '0');
  if (!Number.isSafeInteger(e9) || e9 <= 0) return null;
  return e9;
}

/** `rate_e9` → a plain editable string, e.g. 95427612000 → "95.427612". */
export function rateToInput(rateE9: number): string {
  const whole = Math.trunc(rateE9 / RATE_SCALE);
  const fraction = String(rateE9 % RATE_SCALE).padStart(9, '0').replace(/0+$/, '');
  return fraction === '' ? String(whole) : `${whole}.${fraction}`;
}

/**
 * Convert an integer minor amount between currencies.
 *
 * Mirrors public.convert_amount_minor() exactly — including the decimal-exponent
 * shift, which is the part that goes wrong when a yen meets a rupee. This is a
 * preview for the user; the value that is stored is always the one the database
 * computed from the same inputs.
 */
export function convertMinor(
  amountMinor: number,
  from: string,
  to: string,
  rateE9: number | null | undefined,
): number | null {
  const fromCode = normaliseCode(from);
  const toCode = normaliseCode(to);
  if (!Number.isFinite(amountMinor)) return null;
  if (fromCode === toCode) return amountMinor;
  if (!rateE9 || rateE9 <= 0) return null;

  const scale = 10 ** (decimalsFor(toCode) - decimalsFor(fromCode));
  return Math.round((amountMinor * scale * rateE9) / RATE_SCALE);
}

/**
 * How many decimals to print a rate at.
 *
 * The rate is the one number on screen that is NEVER used to compute anything:
 * every conversion in this product runs on the full 1e9-scaled integer. A
 * shortened rate is therefore only a readability choice — but a shortened rate
 * that cannot reproduce the converted amount printed beside it is a readability
 * choice that makes the screen look wrong.
 *
 *     400 AED at 1 AED = ₹25.984225 INR is ₹10,393.69
 *     but 400 × 25.9842 (4 dp) is ₹10,393.68
 *
 * So when the amount being converted is known, the precision grows — from the
 * readable default up to the nine digits the rate is actually stored at — until
 * re-converting at the printed rate lands on the printed amount. Nothing about
 * the calculation changes; only how much of the rate is shown.
 */
export function rateDecimals(
  from: string,
  to: string,
  rateE9: number,
  amountMinor?: number | null,
): number {
  const rate = rateFromE9(rateE9);
  const base = rate >= 100 ? 2 : rate >= 1 ? 4 : 6;

  if (amountMinor == null || !Number.isFinite(amountMinor) || amountMinor === 0) return base;

  const exact = convertMinor(amountMinor, from, to, rateE9);
  if (exact === null) return base;

  for (let decimals = base; decimals <= RATE_DECIMALS; decimals += 1) {
    if (convertMinor(amountMinor, from, to, roundRateE9(rateE9, decimals)) === exact) {
      return decimals;
    }
  }
  return RATE_DECIMALS;
}

/** The decimal places `rate_e9` is stored at. */
const RATE_DECIMALS = 9;

/**
 * The rate as it would be if it really had only `decimals` digits.
 *
 * Integer arithmetic on the scaled rate, never a float round-trip: this value
 * has to be *exactly* the one rateText() prints, or the precision search
 * validates one number and the screen shows another that is one ulp away and
 * does not reconcile. That is how `1 AED = ₹25.98421` came to sit under
 * `₹10,393.69` when 400 × 25.98421 is ₹10,393.68.
 */
function roundRateE9(rateE9: number, decimals: number): number {
  const divisor = 10 ** (RATE_DECIMALS - decimals);
  return Math.round(rateE9 / divisor) * divisor;
}

/**
 * `rate_e9` written out at exactly this many decimals — from the integer, so
 * what is printed is the same number the search above tested.
 *
 * Trailing zeros go, down to a floor of two: `24.0100` is noise, and `26` reads
 * as a guess where `26.00` reads as a rate.
 */
export function rateText(rateE9: number, decimals: number): string {
  const shown = Math.min(Math.max(decimals, 2), RATE_DECIMALS);
  const scaled = Math.round(rateE9 / 10 ** (RATE_DECIMALS - shown));
  const unit = 10 ** shown;
  const whole = Math.floor(scaled / unit);
  let fraction = String(scaled - whole * unit).padStart(shown, '0');
  while (fraction.length > 2 && fraction.endsWith('0')) fraction = fraction.slice(0, -1);
  return `${whole.toLocaleString('en-US')}.${fraction}`;
}

/**
 * "1 AED = ₹25.98422 INR" — the line that stops a conversion being a mystery.
 *
 * Tertiary information by construction: one unit of the original currency, the
 * base-currency symbol and figure, and the code. Pass the amount being
 * converted and the precision is chosen so the sentence agrees with the
 * converted amount shown above it (see rateDecimals).
 */
export function rateSentence(
  from: string,
  to: string,
  rateE9: number,
  amountMinor?: number | null,
): string {
  const decimals = rateDecimals(from, to, rateE9, amountMinor);
  const value = rateText(rateE9, decimals);
  return `1 ${normaliseCode(from)} = ${displaySymbol(to)}${value} ${normaliseCode(to)}`;
}

/**
 * The two currencies a person has, resolved (db/migrations/0013).
 *
 * `ledger` is what their stored figures are denominated in; `entry` is what a
 * new transaction with them should be typed in. They are the same string for
 * everyone who has never changed currency, which is almost everyone — the pair
 * exists so that the one case where they differ cannot be silently collapsed
 * into whichever of the two the calling screen happened to have.
 *
 * The fallback chain is the database's, to the letter:
 *
 *     entry  = person.currency        ?? base
 *     ledger = person.ledger_currency ?? person.currency ?? base
 *
 * A NULL `currency` is a reference to the account's base currency and not a
 * snapshot of it, so a person who has never named one follows the workspace
 * when the workspace changes.
 */
export function personCurrencies(
  person: { currency?: string | null; ledger_currency?: string | null } | null | undefined,
  baseCurrency: string | null | undefined,
): { entry: string; ledger: string } {
  const base = normaliseCode(baseCurrency) || FALLBACK_CURRENCY;
  const entry = normaliseCode(person?.currency) || base;
  const ledger = normaliseCode(person?.ledger_currency) || entry;
  return { entry, ledger };
}
