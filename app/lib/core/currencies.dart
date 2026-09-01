/// The currency list, Dart side (upgrade §19).
///
/// GENERATED between the markers from shared/currencies.json by
/// `node db/tools/sync-currencies.mjs`. Edit the JSON, not this file.
/// `test/currencies_test.dart` fails if the two drift, and the same list is
/// seeded into public.currencies and mirrored in web/src/lib/currencies.ts.
///
/// `decimals` is the ISO 4217 minor-unit exponent, and it is what an integer
/// amount means: ¥1,000 is 1000 minor units, ₹1,000 is 100000. Nothing in the
/// money path may assume 100.
library;

class Currency {
  const Currency(this.code, this.name, this.symbol, this.decimals);

  final String code;
  final String name;
  final String symbol;
  final int decimals;

  /// "INR — Indian Rupee (₹)", the label used in every currency picker.
  String get label => '$code — $name ($symbol)';
}

const List<Currency> kCurrencies = [
// @@CURRENCY_LIST_START@@
  Currency('INR', 'Indian Rupee', '₹', 2),
  Currency('AED', 'UAE Dirham', 'د.إ', 2),
  Currency('USD', 'US Dollar', '\$', 2),
  Currency('EUR', 'Euro', '€', 2),
  Currency('GBP', 'British Pound', '£', 2),
  Currency('JPY', 'Japanese Yen', '¥', 0),
  Currency('AUD', 'Australian Dollar', 'A\$', 2),
  Currency('CAD', 'Canadian Dollar', 'C\$', 2),
  Currency('SGD', 'Singapore Dollar', 'S\$', 2),
  Currency('CHF', 'Swiss Franc', 'CHF', 2),
  Currency('CNY', 'Chinese Yuan', '¥', 2),
  Currency('HKD', 'Hong Kong Dollar', 'HK\$', 2),
  Currency('NZD', 'New Zealand Dollar', 'NZ\$', 2),
  Currency('SAR', 'Saudi Riyal', '﷼', 2),
  Currency('QAR', 'Qatari Riyal', '﷼', 2),
  Currency('KWD', 'Kuwaiti Dinar', 'د.ك', 3),
  Currency('BHD', 'Bahraini Dinar', '.د.ب', 3),
  Currency('OMR', 'Omani Rial', '﷼', 3),
  Currency('JOD', 'Jordanian Dinar', 'د.ا', 3),
  Currency('LKR', 'Sri Lankan Rupee', 'Rs', 2),
  Currency('NPR', 'Nepalese Rupee', 'रू', 2),
  Currency('PKR', 'Pakistani Rupee', '₨', 2),
  Currency('BDT', 'Bangladeshi Taka', '৳', 2),
  Currency('MYR', 'Malaysian Ringgit', 'RM', 2),
  Currency('THB', 'Thai Baht', '฿', 2),
  Currency('IDR', 'Indonesian Rupiah', 'Rp', 2),
  Currency('PHP', 'Philippine Peso', '₱', 2),
  Currency('VND', 'Vietnamese Dong', '₫', 0),
  Currency('KRW', 'South Korean Won', '₩', 0),
  Currency('ZAR', 'South African Rand', 'R', 2),
  Currency('NGN', 'Nigerian Naira', '₦', 2),
  Currency('KES', 'Kenyan Shilling', 'KSh', 2),
  Currency('EGP', 'Egyptian Pound', 'E£', 2),
  Currency('TRY', 'Turkish Lira', '₺', 2),
  Currency('RUB', 'Russian Ruble', '₽', 2),
  Currency('BRL', 'Brazilian Real', 'R\$', 2),
  Currency('MXN', 'Mexican Peso', 'Mex\$', 2),
  Currency('SEK', 'Swedish Krona', 'kr', 2),
  Currency('NOK', 'Norwegian Krone', 'kr', 2),
  Currency('DKK', 'Danish Krone', 'kr', 2),
  Currency('PLN', 'Polish Zloty', 'zł', 2),
  Currency('CZK', 'Czech Koruna', 'Kč', 2),
  Currency('HUF', 'Hungarian Forint', 'Ft', 2),
  Currency('RON', 'Romanian Leu', 'lei', 2),
  Currency('ILS', 'Israeli Shekel', '₪', 2),
  Currency('TWD', 'New Taiwan Dollar', 'NT\$', 2),
// @@CURRENCY_LIST_END@@
];

final Map<String, Currency> _byCode = {
  for (final currency in kCurrencies) currency.code: currency,
};

/// The default when a person or profile has not named one.
const String kFallbackCurrency = 'INR';

String normaliseCode(String? code) => (code ?? '').trim().toUpperCase();

Currency? currencyOf(String? code) => _byCode[normaliseCode(code)];

bool isSupportedCurrency(String? code) => _byCode.containsKey(normaliseCode(code));

int decimalsFor(String? code) => currencyOf(code)?.decimals ?? 2;

