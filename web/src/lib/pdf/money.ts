import 'server-only';

import { formatApprox, formatMoney } from '@/lib/money';
import { rateSentence } from '@/lib/currencies';
import { supportsAll } from '@/lib/pdf/typeface';

/**
 * Money, as a PDF can print it (upgrade §47).
 *
 * This is NOT a second money formatter. Every figure below comes out of
 * `lib/money.ts` — the same `formatMoney` the person page, the dashboard and
 * the activity feed use, with the same grouping, the same decimals and the same
 * ISO code. A statement and the screen it was exported from print a number
 * identically, because they call the same function.
 *
 * The single thing added here is a fallback for the handful of currency symbols
 * the embedded typeface cannot draw (₪, ₫, ₩, ₦, ₱, ৳, ฿). Those fall back to
 * the ISO-code form — `1,500.00 VND` rather than `₫1,500.00 VND` — which is the
 * same string minus a glyph that would otherwise throw. Nothing about the amount
 * changes; only whether a symbol precedes it.
 */

/** `$40.00 USD`, or `40.00 USD` when the symbol has no glyph. */
export function pdfMoney(
  minor: number,
  currency: string | null | undefined,
  options: { compactDecimals?: boolean } = {},
): string {
  const withSymbol = formatMoney(minor, currency, options);
  return supportsAll(withSymbol)
    ? withSymbol
    : formatMoney(minor, currency, { ...options, withSymbol: false });
}

/**
 * `≈ ₹3,817.11 INR` — the converted figure, marked as a conversion.
 *
 * The screen drops this ISO code, because on screen the workspace currency is
 * stated all around the figure. A statement has no workspace around it — it is
 * read in an inbox, a folder, a printout — so the code stays here, explicitly.
 */
export function pdfApprox(minor: number, currency: string | null | undefined): string {
  const withSymbol = formatApprox(minor, currency, { withCode: true });
  return supportsAll(withSymbol)
    ? withSymbol
    : `≈ ${formatMoney(minor, currency, { withSymbol: false, compactDecimals: false })}`;
}

/**
 * `1 USD = ₹95.4276 INR` — the rate, at the precision that reproduces the
 * converted figure printed beside it.
 *
 * `rateSentence` chooses that precision (lib/currencies.ts). Passing the amount
 * through is what keeps a statement from showing a rate that does not multiply
 * out to the amount above it — the exact defect v1.5.0 was cut for.
 */
export function pdfRate(
  from: string,
  to: string,
  rateE9: number,
  amountMinor?: number | null,
): string {
  const sentence = rateSentence(from, to, rateE9, amountMinor);
  if (supportsAll(sentence)) return sentence;
  // Same sentence, symbol dropped. Rebuilt rather than regex-stripped so the
  // number itself is never touched.
  const bare = sentence.replace(/=\s*\S*?([\d.,])/, '= $1');
  return supportsAll(bare) ? bare : `1 ${from} = ${to}`;
}
