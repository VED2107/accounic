library;

import 'package:intl/intl.dart';

/// Money handling (context.md §7).
///
/// The Dart mirror of `web/src/lib/money.ts`. Both sides must agree exactly,
/// because the same integer minor units cross the wire to both — a rounding
/// difference here would show a user two different balances on two devices.
///
/// Dart's `int` is 64-bit on Android and Windows, so minor units never lose
/// precision. `double` is not used anywhere in the money path.

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
};

String localeFor(String currency) =>
    _currencyLocale[currency.toUpperCase()] ?? 'en_US';

/// Parses what the user typed into minor units.
///
/// Accepts `1,234.5`, `₹1234`, ` 1 234.56 `. Returns null for anything that is
/// not a usable amount, including more than two decimal places — silently
/// rounding away a user's paise is not acceptable.
int? parseAmountToMinor(String input) {
  final cleaned = input
      .replaceAll(RegExp(r'[\s,  ]'), '')
      .replaceAll(RegExp(r'[^\d.\-]'), '');

  if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return null;
  if ('.'.allMatches(cleaned).length > 1) return null;

  final negative = cleaned.startsWith('-');
  final unsigned = negative ? cleaned.substring(1) : cleaned;
  if (!RegExp(r'^\d*(\.\d*)?$').hasMatch(unsigned)) return null;

  final parts = unsigned.split('.');
  final whole = parts[0];
  final fraction = parts.length > 1 ? parts[1] : '';
  if (fraction.length > 2) return null;
  if (whole.isEmpty && fraction.isEmpty) return null;

  final padded = fraction.padRight(2, '0');
  final minor = (int.tryParse(whole.isEmpty ? '0' : whole) ?? 0) * minorPerMajor +
      (int.tryParse(padded.isEmpty ? '0' : padded) ?? 0);

  return negative ? -minor : minor;
}

/// Minor units to an editable string: 1050050 -> "10500.50".
String minorToInput(int minor) {
  final negative = minor < 0;
  final abs = minor.abs();
  final whole = abs ~/ minorPerMajor;
  final fraction = abs % minorPerMajor;
  final body = fraction == 0
      ? '$whole'
      : '$whole.${fraction.toString().padLeft(2, '0')}';
  return negative ? '-$body' : body;
}

/// Minor units to a display string: 1050050 -> "₹10,500.50".
String formatMinor(
  int minor, {
  String currency = 'INR',
  bool compactDecimals = true,
  bool withSymbol = true,
  bool signed = false,
}) {
  final abs = minor.abs();
  final hasFraction = abs % minorPerMajor != 0;
  final digits = compactDecimals && !hasFraction ? 0 : 2;

  final format = withSymbol
      ? NumberFormat.currency(
          locale: localeFor(currency),
          name: currency,
          symbol: currencySymbol(currency),
          decimalDigits: digits,
        )
      : NumberFormat.decimalPatternDigits(
          locale: localeFor(currency),
          decimalDigits: digits,
        );

  final text = format.format(abs / minorPerMajor);

  if (signed && minor != 0) return '${minor > 0 ? '+' : '−'}$text';
  if (minor < 0) return '−$text';
  return text;
}

String currencySymbol(String currency) {
  const symbols = {
    'INR': '₹',
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'AED': 'AED ',
    'AUD': r'A$',
    'CAD': r'C$',
    'SGD': r'S$',
  };
  return symbols[currency.toUpperCase()] ?? '$currency ';
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
String netSummary(int netMinor, {String currency = 'INR'}) {
  final tone = balanceTone(netMinor);
  if (tone == BalanceTone.settled) return 'Settled up';
  return '${formatMinor(netMinor.abs(), currency: currency)} '
      '${tone == BalanceTone.receivable ? 'receivable' : 'payable'}';
}