/// Minor units per major unit for this currency: 100 for most, 1 for JPY.
int minorPerMajorFor(String? code) {
  var units = 1;
  for (var i = 0; i < decimalsFor(code); i++) {
    units *= 10;
  }
  return units;
}

String currencyName(String? code) => currencyOf(code)?.name ?? normaliseCode(code);

String currencyLabel(String? code) => currencyOf(code)?.label ?? normaliseCode(code);

/* --------------------------------------------------------------------------
 * Rates
 *
 * A rate is carried as an integer scaled by 1e9 — `rateE9` — everywhere it
 * crosses a boundary, exactly as the database stores it. One unit of `from`
 * costs rateE9/1e9 units of `to`.
 * ----------------------------------------------------------------------- */

const int kRateScale = 1000000000;

int rateToE9(num rate) => (rate * kRateScale).round();

double rateFromE9(int rateE9) => rateE9 / kRateScale;

/// The band a rate has to fall in to be arithmetic rather than nonsense.
///
/// The lower bound is one unit of rateE9: anything smaller has already rounded
/// to zero, and a zero rate does not convert an amount, it erases it. The upper
/// bound is one unit of a currency being worth a million of another — far
/// outside any real pair.
const int kMinRateE9 = 1;
const int kMaxRateE9 = 1000000 * kRateScale;

/// True when a rate can be used — and, just as importantly, inverted.
///
/// A provider that answers with 0, a negative number, NaN or an absurd figure
/// is a provider that is broken, not one offering a bad deal. The only safe
/// response is to treat the pair as unavailable and say so: a zero rate
/// converts every amount to nothing, and inverting one divides by zero
/// (context.md §7).
bool isUsableRateE9(int? rateE9) =>
    rateE9 != null && rateE9 >= kMinRateE9 && rateE9 <= kMaxRateE9;

/// A provider's decimal rate as rateE9, or null when it is unusable.
int? usableRateToE9(num? rate) {
  if (rate == null || rate.isNaN || rate.isInfinite) return null;
  final e9 = rateToE9(rate);
  return isUsableRateE9(e9) ? e9 : null;
}

/// The reciprocal of a stored rate, or null when it cannot be taken safely.
int? invertRateE9(int rateE9) {
  if (!isUsableRateE9(rateE9)) return null;
  final inverted = (kRateScale * kRateScale / rateE9).round();
  return isUsableRateE9(inverted) ? inverted : null;
}

/// Convert an integer minor amount between currencies.
///
/// Mirrors public.convert_amount_minor() exactly — including the
/// decimal-exponent shift, which is the part that goes wrong when a yen meets a
/// rupee. This is a preview for the user; the value that is stored is always the
/// one the database computed from the same inputs.
int? convertMinor(int amountMinor, String from, String to, int? rateE9) {
  final fromCode = normaliseCode(from);
  final toCode = normaliseCode(to);
  if (fromCode == toCode) return amountMinor;
  if (rateE9 == null || rateE9 <= 0) return null;

  final shift = decimalsFor(toCode) - decimalsFor(fromCode);
  var scaled = amountMinor * rateE9 / kRateScale;
  for (var i = 0; i < shift.abs(); i++) {
    scaled = shift > 0 ? scaled * 10 : scaled / 10;
  }
  return scaled.round();
}

/// The symbol, but only when printing it in front of a figure helps.
///
/// `₹1,000`, `$40`, `฿50` and `zł50` read as money at a glance. `د.إ400` does
/// not: the mark is right-to-left, so it fights the digits beside it, and the
/// same is true of every non-Latin script in this list. Those currencies are
/// written `400 AED` — the ISO code alone, which every reader of a ledger knows.
///
/// Character-for-character the same rule as symbolLeadsFigure() in
/// web/src/lib/currencies.ts, so the two clients cannot render the same
/// currency differently.
bool symbolLeadsFigure(String symbol) {
  if (symbol.isEmpty || symbol.length > 4) return false;
  for (final rune in symbol.runes) {
    final usable = (rune >= 0x20 && rune <= 0x7e) ||
        (rune >= 0x80 && rune <= 0x24f) ||
        (rune >= 0x20a0 && rune <= 0x20bf) ||
        rune == 0x0e3f;
    if (!usable) return false;
  }
  return true;
}

/// The symbol to print in front of a figure, or '' to fall back to the code.
String displaySymbol(String? code) {
  final symbol = currencyOf(code)?.symbol ?? '';
  return symbolLeadsFigure(symbol) ? symbol : '';
}

