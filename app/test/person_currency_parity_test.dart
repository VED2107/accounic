import 'dart:convert';
import 'dart:io';

import 'package:accounic/data/models.dart';
import 'package:accounic/data/statement_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dashboard = Person Details = Person statement.
///
/// The fixtures are real `person_page()` responses from
/// db/tools/smoke-person-parity.mjs: an INR workspace whose history was entered
/// at 1 AED = ₹22.50 while today's cached rate is ₹26.32. The same files drive
/// web/src/lib/pdf/person-parity.test.ts, so both clients are held to one set
/// of figures.
///
/// The bug: the person screen and its statement printed the dirham account's
/// whole position re-converted at today's rate (₹96,491.05), re-pricing rupees
/// typed as rupees; and the per-currency card labelled a rupee figure as
/// dirhams. The dashboard counts those rupees as the rupees they were.
PersonPage _fixture(String name) => PersonPage.fromJson(
      jsonDecode(File('../shared/fixtures/$name.json').readAsStringSync())
          as Map<String, dynamic>,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final aed = _fixture('person-page-aed-ledger');
  final inr = _fixture('person-page-inr-ledger');

  test('dirham account: rupees entered as rupees stay rupees', () {
    final rupees = aed.regularByCurrency.firstWhere((r) => r.currency == 'INR');
    final dirhams = aed.regularByCurrency.firstWhere((r) => r.currency == 'AED');
    expect(rupees.net, 10500000);
    expect(aed.regularInBase, rupees.net + dirhams.netBaseMinor!);
    expect(aed.regularInBase, 7868421);
    // Not the old whole-position figure at today's rate.
    expect(aed.regular.positionBaseMinor, 9649105);
    expect(aed.regularInBase, isNot(aed.regular.positionBaseMinor));
  });

  test('rupee account: a dirham entry is worth the rupees it was booked at', () {
    final dirhams = inr.regularByCurrency.firstWhere((r) => r.currency == 'AED');
    final eq = dirhams.baseEquivalent('INR')!;
    expect(eq.asBooked, isTrue);
    expect(eq.minor, dirhams.netLedgerMinor);
    expect(eq.minor, isNot(dirhams.netBaseMinor));
    expect(inr.regularInBase, inr.regular.positionMinor);
    expect(
      CurrencyHalfBreakdown.workspaceTotal(inr.openingByCurrency, 'INR', 'INR'),
      inr.openingPosition.positionMinor,
    );
  });

  test('a dirham row on a dirham account falls back to the dashboard figure', () {
    final dirhams = aed.regularByCurrency.firstWhere((r) => r.currency == 'AED');
    final eq = dirhams.baseEquivalent('AED')!;
    expect(eq.asBooked, isFalse);
    expect(eq.minor, dirhams.netBaseMinor);
  });

  test('unknown, not zero, when a foreign row has no figure', () {
    const row = CurrencyHalfBreakdown(
      currency: 'USD',
      baseCurrency: 'INR',
      credit: 100,
      debit: 0,
      settled: 0,
      receivable: 100,
      payable: 0,
      net: 100,
    );
    expect(CurrencyHalfBreakdown.workspaceTotal([row], 'AED', 'INR'), isNull);
  });

  for (final (name, page) in [('aed-ledger', aed), ('inr-ledger', inr)]) {
    test('statement renders over real data: $name', () async {
      final bytes = await PersonStatement.build(
        page: page,
        ownerName: 'Parity Check',
        generatedAt: DateTime(2026, 9, 25, 14),
      );
      expect(bytes.length, greaterThan(1000));
      // Set PARITY_OUT to keep the file so its text can be read back.
      final out = Platform.environment['PARITY_OUT'];
      if (out != null) File('$out/flutter-$name.pdf').writeAsBytesSync(bytes);
    });
  }
}
