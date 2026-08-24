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

const Map<String, String> _currencyLocale = {
  'INR': 'en_IN',
  'USD': 'en_US',
  'EUR': 'de_DE',
  'GBP': 'en_GB',
  'AED': 'en_AE',
  'AUD': 'en_AU',
  'CAD': 'en_CA',
  'SGD': 'en_SG',
  'JPY': 'ja_JP',
  'CNY': 'zh_CN',
  'CHF': 'de_CH',
  'SAR': 'ar_SA',
  'QAR': 'ar_QA',
  'KWD': 'ar_KW',
  'BHD': 'ar_BH',
  'OMR': 'ar_OM',
  'JOD': 'ar_JO',
  'PKR': 'en_PK',
  'BDT': 'bn_BD',
  'LKR': 'si_LK',
  'NPR': 'ne_NP',
  'MYR': 'ms_MY',
  'THB': 'th_TH',
  'IDR': 'id_ID',
  'PHP': 'en_PH',
  'VND': 'vi_VN',
  'KRW': 'ko_KR',
  'ZAR': 'en_ZA',
  'NGN': 'en_NG',
  'KES': 'en_KE',
  'EGP': 'ar_EG',
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

  final format = withSymbol
      ? NumberFormat.currency(
          locale: localeFor(code),
          name: code,
          symbol: currencySymbol(code),
          decimalDigits: digits,
        )
      : NumberFormat.decimalPatternDigits(
          locale: localeFor(code),
          decimalDigits: digits,
        );

  final formatted = format.format(abs / units);
  // The ISO code, for the places where the symbol alone is ambiguous — and $ is
  // four different currencies in this list alone (upgrade §11).
  final text = withCode ? '$formatted $code' : formatted;

  if (signed && minor != 0) return '${minor > 0 ? '+' : '−'}$text';
  if (minor < 0) return '−$text';
  return text;
}

/// The symbol for a currency, from the one list every client shares.
String currencySymbol(String currency) =>
    currencyOf(currency)?.symbol ?? '${normaliseCode(currency)} ';

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
