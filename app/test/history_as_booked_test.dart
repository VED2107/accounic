import 'dart:convert';
import 'dart:io';

import 'package:accounic/core/money.dart';
import 'package:accounic/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every historical figure on the person screen is the one BOOKED when the
/// entry was made (db/migrations/0034) — never re-priced at today's rate.
///
/// Fixtures: real person_page() responses (db/tools/smoke-person-parity.mjs)
/// for an INR workspace whose history was entered at 1 AED = ₹22.50 and ₹24.00
/// while today's cached rate is ₹26.32. Twin of
/// web/src/lib/history-as-booked.test.ts.
PersonPage _fixture(String name) => PersonPage.fromJson(
      jsonDecode(File('../shared/fixtures/$name.json').readAsStringSync())
          as Map<String, dynamic>,
    );

void main() {
  final aed = _fixture('person-page-aed-ledger');
  final inr = _fixture('person-page-inr-ledger');
  final settled = _fixture('person-page-aed-settled');

  TimelineEntry row(PersonPage page, String note) =>
      page.timeline.firstWhere((t) => t.note == note);

  group('timeline rows keep the rate they were entered at', () {
    test('a dirham entry on a rupee account is the rupees it was booked at', () {
      // 2,000 AED at ₹22.50 = ₹45,000, not 2,000 × today's ₹26.32.
      final entry = row(inr, 'dirhams at 22.50');
      expect(entry.amountMinor, 4500000);
      expect(entry.amountBaseMinor, 4500000);
    });

    test('a manual conversion stays the figure typed', () {
      expect(row(inr, 'dirhams, manual 2,700 rupees').amountBaseMinor, 270000);
    });

    test('a rupee entry on a dirham account is its rupees at face', () {
      expect(row(aed, 'rupees at 22.50').amountBaseMinor, 10000000);
      expect(row(aed, 'part paid in rupees at 24.00').amountBaseMinor, 2000000);
    });

    test('a dirham entry on a dirham account has no rupee figure', () {
      expect(row(aed, 'dirhams, native').amountBaseMinor, isNull);
      expect(row(settled, 'dirhams borrowed').amountBaseMinor, isNull);
    });

    test('rows reconcile to the headline at their booked figures', () {
      for (final page in [aed, inr, settled]) {
        expect(
          page.regularByCurrency.fold<int>(0, (t, r) => t + (r.netLedgerMinor ?? 0)),
          page.regular.positionMinor,
        );
      }
    });
  });

  group('per-currency rows show what was booked, in the account currency', () {
    test('dirham row on a rupee account: the rupees booked, not today', () {
      final dirhams = inr.regularByCurrency.firstWhere((r) => r.currency == 'AED');
      expect(dirhams.netBaseMinor, isNot(dirhams.netLedgerMinor));
      final eq = dirhams.bookedEquivalent('INR')!;
      expect((eq.minor, eq.currency), (3970000, 'INR'));
    });

    test('rupee row on a dirham account: the dirhams it was booked at', () {
      final rupees = settled.regularByCurrency.firstWhere((r) => r.currency == 'INR');
      final eq = rupees.bookedEquivalent('AED')!;
      expect((eq.minor, eq.currency), (1000000, 'AED'));
    });

    test('missing booked figure says nothing rather than re-price', () {
      const row = CurrencyHalfBreakdown(
        currency: 'AED',
        baseCurrency: 'INR',
        credit: 100,
        debit: 0,
        settled: 0,
        receivable: 100,
        payable: 0,
        net: 100,
        netBaseMinor: 2632,
      );
      expect(row.bookedEquivalent('INR'), isNull);
    });
  });

  group('outstanding is the net position, as the dashboard counts it', () {
    test('a fully settled account has nothing to receive or pay', () {
      expect(settled.regular.receivableMinor, 1000000); // gross, still open
      expect(settled.regular.payableMinor, 1000000);
      final o = outstandingOf(settled.regular.positionMinor);
      expect((o.receivable, o.payable), (0, 0));
      expect(settled.regularInBase, 0);
    });

    test('a partial settlement leaves exactly the remainder', () {
      final o = outstandingOf(inr.regular.positionMinor);
      expect((o.receivable, o.payable), (2470000, 0));
    });

    test('mixed currencies net to the booked position; payable side', () {
      expect(outstandingOf(aed.regular.positionMinor).receivable, 626666);
      final o = outstandingOf(-500);
      expect((o.receivable, o.payable), (0, 500));
    });

    test('opening book stays apart from cash in hand', () {
      expect(aed.openingPosition.positionMinor, isNot(0));
      expect(outstandingOf(aed.regular.positionMinor).receivable, aed.regular.positionMinor);
    });
  });
}
