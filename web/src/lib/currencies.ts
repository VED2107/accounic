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

/** "1 AED = ₹24.01" — the line that stops a conversion being a mystery. */
export function rateSentence(from: string, to: string, rateE9: number): string {
  const rate = rateFromE9(rateE9);
  const toCurrency = currencyOf(to);
  const decimals = rate >= 100 ? 2 : rate >= 1 ? 4 : 6;
  const value = rate.toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: decimals,
  });
  return `1 ${normaliseCode(from)} = ${toCurrency?.symbol ?? ''}${value} ${normaliseCode(to)}`;
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
