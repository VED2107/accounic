import 'package:accounic/core/theme.dart';
import 'package:accounic/data/models.dart';
import 'package:accounic/providers.dart';
import 'package:accounic/ui/screens/admin_screen.dart';
import 'package:accounic/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Demo users in Administration (db/migrations/0030).
///
/// The interesting property is not that the button appears — it is that it
/// appears for exactly one kind of row. A "Convert to real user" offered on a
/// paying customer is an invitation to a mistake, and the RPC refusing it
/// afterwards is a worse experience than never offering it.
///
/// The RPC refuses it anyway. These cover the layer above.
void main() {
  const info = SystemInfo(
    usersTotal: 6,
    usersActive: 6,
    usersDemo: 2,
    admins: 1,
    peopleTotal: 12,
    transactionsTotal: 30,
    settlementsTotal: 9,
    databaseSize: '14 MB',
    serverTime: '2026-09-08T12:00:00Z',
  );

  AdminUser account({
    required String id,
    required String name,
    bool isDemo = false,
    bool isAnonymous = false,
  }) =>
      AdminUser(
        id: id,
        name: name,
        email: '$id@example.com',
        currency: 'INR',
        isAdmin: false,
        isActive: true,
        isDemo: isDemo,
        isAnonymous: isAnonymous,
        peopleCount: 5,
        transactionCount: 6,
        createdAt: '2026-09-01',
      );

  Future<void> pump(WidgetTester tester, List<AdminUser> users) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meProvider.overrideWith((ref) async => Me(
                id: 'admin',
                name: 'Admin',
                email: 'admin@example.com',
                currency: 'INR',
                isAdmin: true,
                isActive: true,
                isDemo: false,
                createdAt: '2026-08-01',
              )),
          systemInfoProvider.overrideWith((ref) async => info),
          adminUsersProvider.overrideWith(
            (ref, args) async => AdminUserPage(
              users: args.demoOnly == null
                  ? users
                  : users.where((u) => u.isDemo == args.demoOnly).toList(),
              total: users.length,
            ),
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a demo account is marked as one in the directory', (tester) async {
    await pump(tester, [
      account(id: 'demo', name: 'Demo visitor', isDemo: true),
      account(id: 'real', name: 'Real Customer'),
    ]);

    expect(find.text('Demo'), findsWidgets, reason: 'the demo row carries a badge');
    expect(find.text('Real Customer'), findsOneWidget);
  });

  testWidgets('an anonymous visitor is marked as one, distinctly', (tester) async {
    await pump(tester, [
      account(id: 'anon', name: '', isDemo: true, isAnonymous: true),
    ]);

    expect(find.text('Demo - anonymous'), findsOneWidget);
  });

  testWidgets('the summary counts demo accounts', (tester) async {
    await pump(tester, [account(id: 'demo', name: 'Demo visitor', isDemo: true)]);
    expect(find.text('active · 2 demo'), findsOneWidget);
  });

  testWidgets('Convert to real user is offered on a demo account only',
      (tester) async {
    await pump(tester, [
      account(id: 'demo', name: 'Demo visitor', isDemo: true),
    ]);

    await tester.tap(find.byTooltip('Manage account').first);
    await tester.pumpAndSettle();

    expect(find.text('Convert to real user'), findsOneWidget);
    expect(
      find.text('Keeps their account, their password and their books'),
      findsOneWidget,
      reason: 'the menu says what survives the conversion before it is chosen',
    );
  });

  testWidgets('it is never offered on a real account', (tester) async {
    await pump(tester, [account(id: 'real', name: 'Real Customer')]);

    await tester.tap(find.byTooltip('Manage account').first);
    await tester.pumpAndSettle();

    expect(
      find.text('Convert to real user'),
      findsNothing,
      reason: 'a customer must not be one misfired click from being converted',
    );
  });

  testWidgets('an anonymous visitor is shown the action, disabled, with the reason',
      (tester) async {
    await pump(tester, [
      account(id: 'anon', name: 'Anonymous', isDemo: true, isAnonymous: true),
    ]);

    await tester.tap(find.byTooltip('Manage account').first);
    await tester.pumpAndSettle();

    expect(find.text('Convert to real user'), findsOneWidget);
    expect(find.text('Anonymous visitors have no sign-in to keep'), findsOneWidget);

    final item = tester.widget<PopupMenuItem<String>>(
      find.widgetWithText(PopupMenuItem<String>, 'Convert to real user'),
    );
    expect(item.enabled, isFalse);
  });

  testWidgets('the directory can be narrowed to demo accounts', (tester) async {
    await pump(tester, [
      account(id: 'demo', name: 'Demo visitor', isDemo: true),
      account(id: 'real', name: 'Real Customer'),
    ]);

    expect(find.text('Real Customer'), findsOneWidget);

    // The segmented control sits above the list, so it is the first 'Demo' in
    // the tree; the row badges are the later ones.
    await tester.tap(find.text('Demo').first);
    await tester.pumpAndSettle();

    expect(find.text('Demo visitor'), findsOneWidget);
    expect(
      find.text('Real Customer'),
      findsNothing,
      reason: 'the filter is applied by the query, not by hiding rows',
    );
  });

  testWidgets('a non-administrator sees none of it', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meProvider.overrideWith((ref) async => Me(
                id: 'u1',
                name: 'Not an admin',
                email: 'u1@example.com',
                currency: 'INR',
                isAdmin: false,
                isActive: true,
                isDemo: false,
                createdAt: '2026-08-01',
              )),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Convert to real user'), findsNothing);
    expect(find.text('Administrator access is required'), findsOneWidget);
  });
}
