import 'package:accounic/core/theme.dart';
import 'package:accounic/data/models.dart';
import 'package:accounic/ui/sheets/person_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opening balance on the edit form.
///
/// It was on the create form only, which meant an account opened with the wrong
/// figure — or opened without one and needing it later — could not be corrected
/// from the app at all. The RPC and the repository method both already existed;
/// what was missing was the form offering them.
///
/// What these pin is that editing loads the balance that is actually there, in
/// the right direction, and that the same three choices are on offer as when
/// the person was created — including the one that removes it.
void main() {
  Person person({String? currency, String? ledgerCurrency}) => Person(
        id: 'p1',
        ownerId: 'o1',
        name: 'Ahmed',
        type: PartyType.person,
        isArchived: false,
        currency: currency,
        ledgerCurrency: ledgerCurrency,
      );

  Future<void> pumpSheet(
    WidgetTester tester, {
    Person? editing,
    int openingMinor = 0,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: ElevatedButton(
                onPressed: () => showPersonSheet(
                  context,
                  ref,
                  person: editing,
                  openingMinor: openingMinor,
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

  testWidgets('editing offers the opening balance, as creating does',
      (tester) async {
    await pumpSheet(tester, editing: person(currency: 'INR'));

    expect(find.text('OPENING BALANCE'), findsOneWidget);
    // The same three choices, worded the same way, in the same order.
    expect(find.text('No opening balance'), findsOneWidget);
    expect(find.text('They owe me'), findsOneWidget);
    expect(find.text('I owe them'), findsOneWidget);
  });

  testWidgets('an account with no opening balance opens on "none"',
      (tester) async {
    await pumpSheet(tester, editing: person(currency: 'INR'));

    // Nothing is prefilled, so nothing is about to be rewritten.
    expect(find.text('Opening amount'), findsNothing);
    expect(
      find.textContaining('This account has no opening balance'),
      findsOneWidget,
    );
  });

  testWidgets('a balance in the user\'s favour loads as "They owe me"',
      (tester) async {
    // person_balances.opening_minor is signed: positive means they owe you.
    await pumpSheet(tester, editing: person(currency: 'INR'), openingMinor: 500000);

    expect(find.textContaining('in your favour'), findsOneWidget);
    // The amount is loaded into the field rather than left for the user to
    // retype from the person page.
    expect(find.text('Opening amount'), findsOneWidget);
    expect(find.widgetWithText(TextField, '5000'), findsOneWidget);
  });

  testWidgets('a balance against the user loads as "I owe them"',
      (tester) async {
    await pumpSheet(tester, editing: person(currency: 'INR'), openingMinor: -125000);

    expect(find.textContaining('against you'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1250'), findsOneWidget);
  });

  testWidgets('the amount is stated in the ledger currency, not the new default',
      (tester) async {
    // Ahmed's history is in dirhams; his new entries default to dollars. An
    // opening balance is part of that history, so it is written in AED.
    await pumpSheet(
      tester,
      editing: person(currency: 'USD', ledgerCurrency: 'AED'),
      openingMinor: 30000,
    );

    expect(find.textContaining('AED'), findsWidgets);
  });

  testWidgets('creating still starts with no opening balance', (tester) async {
    await pumpSheet(tester);

    expect(find.text('OPENING BALANCE'), findsOneWidget);
    expect(find.text('Opening amount'), findsNothing);
  });
}
