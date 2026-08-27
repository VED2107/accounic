import 'package:accounic/core/theme.dart';
import 'package:accounic/data/models.dart';
import 'package:accounic/ui/sheets/sheet_scaffold.dart';
import 'package:accounic/ui/widgets/currency_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The manual converted amount, and the form's isolation from the app footer
/// (upgrade §40, §41).
///
/// The brief's case throughout: an AED account, Rs 1,000 handed over, a rate
/// that makes it AED 44.20, and AED 43 actually given at the counter.
void main() {
  // Rs 1,000 in minor units, and the two figures it can become.
  const rupees1000 = 100000;
  const autoAed = 4420;
  const actualAed = 4300;

  Map<String, dynamic> row({
    String? mode,
    int? auto,
    int amountMinor = autoAed,
  }) =>
      {
        'id': 't1',
        'entry_kind': 'transaction',
        'entry_type': 'credit',
        'money_direction': 'in',
        'amount_minor': amountMinor,
        'entry_date': '2026-08-25',
        'is_void': false,
        'entered_amount_minor': rupees1000,
        'entered_currency': 'INR',
        'exchange_rate_e9': 44200000,
        if (mode != null) 'conversion_mode': mode,
        if (auto != null) 'auto_converted_amount_minor': auto,
      };

  group('reading a converted row', () {
    test('an automatic row carries the rate figure as its amount', () {
      final entry = TimelineEntry.fromJson(row(mode: 'automatic'));

      expect(entry.amountMinor, autoAed);
      expect(entry.conversionMode, 'automatic');
      expect(entry.isManualConversion, isFalse);
      expect(entry.autoConvertedAmountMinor, isNull);
      // The rupees that changed hands are still on the row.
      expect(entry.enteredAmountMinor, rupees1000);
      expect(entry.enteredCurrency, 'INR');
    });

    test('a manual row carries what was exchanged, and what the rate said', () {
      final entry = TimelineEntry.fromJson(
        row(mode: 'manual', auto: autoAed, amountMinor: actualAed),
      );

      expect(entry.amountMinor, actualAed);
      expect(entry.isManualConversion, isTrue);
      expect(entry.autoConvertedAmountMinor, autoAed);
      expect(entry.exchangeRateE9, 44200000);
    });

    test('a pre-v1.1.2 row, which stored neither key, still reads', () {
      final entry = TimelineEntry.fromJson(row());

      expect(entry.amountMinor, autoAed);
      expect(entry.conversionMode, isNull);
      expect(entry.isManualConversion, isFalse);
      expect(entry.autoConvertedAmountMinor, isNull);
    });

    test('the activity feed reads the same two keys', () {
      final item = ActivityItem.fromJson({
        'id': 't1',
        'person_id': 'p1',
        'person_name': 'Ahmed',
        'entry_kind': 'transaction',
        'entry_type': 'credit',
        'amount_minor': actualAed,
        'entry_date': '2026-08-25',
        'currency': 'AED',
        'entered_amount_minor': rupees1000,
        'entered_currency': 'INR',
        'exchange_rate_e9': 44200000,
        'conversion_mode': 'manual',
        'auto_converted_amount_minor': autoAed,
      });

      expect(item.isManualConversion, isTrue);
      expect(item.autoConvertedAmountMinor, autoAed);
      expect(item.amountMinor, actualAed);
    });
  });

  group('what a stored entry says on screen', () {
    Future<void> pump(WidgetTester tester, TimelineEntry entry) =>
        tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: RateNote(
              enteredMinor: entry.enteredAmountMinor,
              enteredCurrency: entry.enteredCurrency,
              rateE9: entry.exchangeRateE9,
              rateSource: entry.exchangeRateSource,
              accountCurrency: 'AED',
              conversionMode: entry.conversionMode,
              autoConvertedMinor: entry.autoConvertedAmountMinor,
            ),
          ),
        ));

    testWidgets('an automatic row shows what was handed over and the rate',
        (tester) async {
      await pump(tester, TimelineEntry.fromJson(row(mode: 'automatic')));

      final text = tester.widget<Text>(find.byType(Text)).data!;
      expect(text, contains('1 INR = '));
      expect(text, isNot(contains('Amount entered by hand')));
    });

    testWidgets('a manual row says so, and says what the rate said',
        (tester) async {
      await pump(
        tester,
        TimelineEntry.fromJson(row(mode: 'manual', auto: autoAed, amountMinor: actualAed)),
      );

      final text = tester.widget<Text>(find.byType(Text)).data!;
      // Never hidden: the rate, the fact that somebody overrode the conversion
      // on purpose, and what the rate had said.
      expect(text, contains('1 INR = '));
      expect(text, contains('Amount entered by hand'));
      expect(text, contains('44.20'));
    });
  });

  group('a form is isolated from the application footer', () {
    // The regression this pins: go_router builds the shell around a nested
    // navigator, so a sheet pushed there opened *inside* the shell's Scaffold
    // and left the bottom bar and the docked `+` drawn over the form. Every
    // modal in the product goes to the ROOT navigator instead.
    testWidgets('showAppSheet pushes above the shell, not inside it',
        (tester) async {
      final rootKey = GlobalKey<NavigatorState>();
      final shellKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        navigatorKey: rootKey,
        home: Scaffold(
          // Stands in for the shell's four destinations and its `+`.
          bottomNavigationBar: const SizedBox(height: 62, child: Text('App footer')),
          body: Navigator(
            key: shellKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showAppSheet<void>(
                    context,
                    (context) => SheetScaffold(
                      title: 'Add transaction',
                      primaryLabel: 'Save transaction',
                      onPrimary: () {},
                      children: const [SizedBox(height: 40)],
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Add transaction'), findsOneWidget);

      // The sheet is a descendant of the root navigator and NOT of the shell's,
      // which is what keeps the footer from being drawn over it.
      expect(
        find.descendant(
          of: find.byKey(rootKey),
          matching: find.text('Add transaction'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(shellKey),
          matching: find.text('Add transaction'),
        ),
        findsNothing,
      );

      // And the form supplies its own action area, which is still reachable.
      expect(find.text('Save transaction'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
