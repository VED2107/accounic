import 'package:accounic/core/theme.dart';
import 'package:accounic/data/models.dart';
import 'package:accounic/providers.dart';
import 'package:accounic/ui/screens/admin_screen.dart';
import 'package:accounic/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Administration works on a phone, not just on a desktop.
///
/// The bottom bar carries four destinations and Administration is not one of
/// them — four thumb targets plus the primary action is already the width of a
/// phone — so on Android the only way in is Profile → Administration. That
/// makes the screen easy to break on the platform nobody develops on, which is
/// what these cover.
void main() {
  const info = SystemInfo(
    usersTotal: 4,
    usersActive: 4,
    admins: 2,
    peopleTotal: 8,
    transactionsTotal: 16,
    settlementsTotal: 7,
    databaseSize: '11 MB',
    serverTime: '2026-08-20T12:00:00Z',
  );

  final users = AdminUserPage(
    users: const [
      AdminUser(
        id: 'u1',
        email: 'someone@example.com',
        name: 'Someone Else',
        currency: 'INR',
        isAdmin: false,
        isActive: true,
        peopleCount: 2,
        transactionCount: 4,
        createdAt: '2026-08-01',
      ),
    ],
    total: 1,
  );

  Future<void> pumpAdmin(
    WidgetTester tester, {
    required bool isAdmin,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          meProvider.overrideWith((ref) async => Me(
                id: 'me',
                email: 'me@example.com',
                name: 'Me',
                currency: 'INR',
                isAdmin: isAdmin,
                isActive: true,
                createdAt: '2026-08-01',
              )),
          systemInfoProvider.overrideWith((ref) async => info),
          adminUsersProvider.overrideWith((ref, query) async => users),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('administration on a phone', () {
    testWidgets('renders the stats and the account directory', (tester) async {
      await pumpAdmin(tester, isAdmin: true);

      expect(tester.takeException(), isNull);
      expect(find.text('Administration'), findsWidgets);
      expect(find.text('Accounts'), findsOneWidget);
      // The counters, laid out two-per-row at this width.
      expect(find.text('USERS'), findsOneWidget);
      expect(find.text('4/4'), findsOneWidget);
      // The one account in the directory.
      expect(find.text('Someone Else'), findsOneWidget);
    });

    testWidgets('refuses a non-admin rather than rendering an empty screen',
        (tester) async {
      await pumpAdmin(tester, isAdmin: false);

      expect(tester.takeException(), isNull);
      expect(find.text('Administrator access is required'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
    });

    testWidgets('renders on a desktop width too', (tester) async {
      await pumpAdmin(tester, isAdmin: true, size: const Size(1280, 800));

      expect(tester.takeException(), isNull);
      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('Someone Else'), findsOneWidget);
    });
  });
}
