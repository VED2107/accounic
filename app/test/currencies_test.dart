import 'dart:convert';
import 'dart:io';

import 'package:accounic/core/currencies.dart';
import 'package:accounic/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// Currency tests (upgrade §19, §20).
///
/// The same cases as web/src/lib/currencies.test.ts, deliberately — and the
/// same conversion arithmetic as db/tests/04_currency.sql. Three runtimes
/// convert money; if any two of them disagree by a single minor unit, a user
/// sees two different balances on two devices for the same ledger.
void main() {
  final shared = jsonDecode(
    File('../shared/currencies.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  final expected = (shared['currencies'] as List)
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList();

  group('the generated list', () {
    test('matches shared/currencies.json exactly', () {
      expect(kCurrencies.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        expect(kCurrencies[i].code, expected[i]['code']);
        expect(kCurrencies[i].name, expected[i]['name']);
        expect(kCurrencies[i].symbol, expected[i]['symbol']);
        expect(kCurrencies[i].decimals, expected[i]['decimals']);
      }
    });

    test('has no duplicate codes', () {
      final codes = kCurrencies.map((c) => c.code).toSet();
      expect(codes.length, kCurrencies.length);
    });

    test('carries the currencies the product is actually used with', () {
      for (final code in ['INR', 'AED', 'USD', 'EUR', 'GBP', 'JPY']) {
        expect(isSupportedCurrency(code), isTrue, reason: code);
      }
    });

    test('rejects anything not on the list', () {
      expect(isSupportedCurrency('XXX'), isFalse);
      expect(isSupportedCurrency(''), isFalse);
      expect(isSupportedCurrency(null), isFalse);
    });

    test('is case-insensitive about codes', () {
      expect(isSupportedCurrency('aed'), isTrue);
      expect(decimalsFor('jpy'), 0);
    });

    test('labels a currency unambiguously — the code first', () {
      expect(currencyLabel('AED'), 'AED — UAE Dirham (د.إ)');
    });
  });

  group('minor units', () {
    test('knows the yen has none', () {
      expect(decimalsFor('JPY'), 0);
      expect(minorPerMajorFor('JPY'), 1);
    });

    test('knows the Gulf dinars have three', () {
      expect(decimalsFor('KWD'), 3);
      expect(minorPerMajorFor('KWD'), 1000);
    });

    test('defaults an unknown code to two rather than throwing', () {
      expect(decimalsFor('ZZZ'), 2);
    });
  });

  group('parsing against a currency', () {
    test('parses yen as whole units', () {
      expect(parseAmountToMinor('1000', currency: 'JPY'), 1000);
    });

    test('refuses a fraction of a yen instead of rounding it away', () {
      expect(parseAmountToMinor('1000.5', currency: 'JPY'), isNull);
    });

    test('parses three decimals for a dinar', () {
      expect(parseAmountToMinor('1.234', currency: 'KWD'), 1234);
      expect(parseAmountToMinor('1.2345', currency: 'KWD'), isNull);
    });

    test('still parses rupees the way it always did', () {
      expect(parseAmountToMinor('1,234.50', currency: 'INR'), 123450);
      expect(parseAmountToMinor('1,234.50'), 123450);
    });

    test('round-trips through minorToInput', () {
      const cases = {'INR': 123450, 'JPY': 1000, 'KWD': 1234};
      cases.forEach((code, minor) {
        expect(
          parseAmountToMinor(minorToInput(minor, currency: code), currency: code),
          minor,
          reason: code,
        );
      });
    });
  });

  group('formatting', () {
    test('never shows a decimal on a zero-decimal currency', () {
      expect(formatMinor(1000, currency: 'JPY').contains('.'), isFalse);
    });

    test('appends the ISO code when asked, because symbols are ambiguous', () {
      expect(formatMinor(4160, currency: 'AED', withCode: true).contains('AED'), isTrue);
    });
  });

  group('conversion', () {
    test('agrees with public.convert_amount_minor for the documented example', () {
      // ₹1,000.00 at 1 INR = 0.0416 AED is AED 41.60.
      expect(convertMinor(100000, 'INR', 'AED', rateToE9(0.0416)), 4160);
    });

    test('shifts the exponent when the decimals differ', () {
      // ₹1,000.00 at 1 INR = 1.78 JPY is ¥1,780 — 1780 minor units.
      expect(convertMinor(100000, 'INR', 'JPY', rateToE9(1.78)), 1780);
      expect(convertMinor(1780, 'JPY', 'INR', rateToE9(0.561797752)), 100000);
    });

    test('is the identity for the same currency, with or without a rate', () {
      expect(convertMinor(12345, 'INR', 'INR', null), 12345);
    });

    test('returns null rather than zero when there is no rate', () {
      expect(convertMinor(100000, 'INR', 'AED', null), isNull);
      expect(convertMinor(100000, 'INR', 'AED', 0), isNull);
    });

    test('states the rate in the direction the user reads it', () {
      expect(rateSentence('AED', 'INR', rateToE9(24.01)), '1 AED = ₹24.01 INR');
    });
  });
}