/// How many decimals to print a rate at.
///
/// The rate is the one number on screen that is NEVER used to compute anything:
/// every conversion in this product runs on the full 1e9-scaled integer. A
/// shortened rate is therefore only a readability choice — but a shortened rate
/// that cannot reproduce the converted amount printed beside it is a
/// readability choice that makes the screen look wrong.
///
///     400 AED at 1 AED = ₹25.984225 INR is ₹10,393.69
///     but 400 × 25.9842 (4 dp) is ₹10,393.68
///
/// So when the amount being converted is known, the precision grows — from the
/// readable default up to the nine digits the rate is actually stored at —
/// until re-converting at the printed rate lands on the printed amount.
int rateDecimals(String from, String to, int rateE9, {int? amountMinor}) {
  final rate = rateFromE9(rateE9);
  final base = rate >= 100
      ? 2
      : rate >= 1
          ? 4
          : 6;

  if (amountMinor == null || amountMinor == 0) return base;

  final exact = convertMinor(amountMinor, from, to, rateE9);
  if (exact == null) return base;

  for (var decimals = base; decimals <= kRateDecimals; decimals++) {
    if (convertMinor(amountMinor, from, to, _roundRateE9(rateE9, decimals)) == exact) {
      return decimals;
    }
  }
  return kRateDecimals;
}

/// The decimal places `rateE9` is stored at.
const int kRateDecimals = 9;

/// The rate as it would be if it really had only [decimals] digits.
///
/// Integer arithmetic on the scaled rate, never a float round-trip: this value
/// has to be *exactly* the one [rateText] prints, or the precision search
/// validates one number and the screen shows another that is one ulp away and
/// does not reconcile. That is how `1 AED = ₹25.98421` came to sit under
/// `₹10,393.69` when 400 × 25.98421 is ₹10,393.68.
int _roundRateE9(int rateE9, int decimals) {
  final divisor = _pow10(kRateDecimals - decimals);
  return (rateE9 / divisor).round() * divisor;
}

int _pow10(int exponent) {
  var value = 1;
  for (var i = 0; i < exponent; i++) {
    value *= 10;
  }
  return value;
}

/// `rateE9` written out at exactly this many decimals — from the integer, so
/// what is printed is the same number the search above tested.
///
/// Trailing zeros go, down to a floor of two: `24.0100` is noise, and `26`
/// reads as a guess where `26.00` reads as a rate.
String rateText(int rateE9, int decimals) {
  final shown = decimals.clamp(2, kRateDecimals);
  final scaled = (rateE9 / _pow10(kRateDecimals - shown)).round();
  final unit = _pow10(shown);
  final whole = scaled ~/ unit;
  var fraction = (scaled - whole * unit).toString().padLeft(shown, '0');
  while (fraction.length > 2 && fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }

  // Grouped the Western way, like the web client: a rate is not an amount and
  // never follows the currency's own grouping.
  final digits = whole.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }

  return '$buffer.$fraction';
}

/// "1 AED = ₹25.98422 INR" — the line that stops a conversion being a mystery.
///
/// Tertiary information by construction. Pass the amount being converted and
/// the precision is chosen so the sentence agrees with the converted amount
/// shown above it (see [rateDecimals]).
String rateSentence(String from, String to, int rateE9, {int? amountMinor}) {
  final decimals = rateDecimals(from, to, rateE9, amountMinor: amountMinor);
  final value = rateText(rateE9, decimals);
  return '1 ${normaliseCode(from)} = ${displaySymbol(to)}$value ${normaliseCode(to)}';
}

/// The provenance a hand-typed rate is stored under (upgrade §45).
///
/// One string, matching public.rate_is_manual() in db/migrations/0018 and
/// MANUAL_RATE_SOURCE in the web client. A row carrying it is a row where a
/// human decided the rate: it is stored in exchange_rate_e9 like any other
/// rate, frozen on the row like any other, and later automatic rates never
/// touch it.
const String kManualRateSource = 'manual-rate';

bool rateIsManual(String? source) =>
    (source ?? '').trim().toLowerCase() == kManualRateSource;

/// Parse a rate a user typed — "95.4276" — into `rateE9`.
///
/// Read the same way the rate sentence states it: one unit of the original
/// currency costs this many of the base one. Up to nine decimals, which is
/// exactly what the column stores; a tenth would be silently discarded, so it
/// is refused instead. Zero, negative and unparseable input return null.
int? parseRateToE9(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s  ,]'), '');
  if (cleaned.isEmpty) return null;
  if (!RegExp(r'^\d*(\.\d*)?$').hasMatch(cleaned)) return null;

  final parts = cleaned.split('.');
  final whole = parts[0];
  final fraction = parts.length > 1 ? parts[1] : '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  if (fraction.length > 9) return null;

  final padded = fraction.padRight(9, '0');
  final e9 = (int.tryParse(whole.isEmpty ? '0' : whole) ?? 0) * kRateScale +
      (int.tryParse(padded.isEmpty ? '0' : padded) ?? 0);
  return e9 <= 0 ? null : e9;
}

/// `rateE9` to a plain editable string, e.g. 95427612000 -> "95.427612".
String rateToInput(int rateE9) {
  final whole = rateE9 ~/ kRateScale;
  final fraction = (rateE9 % kRateScale)
      .toString()
      .padLeft(9, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}
