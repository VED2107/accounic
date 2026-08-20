import 'dart:async';

import 'package:accounic/core/failure.dart';
import 'package:accounic/core/theme.dart';
import 'package:accounic/data/models.dart';
import 'package:accounic/providers.dart';
import 'package:accounic/ui/widgets/common.dart';
import 'package:accounic/ui/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dashboard rendering (regression cover for the blank body).
///
/// The screen once painted **nothing** in the data state — not a card, not the
/// empty state — while `flutter analyze` and every unit test stayed green. The
/// cause was a layout-phase error, not a build-phase one: a `Row` with
/// `CrossAxisAlignment.stretch` inside a vertical scroll view handed its
/// children an infinite height constraint, so the whole body subtree failed to
/// size and was silently skipped at paint time. A build-phase throw would have
/// shown Flutter's red error box; a layout-phase one shows a blank screen.
///
/// These tests pump the real screen at both a desktop and a phone width and
/// fail on any framework exception, which is exactly what the old suite could
/// not see: it only ever exercised the models.
///
/// They assert on the *structure* the screen promises — the net position, both
/// sides, the person, the figures — rather than on a headline string, so a copy
/// change does not read as a regression. The one thing they do pin verbatim is
/// each empty state, because an empty state that stops appearing is precisely
/// the failure this suite exists to catch.
void main() {
  const person = PersonBalance(
    personId: 'p1',
    name: 'Priya Nair',
    type: PartyType.person,
    isArchived: false,
    totalCredit: 500000,
    totalDebit: 0,
    settledIn: 0,
    settledOut: 0,
    totalSettled: 0,
    outstandingReceivable: 500000,
    outstandingPayable: 0,
    netBalance: 500000,
    transactionCount: 1,
  );

  const activity = ActivityItem(
    id: 't1',
    personId: 'p1',
    personName: 'Priya Nair',
    isSettlement: false,
    isReceivable: true,
    amountMinor: 500000,
    entryDate: '2026-08-20',
    note: 'Loan',
  );

  Dashboard dashboard({
    List<PersonBalance> people = const [person],
    List<ActivityItem> recent = const [activity],
    OwnerSummary? summary,
  }) {
    return Dashboard(
      summary: summary ??
          const OwnerSummary(
            totalReceivable: 500000,
            totalPayable: 0,
            netPosition: 500000,
            peopleWithBalance: 1,
            peopleCount: 1,
          ),
      today: const TodayTotals(credit: 0, debit: 0, settled: 0, count: 0),
      recentActivity: recent,
      peopleWithBalance: people,
      currency: 'INR',
      name: 'Vedu Chauhan',
    );
  }

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required Override override,
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [override],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const DashboardScreen(),
        ),
      ),
    );
  }

  group('dashboard body', () {
    testWidgets('renders its figures with data, on a desktop width', (tester) async {
      await pumpDashboard(
        tester,
        override: dashboardProvider.overrideWith((ref) async => dashboard()),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The greeting varies with the hour; the name in it does not.
      expect(find.textContaining('Vedu'), findsWidgets);
      expect(find.text('NET POSITION'), findsOneWidget);
      expect(find.text('Receivable'), findsOneWidget);
      expect(find.text('Payable'), findsOneWidget);
      expect(find.text('Priya Nair'), findsWidgets);
      // ₹5,000.00 recorded in minor units, shown on the receivable side.
      expect(find.textContaining('5,000'), findsWidgets);
    });

    testWidgets('renders its figures at a phone width too', (tester) async {
      await pumpDashboard(
        tester,
        override: dashboardProvider.overrideWith((ref) async => dashboard()),
        size: const Size(390, 844),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Vedu'), findsWidgets);
      expect(find.text('NET POSITION'), findsOneWidget);
    });

    testWidgets('shows the skeleton while loading, never a blank body', (tester) async {
      final completer = Completer<Dashboard>();
      await pumpDashboard(
        tester,
        override: dashboardProvider.overrideWith((ref) => completer.future),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Skeleton), findsWidgets);

      completer.complete(dashboard());
      await tester.pumpAndSettle();
      expect(find.text('NET POSITION'), findsOneWidget);
    });

    testWidgets('shows the empty state when nothing has been recorded', (tester) async {
      await pumpDashboard(
        tester,
        override: dashboardProvider.overrideWith(
          (ref) async => dashboard(
            people: const [],
            recent: const [],
            summary: const OwnerSummary(
              totalReceivable: 0,
              totalPayable: 0,
              netPosition: 0,
              peopleWithBalance: 0,
              peopleCount: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('No one is on your ledger yet'), findsOneWidget);
      expect(find.text('Your ledger is quiet'), findsOneWidget);
    });

    testWidgets('shows a retryable error, and the cause in a debug build', (tester) async {
      await pumpDashboard(
        tester,
        override: dashboardProvider.overrideWith(
          (ref) async => throw Failure(
            'Your dashboard could not be loaded.',
            cause: StateError('boom'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your dashboard could not be loaded.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      // The safe sentence is what the user reads; the cause is there for the
      // developer, which is what the silent failure cost us last time.
      expect(find.textContaining('boom'), findsOneWidget);
    });
  });
}
