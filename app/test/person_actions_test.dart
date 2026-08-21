import 'package:accounic/core/theme.dart';
import 'package:accounic/data/models.dart';
import 'package:accounic/ui/screens/person_screen.dart';
import 'package:accounic/ui/sheets/person_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two person-management regressions, both of which only showed on a phone.
///
/// * Delete used to be *absent* from the menu whenever the account had any
///   history. A missing item reads as a broken action, and it named no
///   alternative. It is now always listed, disabled, with the count that blocks
///   it and Archive named as the way out.
/// * The add/edit sheet put Phone and Email side by side at every width. On a
///   phone that is roughly 150px each, which is narrower than the values.
void main() {
  PersonPage page({required int transactions}) => PersonPage.fromJson({
        'person': {
          'id': 'p1',
          'owner_id': 'o1',
          'name': 'Rahul Traders',
          'type': 'business',
          'is_archived': false,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
        'balance': {
          'person_id': 'p1',
          'name': 'Rahul Traders',
          'type': 'business',
          'is_archived': false,
          'transaction_count': transactions,
        },
        'timeline': const [],
        'timeline_total': 0,
        'open_transactions': const [],
      });

  Widget host(Widget child) => ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: Center(child: child)),
        ),
      );

  group('person menu', () {
    testWidgets('offers Delete on an account with no history', (tester) async {
      await tester.pumpWidget(host(PersonMenu(page: page(transactions: 0))));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      final entry = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Delete'),
      );
      expect(entry.enabled, isTrue);
    });

    testWidgets('still lists Delete when history blocks it, and says why',
        (tester) async {
      await tester.pumpWidget(host(PersonMenu(page: page(transactions: 3))));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Delete'), findsOneWidget);
      final entry = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Delete'),
      );
      expect(entry.enabled, isFalse);
      expect(
        find.text('3 transactions on this account — archive instead'),
        findsOneWidget,
      );
    });

    testWidgets('counts one transaction in the singular', (tester) async {
      await tester.pumpWidget(host(PersonMenu(page: page(transactions: 1))));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(
        find.text('1 transaction on this account — archive instead'),
        findsOneWidget,
      );
    });
  });

  group('person sheet', () {
    Future<void> open(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: ElevatedButton(
                  onPressed: () => showPersonSheet(context, ref),
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

    testWidgets('stacks Phone and Email on a phone', (tester) async {
      await open(tester, const Size(360, 780));

      final phone = tester.getRect(find.text('Phone'));
      final email = tester.getRect(find.text('Email'));

      // Stacked, not side by side: email starts below phone, and each field has
      // the full column to itself.
      expect(email.top, greaterThan(phone.bottom));
      expect(phone.left, closeTo(email.left, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('pairs Phone and Email where the width allows', (tester) async {
      await open(tester, const Size(1200, 900));

      final phone = tester.getRect(find.text('Phone'));
      final email = tester.getRect(find.text('Email'));

      expect(email.left, greaterThan(phone.right));
      expect(phone.top, closeTo(email.top, 0.5));
      expect(tester.takeException(), isNull);
    });
  });
}
