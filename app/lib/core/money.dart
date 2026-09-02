library;

import 'package:intl/intl.dart';

import 'currencies.dart';

/// Money handling (context.md §7).
///
/// The Dart mirror of `web/src/lib/money.ts`. Both sides must agree exactly,
/// because the same integer minor units cross the wire to both — a rounding
/// difference here would show a user two different balances on two devices.
///
/// Dart's `int` is 64-bit on Android and Windows, so minor units never lose
/// precision. `double` is not used anywhere in the money path.
///
/// How many minor units make a major one is a property of the currency, not a
/// constant, so every function here takes the currency (upgrade §19).

/// Minor units per major unit for a two-decimal currency.
///
/// Kept because most of this product is denominated in one. Anything handling a
/// *named* currency asks [minorPerMajorFor] instead: the yen has no minor unit
/// and the Gulf dinars have three.
const int minorPerMajor = 100;

/// The locale each currency's figures are GROUPED by — never the locale its
/// digits are drawn in.
///
/// Grouping is a property of the money: ₹1,00,000 groups the Indian way and
/// $100,000 the Western one, and a ledger that got that wrong would read as a
/// different amount. Digits are not: `١٬٢٣٤` is the correct Arabic rendering of
/// 1,234 and completely unreadable in a column beside `1,234`. So every locale
/// here draws Latin digits, chosen to match the grouping its currency actually
/// uses. The same table as CURRENCY_LOCALE in web/src/lib/money.ts.
const Map<String, String> _currencyLocale = {
  'INR': 'en_IN',
  'USD': 'en_US',
  'EUR': 'de_DE',
  'GBP': 'en_GB',
  'AED': 'en_US',
  'AUD': 'en_AU',
  'CAD': 'en_CA',
  'SGD': 'en_SG',
  'JPY': 'ja_JP',
  'CNY': 'zh_CN',
  'CHF': 'de_CH',
  'SAR': 'en_US',
  'QAR': 'en_US',
  'KWD': 'en_US',
  'BHD': 'en_US',
  'OMR': 'en_US',
  'JOD': 'en_US',
  'PKR': 'en_PK',
  'BDT': 'en_IN',
  'LKR': 'en_IN',
  'NPR': 'en_IN',
  'MYR': 'ms_MY',
  'THB': 'th_TH',
  'IDR': 'id_ID',
  'PHP': 'en_PH',
  'VND': 'vi_VN',
  'KRW': 'ko_KR',
  'ZAR': 'en_ZA',
  'NGN': 'en_NG',
  'KES': 'en_KE',
  'EGP': 'en_US',
  'TRY': 'tr_TR',
  'RUB': 'ru_RU',
  'BRL': 'pt_BR',
  'MXN': 'es_MX',
  'SEK': 'sv_SE',
  'NOK': 'nb_NO',
  'DKK': 'da_DK',
  'PLN': 'pl_PL',
  'CZK': 'cs_CZ',
  'HUF': 'hu_HU',
  'RON': 'ro_RO',
  'ILS': 'he_IL',
  'TWD': 'zh_TW',
  'HKD': 'zh_HK',
  'NZD': 'en_NZ',
};

String localeFor(String currency) =>
    _currencyLocale[currency.toUpperCase()] ?? 'en_US';

/// Parses what the user typed into minor units.
///
/// Accepts `1,234.5`, `₹1234`, ` 1 234.56 `. Returns null for anything that is
/// not a usable amount, including more decimal places than the currency has —
/// silently rounding away a user's paise is not acceptable, and for the yen it
/// means refusing a decimal point at all.
int? parseAmountToMinor(String input, {String currency = kFallbackCurrency}) {
  final decimals = decimalsFor(currency);
  final units = minorPerMajorFor(currency);

  final cleaned = input
      .replaceAll(RegExp(r'[\s,  ]'), '')
      .replaceAll(RegExp(r'[^\d.\-]'), '');

  if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return null;
  if ('.'.allMatches(cleaned).length > 1) return null;

  final negative = cleaned.startsWith('-');
  final unsigned = negative ? cleaned.substring(1) : cleaned;
  if (!RegExp(r'^\d*(\.\d*)?$').hasMatch(unsigned)) return null;

  final parts = unsigned.split('.');
  final whole = parts[0];
  final fraction = parts.length > 1 ? parts[1] : '';
  if (fraction.length > decimals) return null;
  if (whole.isEmpty && fraction.isEmpty) return null;

  final padded = decimals == 0 ? '' : fraction.padRight(decimals, '0');
  final minor = (int.tryParse(whole.isEmpty ? '0' : whole) ?? 0) * units +
      (int.tryParse(padded.isEmpty ? '0' : padded) ?? 0);

  return negative ? -minor : minor;
}

/// Minor units to an editable string: 1050050 -> "10500.50".
String minorToInput(int minor, {String currency = kFallbackCurrency}) {
  final units = minorPerMajorFor(currency);
  final decimals = decimalsFor(currency);
  final negative = minor < 0;
  final abs = minor.abs();
  final whole = abs ~/ units;
  final fraction = abs % units;
  final body = fraction == 0
      ? '$whole'
      : '$whole.${fraction.toString().padLeft(decimals, '0')}';
  return negative ? '-$body' : body;
}

