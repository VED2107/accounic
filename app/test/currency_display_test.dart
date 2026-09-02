import 'package:flutter_test/flutter_test.dart';
import 'package:accounic/core/currencies.dart';
import 'package:accounic/core/money.dart';

/// The currency presentation rules (upgrade §44, §45), Dart side.
///
/// The mirror of web/src/lib/currency-display.test.ts, case for case: the two
/// clients must write the same amount the same way, or a user reading their
/// phone and their browser sees two ledgers.
///
/// The bug these pin: a screen showed `400 AED`, a rate of `1 AED = ₹25.9842`
/// and a converted `₹10,393.69`, and 400 × 25.9842 is ₹10,393.68. The
/// conversion was right — the stored rate is 25.984225 and the arithmetic runs
/// on all nine decimals of it. What was wrong is that the printed rate could
/// not reproduce the printed amount.
void main() {
  final aedInr = rateToE9(25.984225);
  final usdInr = rateToE9(95.427612);

  group('conversion arithmetic', () {
    test('400 AED at the full stored rate is ₹10,393.69', () {
      expect(convertMinor(40000, 'AED', 'INR', aedInr), 1039369);
    });

    test('₹10,393.68 is what rounding the rate first would have given', () {
      expect(convertMinor(40000, 'AED', 'INR', rateToE9(25.9842)), 1039368);
    });

    test(r'$40 at the full stored rate is ₹3,817.10', () {
      expect(convertMinor(4000, 'USD', 'INR', usdInr), 381710);
    });

    test('the exponent shifts when the decimals differ', () {
      expect(convertMinor(100000, 'INR', 'JPY', rateToE9(1.78)), 1780);
    });

    test('no rate is null — "not known", never zero', () {
      expect(convertMinor(100000, 'INR', 'AED', null), isNull);
    });
  });

  group('rateSentence', () {
    test('reads in the direction the user reads it', () {
      expect(rateSentence('AED', 'INR', rateToE9(24.01)), '1 AED = ₹24.01 INR');
    });

    test('shows enough of the rate to reproduce the amount beside it', () {
      final sentence = rateSentence('AED', 'INR', aedInr, amountMinor: 40000);
      expect(sentence, isNot('1 AED = ₹25.9842 INR'));

      final shown = double.parse(
        sentence.replaceFirst('1 AED = ₹', '').replaceFirst(' INR', ''),
      );
      expect(
        convertMinor(40000, 'AED', 'INR', rateToE9(shown)),
        convertMinor(40000, 'AED', 'INR', aedInr),
      );
    });

    test('does the same for the dollar case', () {
      final sentence = rateSentence('USD', 'INR', usdInr, amountMinor: 4000);
      final shown = double.parse(
        sentence.replaceFirst('1 USD = ₹', '').replaceFirst(' INR', ''),
      );
      expect(
        convertMinor(4000, 'USD', 'INR', rateToE9(shown)),
        convertMinor(4000, 'USD', 'INR', usdInr),
      );
    });

    test('stays short when short is already exact', () {
      expect(rateSentence('AED', 'INR', rateToE9(25.5), amountMinor: 40000),
          '1 AED = ₹25.50 INR');
    });

    test('falls back to a readable precision with no amount in hand', () {
      expect(rateSentence('AED', 'INR', aedInr), '1 AED = ₹25.9842 INR');
    });
    test('prints the rate it actually tested, not a float a hair away', () {
      // The live rate that exposed this: 1 AED = 25.984215 INR. The precision
      // search accepted five decimals on 25.98422, while the text was rendered
      // from the raw double and came out 25.98421 — which multiplies out to
      // ₹10,393.68 under a printed ₹10,393.69.
      const stored = 25984215000;
      final sentence = rateSentence('AED', 'INR', stored, amountMinor: 40000);

      expect(convertMinor(40000, 'AED', 'INR', stored), 1039369);
      expect(sentence, '1 AED = ₹25.98422 INR');
    });

    test('holds for every stored rate and amount on this ledger', () {
      const cases = [
        (40000, 25984215000, 'AED'),
        (4000, 95427628000, 'USD'),
        (200000, 25984215000, 'AED'),
        (1, 95427628000, 'USD'),
        (99999999, 25984215000, 'AED'),
      ];

      for (final (amount, stored, from) in cases) {
        final sentence = rateSentence(from, 'INR', stored, amountMinor: amount);
        final shown = double.parse(sentence
            .replaceFirst('1 $from = ₹', '')
            .replaceFirst(' INR', '')
            .replaceAll(',', ''));
        expect(
          convertMinor(amount, from, 'INR', rateToE9(shown)),
          convertMinor(amount, from, 'INR', stored),
        );
      }
    });
  });

  group('the amount hierarchy', () {
    test('writes an original amount with its symbol and its code', () {
      expect(formatMoney(4000, currency: 'USD'), r'$40 USD');
      expect(formatMoney(500000, currency: 'INR'), '₹5,000 INR');
      expect(formatMoney(1000, currency: 'EUR'), '€10 EUR');
    });

    test('drops a symbol that cannot lead a figure, and keeps the code', () {
      expect(formatMoney(40000, currency: 'AED'), '400 AED');
      expect(displaySymbol('AED'), '');
      expect(displaySymbol('INR'), '₹');
    });

    test('writes a converted amount as an approximation, in full', () {
      // On screen the conversion is always *into* the workspace currency, which
      // the screen states all around the figure — so the ≈ carries the meaning
      // and the code would only repeat the ₹ (upgrade §45).
      expect(formatApprox(1039369, currency: 'INR'), '≈ ₹10,393.69');
      expect(formatApprox(381710, currency: 'INR'), '≈ ₹3,817.10');
    });

    test('puts the code back for anything that leaves the app', () {
      // A statement is read in an inbox or a folder, with no workspace around
      // it to supply the missing currency.
      expect(
        formatApprox(1039369, currency: 'INR', withCode: true),
        '≈ ₹10,393.69 INR',
      );
    });

    test('keeps the code on every currency that is not the workspace one', () {
      // The whole point of dropping the suffix: the foreign row still names
      // itself, and the contrast is what marks it as foreign. Matches the same
      // three assertions in web/src/lib/currency-display.test.ts.
      expect(formatMoney(253750, currency: 'INR', base: 'INR'), '₹2,537.50');
      expect(formatMoney(50000, currency: 'AED', base: 'INR'), '500 AED');
      // No base known → nothing may be assumed, so the code stays.
      expect(formatMoney(253750, currency: 'INR'), '₹2,537.50 INR');
    });

    test('handles the awkward values', () {
      expect(formatMoney(0, currency: 'INR'), '₹0 INR');
      expect(formatMoney(-500000, currency: 'INR'), '−₹5,000 INR');
      expect(formatMoney(1000, currency: 'JPY'), '¥1,000 JPY');
      // Latin digits, always: a column that mixes numbering systems cannot be
      // read at all.
      expect(formatMoney(1234, currency: 'KWD'), '1.234 KWD');
      expect(formatMoney(1000000000, currency: 'INR'), '₹1,00,00,000 INR');
    });

    test('renders an unknown currency rather than throwing', () {
      expect(formatMoney(1000, currency: 'ZZZ'), '10 ZZZ');
      expect(formatMoney(1000, currency: null), '₹10 INR');
    });
  });

  group('a rate a human typed', () {
    test('parses to the nine-decimal scale the column stores', () {
      expect(parseRateToE9('96.5'), 96500000000);
      expect(parseRateToE9('95.427612'), usdInr);
      expect(parseRateToE9(' 1,234.5 '), 1234500000000);
    });

    test('refuses what it cannot store exactly, and what is not a rate', () {
      expect(parseRateToE9('95.4276123456'), isNull);
      expect(parseRateToE9('0'), isNull);
      expect(parseRateToE9('-5'), isNull);
      expect(parseRateToE9(''), isNull);
      expect(parseRateToE9('abc'), isNull);
    });

    test('round-trips through the editable form', () {
      for (final rateE9 in [96500000000, usdInr, aedInr, kRateScale]) {
        expect(parseRateToE9(rateToInput(rateE9)), rateE9);
      }
    });

    test('is recognised by its provenance, and only by that exact marker', () {
      expect(rateIsManual(kManualRateSource), isTrue);
      expect(rateIsManual(' Manual-Rate '), isTrue);
      // 0011 defaults a missing source to the bare word 'manual', so rows
      // written by a client that sent none must NOT read as hand-rated.
      expect(rateIsManual('manual'), isFalse);
      expect(rateIsManual('live'), isFalse);
      expect(rateIsManual(null), isFalse);
    });

    test('converts at the typed rate, at full precision', () {
      expect(convertMinor(4000, 'USD', 'INR', parseRateToE9('96.5')), 386000);
    });
  });
}
