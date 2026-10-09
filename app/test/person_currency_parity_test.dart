import 'dart:convert';
import 'dart:io';

import 'package:accounic/data/models.dart';
import 'package:accounic/data/statement_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dashboard = Person Details = Person statement.
///
/// The fixtures are real `person_page()` responses, and the dashboard's own
/// per-account figures, from db/tools/smoke-person-parity.mjs: an INR workspace
/// whose history was entered at 1 AED = ₹22.50 and ₹24.00 while today's cached
/// rate is ₹26.32. The same files drive web/src/lib/pdf/person-parity.test.ts,
/// so both clients are held to one set of figures.
///
/// * Dubai Traders, kept in AED: rupee entries (one manual), a dirham entry, a
///   rupee opening balance, a partial settlement paid in rupees, a transfer in.
/// * Mumbai Supplier, kept in INR: dirham entries at two old rates and one
///   manual, a dirham opening balance, a partial settlement, a transfer out.
/// * Gulf Settled, kept in AED: AED 10,000 owed, repaid as ₹2,25,000 at ₹22.50.
///
/// The bug: v1.16 showed each account in the workspace currency by re-adding
/// its per-currency rows — rupees at face, dirhams at today's rate. On an
/// account holding both, that is neither the sum the ledger keeps nor the
/// figure the dashboard counts: Gulf Settled, zero on the dashboard, read
/// ₹38,157.89.
Map<String, dynamic> _json(String name) =>
    jsonDecode(File('../shared/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

PersonPage _fixture(String name) => PersonPage.fromJson(_json(name));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final aed = _fixture('person-page-aed-ledger');
  final inr = _fixture('person-page-inr-ledger');
  final settled = _fixture('person-page-aed-settled');
  final dashboard = _json('dashboard-figures');
  final people = dashboard['people'] as Map<String, dynamic>;
  final pages = [aed, inr, settled];

  for (final page in pages) {
    test('${page.person.name}: workspace figures are the dashboard\'s', () {
      final d = people[page.person.name] as Map<String, dynamic>;
      expect(page.regularInBase, d['cash_in_hand_base']);
      expect(page.openingInBase, d['opening_net_base']);
    });
  }

  test('summed over the workspace, they are the dashboard\'s Total in INR', () {
    expect(pages.fold<int>(0, (t, p) => t + p.regularInBase!), dashboard['cash_in_hand']);
    expect(pages.fold<int>(0, (t, p) => t + p.openingInBase!), dashboard['opening']);
  });

  test('an AED account settled in rupees reads zero, as on the dashboard', () {
    expect(settled.regular.positionMinor, 0);
    expect(settled.regularInBase, 0);
    // What v1.16 showed: ₹2,25,000 entered, less AED 10,000 at today's rate.
    final rupees = settled.regularByCurrency.firstWhere((r) => r.currency == 'INR');
    final dirhams = settled.regularByCurrency.firstWhere((r) => r.currency == 'AED');
    expect(rupees.net + dirhams.netBaseMinor!, -3815789);
  });

  test('a rupee account sums its dirham entries at the rupees booked, never today', () {
    final dirhams = inr.regularByCurrency.firstWhere((r) => r.currency == 'AED');
    expect(dirhams.netLedgerMinor, isNot(dirhams.netBaseMinor));
    expect(inr.regularInBase, inr.regular.positionMinor);
    expect(
      inr.regularByCurrency.fold<int>(0, (t, r) => t + r.netLedgerMinor!),
      inr.regular.positionMinor,
    );
    final eq = dirhams.baseEquivalent('INR')!;
    expect(eq.asBooked, isTrue);
    expect(eq.minor, dirhams.netLedgerMinor);
  });

  test('a dirham account\'s position is the sum of what each entry booked', () {
    expect(
      aed.regularByCurrency.fold<int>(0, (t, r) => t + r.netLedgerMinor!),
      aed.regular.positionMinor,
    );
  });

  test('a dirham row on a dirham account falls back to the dashboard figure', () {
    final dirhams = aed.regularByCurrency.firstWhere((r) => r.currency == 'AED');
    final eq = dirhams.baseEquivalent('AED')!;
    expect(eq.asBooked, isFalse);
    expect(eq.minor, dirhams.netBaseMinor);
  });

  test('unknown, not zero, when there is no rate', () {
    const split = PositionSplit(currency: 'AED', baseCurrency: 'INR', positionMinor: 100);
    expect(split.inBaseMinor, isNull);
  });

  for (final (name, page) in [
    ('aed-ledger', aed),
    ('inr-ledger', inr),
    ('aed-settled', settled),
  ]) {
    test('statement renders over real data: $name', () async {
      final bytes = await PersonStatement.build(
        page: page,
        ownerName: 'Parity Check',
        generatedAt: DateTime(2026, 10, 10, 14),
      );
      expect(bytes.length, greaterThan(1000));
      // Set PARITY_OUT to keep the file; db/tools/verify-statement-pdfs.mjs
      // reads its text back and checks every figure against the dashboard's.
      final out = Platform.environment['PARITY_OUT'];
      if (out != null) File('$out/flutter-$name.pdf').writeAsBytesSync(bytes);
    });
  }
}