/// Minor units to a display string: 1050050 -> "₹10,500.50".
String formatMinor(
  int minor, {
  String currency = kFallbackCurrency,
  bool compactDecimals = true,
  bool withSymbol = true,
  bool signed = false,
  bool withCode = false,
}) {
  final code = normaliseCode(currency);
  final units = minorPerMajorFor(code);
  final abs = minor.abs();
  final hasFraction = abs % units != 0;
  final digits = compactDecimals && !hasFraction ? 0 : decimalsFor(code);

  // Decimal formatting plus our own symbol, never a locale's currency pattern:
  // a locale renders the same currency differently, and for the right-to-left
  // marks it renders something that cannot sit in a column of figures at all.
  // Grouping still comes from the currency's locale, which is what makes
  // ₹1,00,000 group the Indian way.
  final formatted = NumberFormat.decimalPatternDigits(
    locale: localeFor(code),
    decimalDigits: digits,
  ).format(abs / units);

  final symbol = withSymbol ? displaySymbol(code) : '';
  final amount = '$symbol$formatted';
  final text = withCode ? '$amount $code' : amount;

  if (signed && minor != 0) return '${minor > 0 ? '+' : '−'}$text';
  if (minor < 0) return '−$text';
  return text;
}

/// THE way an amount is written in this product (upgrade §44).
///
/// One shared presenter, mirroring formatMoney() in web/src/lib/money.ts, so
/// that a figure cannot be typed one way on the web and another in the app:
///
///     original amount     $40 USD                 strongest
///     converted amount    ≈ ₹3,817.11 INR         secondary
///     rate                1 USD = ₹95.4276 INR    tertiary (rateSentence)
///
/// The ISO code is always present, because a symbol on its own is ambiguous —
/// `$` is eight currencies in this list and `₹` is two — and because the point
/// of the hierarchy is that the reader can tell at a glance which of the two
/// figures they are looking at.
///
/// [base] is the one thing that takes the code off (upgrade §45). An amount
/// already written in the workspace currency does not need its code repeated:
/// in an INR workspace `₹2,537.50 INR` says "rupees" twice, once in the glyph
/// and once in the suffix, on every row of every screen. Passing [base] drops
/// the suffix for that one currency and keeps it for every other, so `500 AED`
/// in the same list still names itself — and the contrast between the two is
/// what tells the reader which figures are foreign.
///
/// Presentation only. Exports — CSV, JSON and the PDF statement — never pass
/// [base], because a document that leaves the app has no workspace around it to
/// supply the missing context. An explicit [withCode] wins over both.
///
/// Mirrors the `base` option in web/src/lib/money.ts so a figure cannot be
/// written one way on the web and another in the app.
String formatMoney(
  int minor, {
  String? currency,
  bool compactDecimals = true,
  bool signed = false,
  bool? withCode,
  String? base,
  bool approx = false,
}) {
  final code = normaliseCode(currency ?? kFallbackCurrency);
  final resolvedCode = code.isEmpty ? kFallbackCurrency : code;
  final showCode =
      withCode ?? (base != null ? resolvedCode != normaliseCode(base) : true);
  final body = formatMinor(
    minor,
    currency: resolvedCode,
    compactDecimals: compactDecimals,
    signed: signed,
    withCode: showCode,
  );
  return approx ? '≈ $body' : body;
}

/// `≈ ₹3,817.11` — the base-currency equivalent of an original amount.
///
/// A conversion is always *into* the workspace currency, so the currency being
/// converted to is the one the reader never has to be told: the `≈` carries the
/// meaning and the code would only repeat the glyph. Pass [withCode] to force
/// it back for a statement, which is read with no workspace around it.
String formatApprox(int minor, {String? currency, bool withCode = false}) =>
    formatMoney(
      minor,
      currency: currency,
      approx: true,
      compactDecimals: false,
      withCode: withCode,
    );

/// The symbol to lead a figure with, falling back to the ISO code for every
/// currency whose mark cannot — the same rule the formatter uses, so an amount
/// field's prefix and the figure it produces agree.
String currencySymbol(String currency) {
  final symbol = displaySymbol(currency);
  return symbol.isEmpty ? '${normaliseCode(currency)} ' : symbol;
}

/// What a net balance *means* (context.md §8). Positive: they owe the user.
enum BalanceTone { receivable, payable, settled }

BalanceTone balanceTone(int netMinor) {
  if (netMinor > 0) return BalanceTone.receivable;
  if (netMinor < 0) return BalanceTone.payable;
  return BalanceTone.settled;
}

String balanceLabel(int netMinor) => switch (balanceTone(netMinor)) {
      BalanceTone.receivable => 'You will receive',
      BalanceTone.payable => 'You will pay',
      BalanceTone.settled => 'Settled up',
    };

/// "₹12,500 receivable" / "Settled up".
String netSummary(int netMinor, {String currency = kFallbackCurrency}) {
  final tone = balanceTone(netMinor);
  if (tone == BalanceTone.settled) return 'Settled up';
  return '${formatMinor(netMinor.abs(), currency: currency)} '
      '${tone == BalanceTone.receivable ? 'receivable' : 'payable'}';
}
