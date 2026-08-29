import 'package:accounic/core/theme.dart';
import 'package:accounic/data/models.dart';
import 'package:accounic/ui/sheets/settle_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A settlement is offered in the ACCOUNT's currency, never the workspace's.
///
/// The bug this pins shipped and was found on screen: a dirham account showing
/// "Cash in hand 350 AED" opened its settle sheet offering **350 INR**. The
/// sheet read `currencyProvider` — the workspace currency — for every figure it
/// drew, so on any account not kept in the workspace currency it named a
/// different sum of money than the one it was about to settle.
///
/// The database was never wrong: `create_settlement()` takes the amount in the
/// account's denomination either way, and `person_balances` denominates every
/// figure the sheet reads in that same currency. What was wrong was the label
/// on the number, which on a financial screen is the whole of it — and for a
/// currency with different decimals it would have parsed the typed amount into
/// the wrong number of minor units as well.
///
/// These are widget tests rather than unit tests deliberately: the fault was
/// not in any function, it was in which value the widget passed to the
/// formatter, and only building the widget can catch that.
void main() {
  PersonBalance balance({
    required String currency,
    int receivable = 35000,
    int payable = 0,
  }) =>
      PersonBalance.fromJson({
        'person_id': 'p1',
        'name': 'ZZ Dirham',
        'type': 'person',
        'is_archived': false,
        // The account's ledger currency — what every figure below is in.
        'currency': currency,
        'default_currency': currency,
        // The workspace currency, deliberately different, which is the whole
        // point of the test.
        'base_currency': 'INR',
        'total_credit': receivable,
        'total_debit': payable,
        'settled_in': 0,
        'settled_out': 0,
        'total_settled': 0,
        'outstanding_receivable': receivable,
        'outstanding_payable': payable,
        'net_balance': receivable - payable,
        'net_balance_base': (receivable - payable) * 24,
        'transaction_count': 1,
        'cash_in_hand_minor': receivable - payable,
        'cash_in_hand_base': (receivable - payable) * 24,
        'opening_net_minor': 0,
        'regular_receivable': receivable,
        'regular_payable': payable,
        'regular_settled_total': 0,
        'opening_entry_count': 0,
      });

  Future<void> openSettleSheet(WidgetTester tester, PersonBalance person) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: ElevatedButton(
                onPressed: () => showSettleSheet(
                  context,
                  ref,
                  balance: person,
                  openTransactions: const [],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Every rendered string on the sheet, joined — the cheapest way to ask "does
  /// this screen mention INR anywhere".
  String renderedText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' | ');

  group('the settle sheet is denominated in the account currency', () {
    testWidgets('an AED account settles in AED, and never in INR',
        (tester) async {
      await openSettleSheet(tester, balance(currency: 'AED'));

      final text = renderedText(tester);
      expect(text, contains('AED'));
      // THE BUG: the workspace currency must not appear on this sheet at all.
      // Every figure here is one of the account's own.
      expect(text, isNot(contains('INR')));
    });

    testWidgets('a USD account settles in USD', (tester) async {
      await openSettleSheet(tester, balance(currency: 'USD'));

      final text = renderedText(tester);
      expect(text, contains('USD'));
      expect(text, isNot(contains('INR')));
    });

    testWidgets('and an account kept in the workspace currency is unchanged',
        (tester) async {
      // The case that always worked, kept so the fix cannot regress it: when
      // the two currencies agree, the sheet reads exactly as it did before.
      await openSettleSheet(tester, balance(currency: 'INR'));

      expect(renderedText(tester), contains('INR'));
    });

    testWidgets('the outstanding figure is the account-currency one',
        (tester) async {
      await openSettleSheet(tester, balance(currency: 'AED', receivable: 35000));

      // 350.00 AED — the account's outstanding, formatted in the account's
      // currency. Never the base-currency equivalent.
      expect(find.textContaining('350'), findsWidgets);
    });
  });
}
