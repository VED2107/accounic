import 'package:flutter_test/flutter_test.dart';
import 'package:accounic/core/money.dart';

/// Money tests (context.md §7, §33).
///
/// The rule under test is that money never becomes a double. Parsing must be
/// exact, refuse anything it cannot represent, and round-trip without drift —
/// a client that quietly rounds would disagree with the database, and the user
/// would see two different balances on two devices.
void main() {
  group('parseAmountToMinor', () {
    test('parses whole rupees', () {
      expect(parseAmountToMinor('5000'), 500000);
      expect(parseAmountToMinor('0'), 0);
      expect(parseAmountToMinor('1'), 100);
    });

    test('parses paise exactly', () {
      expect(parseAmountToMinor('100.50'), 10050);
      expect(parseAmountToMinor('0.01'), 1);
      expect(parseAmountToMinor('0.1'), 10);
      expect(parseAmountToMinor('.5'), 50);
      expect(parseAmountToMinor('12.34'), 1234);
    });

    test('ignores grouping, spaces and currency symbols', () {
      expect(parseAmountToMinor('1,234.50'), 123450);
      expect(parseAmountToMinor(' 1 234.56 '), 123456);
      expect(parseAmountToMinor('₹10,000'), 1000000);
      expect(parseAmountToMinor('1,00,000'), 10000000); // Indian grouping
    });

    test('refuses more than two decimals rather than rounding money away', () {
      expect(parseAmountToMinor('10.999'), isNull);
      expect(parseAmountToMinor('0.001'), isNull);
    });

    test('refuses nonsense', () {
      expect(parseAmountToMinor(''), isNull);
      expect(parseAmountToMinor('   '), isNull);
      expect(parseAmountToMinor('abc'), isNull);
      expect(parseAmountToMinor('.'), isNull);
      expect(parseAmountToMinor('-'), isNull);
      expect(parseAmountToMinor('1.2.3'), isNull);
    });

    test('keeps the sign for negatives, which callers then reject', () {
      expect(parseAmountToMinor('-500'), -50000);
    });

    test('the classic float trap stays exact', () {
      // 0.1 + 0.2 != 0.3 in binary floating point. In minor units it is just
      // 10 + 20 == 30, which is the whole reason for this representation.
      expect(parseAmountToMinor('0.10')! + parseAmountToMinor('0.20')!,
          parseAmountToMinor('0.30'));
    });

    test('round-trips through the editable form', () {
      for (final minor in [1, 99, 100, 12345, 1000000, 999999999]) {
        expect(parseAmountToMinor(minorToInput(minor)), minor,
            reason: 'round trip failed for $minor');
      }
    });
  });

  group('minorToInput', () {
    test('drops the decimals on whole amounts', () {
      expect(minorToInput(500000), '5000');
      expect(minorToInput(0), '0');
    });

    test('pads paise', () {
      expect(minorToInput(10050), '100.50');
      expect(minorToInput(1), '0.01');
      expect(minorToInput(10), '0.10');
    });
  });

  group('formatMinor', () {
    test('formats rupees with Indian grouping', () {
      // Indian grouping only diverges from Western above 99,999:
      // 10,00,000 rather than 1,000,000.
      expect(formatMinor(1000000), '₹10,000');
      expect(formatMinor(10000000), '₹1,00,000');
      expect(formatMinor(100000000), '₹10,00,000');
      expect(formatMinor(123450), '₹1,234.50');
    });

    test('shows paise only when there are paise', () {
      expect(formatMinor(500000), '₹5,000');
      expect(formatMinor(500050), '₹5,000.50');
    });

    test('honours the profile currency', () {
      expect(formatMinor(123450, currency: 'USD'), r'$1,234.50');
      expect(formatMinor(500000, currency: 'GBP'), '£5,000');
    });

    test('renders negatives with a minus sign, never parentheses', () {
      expect(formatMinor(-500000), '−₹5,000');
    });
  });

  group('balance meaning (context.md §8)', () {
    test('positive net means they owe the user', () {
      expect(balanceTone(1), BalanceTone.receivable);
      expect(balanceLabel(1000), 'You will receive');
      expect(netSummary(1250000), '₹12,500 receivable');
    });

    test('negative net means the user owes them', () {
      expect(balanceTone(-1), BalanceTone.payable);
      expect(balanceLabel(-1000), 'You will pay');
      expect(netSummary(-600000), '₹6,000 payable');
    });

    test('zero is settled', () {
      expect(balanceTone(0), BalanceTone.settled);
      expect(netSummary(0), 'Settled up');
    });
  });
}
