import 'package:accounic/core/currencies.dart';
import 'package:accounic/data/rate_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a rate provider does when it is having a bad day (upgrade §6, §7).
///
/// The mirror of web/src/lib/rate-source.test.ts. Every case here is a way for
/// a broken provider to silently change someone's money, so every one of them
/// has to end at "no rate for this pair" rather than at a number.
void main() {
  group('parsePrimaryRates — open.er-api.com', () {
    test('reads a successful table', () {
      final table = parsePrimaryRates({
        'result': 'success',
        'time_last_update_utc': 'Mon, 01 Sep 2026 00:00:01 +0000',
        'rates': {'INR': 23.9, 'USD': 0.272},
      });

      expect(table, isNotNull);
      expect(table!.source, 'open.er-api.com');
      expect(table.rates['INR'], 23.9);
    });

    test('refuses a 200 that carries an error', () {
      expect(
        parsePrimaryRates({'result': 'error', 'error-type': 'unsupported-code'}),
        isNull,
      );
    });

    test('refuses a payload that is not a map', () {
      expect(parsePrimaryRates(null), isNull);
      expect(parsePrimaryRates('rates'), isNull);
      expect(parsePrimaryRates([1, 2, 3]), isNull);
    });

    test('drops entries that are not numbers, and keeps the rest', () {
      final table = parsePrimaryRates({
        'result': 'success',
        'rates': {'INR': 23.9, 'USD': '0.272', 'EUR': null, 'GBP': double.nan},
      });

      expect(table!.rates.keys.toList(), ['INR']);
    });

    test('refuses a table with nothing usable left in it', () {
      expect(
        parsePrimaryRates({'result': 'success', 'rates': {'INR': '23.9'}}),
        isNull,
      );
      expect(parsePrimaryRates({'result': 'success', 'rates': {}}), isNull);
    });
  });

  group('parseFallbackRates — frankfurter.dev', () {
    test('reads a table and keeps the published date', () {
      final table = parseFallbackRates({
        'date': '2026-08-29',
        'rates': {'INR': 94.1},
      });

      expect(table!.asOf, '2026-08-29');
      expect(table.source, 'frankfurter.dev (ECB)');
      expect(table.rates['INR'], 94.1);
    });

    test('refuses an empty or malformed body', () {
      expect(parseFallbackRates(const {}), isNull);
      expect(parseFallbackRates({'rates': null}), isNull);
      expect(parseFallbackRates(null), isNull);
    });
  });

  group('a rate has to be usable before it is used', () {
    test('accepts an ordinary rate', () {
      expect(isUsableRateE9(kRateScale), isTrue);
      expect(usableRateToE9(23.9), 23900000000);
    });

    test('refuses zero, negatives and nonsense — a zero rate erases an amount', () {
      expect(usableRateToE9(0), isNull);
      expect(usableRateToE9(-1), isNull);
      expect(usableRateToE9(double.nan), isNull);
      expect(usableRateToE9(double.infinity), isNull);
      expect(usableRateToE9(null), isNull);
    });

    test('refuses a rate so small it has already rounded away', () {
      expect(usableRateToE9(1e-12), isNull);
    });

    test('refuses a rate no real pair reaches', () {
      expect(isUsableRateE9(kMaxRateE9 + 1), isFalse);
    });

    test('inverts a stored rate, and refuses to divide by a bad one', () {
      expect(invertRateE9(2 * kRateScale), kRateScale ~/ 2);
      expect(invertRateE9(0), isNull);
      expect(invertRateE9(-5), isNull);
    });

    test('the two clients agree on every boundary', () {
      // web/src/lib/currencies.ts carries the same two constants; a difference
      // here would mean one client converting where the other refuses.
      expect(kMinRateE9, 1);
      expect(kMaxRateE9, 1000000 * kRateScale);
    });
  });
}
