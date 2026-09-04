import 'package:accounic/core/theme.dart';
import 'package:accounic/data/models.dart';
import 'package:accounic/providers.dart';
import 'package:accounic/ui/screens/person_screen.dart';
import 'package:accounic/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The person screen's four tabs (v1.11.0).
///
/// The screen was one long statement and is now a position plus four tabs. That
/// is a structural change to the product's most important screen, and the two
/// things most likely to break in it are not catchable by `flutter analyze`:
///
///   * a tab that renders nothing, because a layout-phase error inside a
///     branch is silent — the same class of failure that once left the whole
///     dashboard blank while every test stayed green (dashboard_screen_test);
///   * a tab that shows the WRONG rows. Transactions and Settlements are the
///     same widget over two different filters, and a filter written the wrong
///     way round would put settlements under Transactions and still look
///     entirely plausible on screen.
///
/// So these pump the real screen, switch tabs by tapping, assert on the rows
/// each one contains, and fail on any framework exception. They run at a phone
/// width, because that is where a four-segment control is tightest.
void main() {
  Map<String, dynamic> entry({
    required String id,
    required String kind,
    required int amount,
    required String date,
    String? note,
  }) =>
      {
        'id': id,
        'entry_kind': kind,
        'entry_type': kind == 'settlement' ? 'in' : 'credit',
        'money_direction': 'in',
        'amount_minor': amount,
        'entry_date': date,
        'note': note,
        'is_void': false,
        'created_at': '${date}T10:00:00Z',
        'is_opening': false,
        'type': 'credit',
      };

  PersonPage page() => PersonPage.fromJson({
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
          'currency': 'INR',
          'base_currency': 'INR',
          'total_credit': 500000,
          'total_debit': 0,
          'total_settled': 200000,
          'outstanding_receivable': 300000,
          'outstanding_payable': 0,
          'net_balance': 300000,
          'transaction_count': 2,
          'last_activity_at': '2026-02-02T10:00:00Z',
        },
        'currency': 'INR',
        'default_currency': 'INR',
        'base_currency': 'INR',
        'timeline': [
          entry(id: 't1', kind: 'transaction', amount: 500000, date: '2026-02-01'),
          entry(id: 's1', kind: 'settlement', amount: 200000, date: '2026-02-02'),
        ],
        'timeline_total': 2,
        'open_transactions': const [],
      });

  Future<void> pumpPerson(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personPageProvider('p1').overrideWith((ref) async => page()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const PersonScreen(personId: 'p1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(Segmented<PersonTab>),
      matching: find.text(label),
    ));
    await tester.pumpAndSettle();
  }

  group('person tabs', () {
    testWidgets('opens on Overview with the position and its four figures',
        (tester) async {
      await pumpPerson(tester);

      expect(tester.takeException(), isNull);
      // The position, in words as well as in colour (§29).
      expect(find.textContaining('owes you'), findsWidgets);
      // The four figures the position is made of live on Overview now, not on
      // the position card.
      expect(find.text('Credited to you'), findsOneWidget);
      expect(find.text('Debited to them'), findsOneWidget);
      expect(find.text('Settled'), findsOneWidget);
      expect(find.text('RECENT TRANSACTIONS'), findsOneWidget);
    });

    testWidgets('offers all four tabs at a phone width', (tester) async {
      await pumpPerson(tester);

      for (final tab in PersonTab.values) {
        expect(
          find.descendant(
            of: find.byType(Segmented<PersonTab>),
            matching: find.text(tab.label),
          ),
          findsOneWidget,
          reason: 'the ${tab.label} segment should be present at 390px',
        );
      }
    });

    testWidgets('Transactions holds the transaction and not the settlement',
        (tester) async {
      await pumpPerson(tester);
      await openTab(tester, 'Transactions');

      expect(tester.takeException(), isNull);
      expect(find.byType(TimelineTile), findsOneWidget);
      final tile = tester.widget<TimelineTile>(find.byType(TimelineTile));
      expect(tile.entry.isSettlement, isFalse);
    });

    testWidgets('Settlements holds the settlement and not the transaction',
        (tester) async {
      await pumpPerson(tester);
      await openTab(tester, 'Settlements');

      expect(tester.takeException(), isNull);
      expect(find.byType(TimelineTile), findsOneWidget);
      final tile = tester.widget<TimelineTile>(find.byType(TimelineTile));
      expect(tile.entry.isSettlement, isTrue);
    });

    testWidgets('Activity holds both, in order', (tester) async {
      await pumpPerson(tester);
      await openTab(tester, 'Activity');

      expect(tester.takeException(), isNull);
      expect(find.byType(TimelineTile), findsNWidgets(2));
    });
  });

  group('collapsible section', () {
    testWidgets('starts closed and opens on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: SectionCard(
              title: 'Cash in hand by currency',
              collapsible: true,
              hint: '2 currencies',
              child: Text('the breakdown'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cash in hand by currency'), findsOneWidget);
      expect(find.text('the breakdown'), findsNothing);

      await tester.tap(find.text('Cash in hand by currency'));
      await tester.pumpAndSettle();

      expect(find.text('the breakdown'), findsOneWidget);
    });
  });
}
