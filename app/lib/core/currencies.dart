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

/// "1 AED = ₹24.01" — the line that stops a conversion being a mystery.
String rateSentence(String from, String to, int rateE9) {
  final rate = rateFromE9(rateE9);
  final decimals = rate >= 100
      ? 2
      : rate >= 1
          ? 4
          : 6;
  final value = rate.toStringAsFixed(decimals);
  final trimmed = value.contains('.')
      ? value.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : value;
  return '1 ${normaliseCode(from)} = ${currencyOf(to)?.symbol ?? ''}$trimmed ${normaliseCode(to)}';
}
