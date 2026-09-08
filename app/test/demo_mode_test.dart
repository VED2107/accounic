import 'package:accounic/core/catalogue.dart';
import 'package:accounic/core/config.dart';
import 'package:accounic/core/demo.dart';
import 'package:accounic/data/models.dart';
import 'package:accounic/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Demo mode (docs/demo.md, lib/core/demo.dart, db/migrations/0030).
///
/// The demo is the same application, on the same database, behind the same RLS.
/// What separates a demo visitor from a customer is two flags, and these tests
/// are the guard on both of them — because the suite runs with no dart-defines
/// and no server, so anything that has quietly become true by default fails
/// here rather than in a release.
Me user({bool isDemo = false, bool isAdmin = false}) => Me(
      id: 'u1',
      name: 'Person',
      email: 'person@example.com',
      currency: 'INR',
      isActive: true,
      isAdmin: isAdmin,
      isDemo: isDemo,
      createdAt: '2026-08-01',
    );

/// A container with `me` resolved to [me], as every screen sees it.
ProviderContainer containerFor(Me? me) {
  final container = ProviderContainer(
    overrides: [meProvider.overrideWith((ref) async => me)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('the build flag is off unless it is asked for', () {
    test('AppConfig.demoMode defaults to false', () {
      expect(AppConfig.demoMode, isFalse);
    });

    test('isDemoBuild follows AppConfig and nothing else', () {
      expect(isDemoBuild, AppConfig.demoMode);
      expect(isDemoBuild, isFalse);
    });

    test('it does not disturb the rest of the configuration', () {
      expect(AppConfig.isConfigured, isFalse, reason: 'no dart-defines in a test run');
      expect(AppConfig.releaseRepo, 'VED2107/accounic');
      expect(AppConfig.updateCheckEnabled, isTrue);
    });
  });

  group('the account flag and the build flag are separate things', () {
    test('a demo account is restricted on a production build', () async {
      final container = containerFor(user(isDemo: true));
      await container.read(meProvider.future);

      expect(isDemoBuild, isFalse, reason: 'this is a production build');
      expect(container.read(isDemoAccountProvider), isTrue);
      expect(
        container.read(demoRestrictedProvider),
        isTrue,
        reason: 'the restriction belongs to the account, not to the binary',
      );
    });

    test('a real user on a production build is not restricted', () async {
      final container = containerFor(user());
      await container.read(meProvider.future);

      expect(container.read(isDemoAccountProvider), isFalse);
      expect(container.read(demoRestrictedProvider), isFalse);
    });

    test('an administrator is not made a demo user by being an administrator',
        () async {
      final container = containerFor(user(isAdmin: true));
      await container.read(meProvider.future);

      expect(container.read(isDemoAccountProvider), isFalse);
      expect(container.read(demoRestrictedProvider), isFalse);
    });

    test('a signed-out client is not restricted, and is not a demo account', () async {
      final container = containerFor(null);
      await container.read(meProvider.future);

      expect(container.read(isDemoAccountProvider), isFalse);
      expect(container.read(demoRestrictedProvider), isFalse);
    });

    test('conversion is what lifts the restriction', () async {
      // What `admin_convert_demo_user()` does, seen from the client: the same
      // account, one field different, and the gates open.
      final before = containerFor(user(isDemo: true));
      await before.read(meProvider.future);
      expect(before.read(demoRestrictedProvider), isTrue);

      final after = containerFor(user());
      await after.read(meProvider.future);
      expect(after.read(demoRestrictedProvider), isFalse);
    });
  });

  group('what the client reads back about an account', () {
    test('is_demo comes off me() and defaults to false when absent', () {
      final flagged = Me.fromJson(const {
        'id': 'u1',
        'name': 'Demo visitor',
        'email': 'demo@accounic.app',
        'currency': 'INR',
        'is_active': true,
        'is_admin': false,
        'is_demo': true,
        'created_at': '2026-09-01',
      });
      expect(flagged.isDemo, isTrue);

      // A client built against 0030 talking to a database that has not had it
      // applied must treat everyone as a full user rather than restricting the
      // whole installation.
      final older = Me.fromJson(const {
        'id': 'u1',
        'name': 'Someone',
        'email': 'someone@example.com',
        'currency': 'INR',
        'is_active': true,
        'is_admin': false,
        'created_at': '2026-09-01',
      });
      expect(older.isDemo, isFalse);
    });

    test('the directory carries demo and anonymous status', () {
      final row = AdminUser.fromJson(const {
        'id': 'u2',
        'name': '',
        'email': 'anon@anonymous.invalid',
        'currency': 'INR',
        'is_active': true,
        'is_admin': false,
        'is_demo': true,
        'is_anonymous': true,
        'created_at': '2026-09-01',
        'people_count': 5,
        'transaction_count': 6,
      });
      expect(row.isDemo, isTrue);
      expect(row.isAnonymous, isTrue);
    });

    test('a conversion reports what it kept', () {
      final converted = ConvertedUser.fromJson(const {
        'id': 'u1',
        'name': 'Demo visitor',
        'email': 'demo@accounic.app',
        'is_demo': false,
        'people_kept': 5,
        'transactions_kept': 6,
      });
      expect(converted.peopleKept, 5);
      expect(converted.transactionsKept, 6);
    });
  });

  group('what the demo says it holds back', () {
    test('every gated capability states what it does, not what it forbids', () {
      for (final feature in DemoFeature.values) {
        expect(feature.title, isNotEmpty);
        expect(feature.blurb, isNotEmpty);

        // The copy rule from core/demo.dart, enforced rather than remembered:
        // a gate that opens with "cannot" or "locked" reads as a wall, and the
        // demo's whole job is to leave the visitor wanting the product.
        final copy = '${feature.title} ${feature.blurb}'.toLowerCase();
        for (final word in ['locked', 'cannot', 'not allowed', 'restricted', 'upgrade']) {
          expect(copy.contains(word), isFalse, reason: '${feature.name} says "$word"');
        }
      }
    });

    test('the promises the upgrade sheet makes are the ones the screen makes', () {
      expect(kFullAccounicPromises, isNotEmpty);
      for (final promise in kFullAccounicPromises) {
        expect(promise, isNotEmpty);
      }
    });
  });

  group('the capability inventory the demo shows', () {
    test('is not empty, and every line is named', () {
      expect(kAccounicCapabilities, isNotEmpty);
      for (final group in kAccounicCapabilities) {
        expect(group.title, isNotEmpty);
        expect(group.capabilities, isNotEmpty, reason: '${group.title} is empty');
        for (final capability in group.capabilities) {
          expect(capability.label, isNotEmpty);
          expect(capability.detail, anyOf(isNull, isNotEmpty));
        }
      }
    });

    test('the totals are derived, so they cannot drift from the list', () {
      final total = kAccounicCapabilities.fold<int>(
        0,
        (sum, group) => sum + group.capabilities.length,
      );
      final inDemo = kAccounicCapabilities.fold<int>(
        0,
        (sum, group) => sum + group.capabilities.where((c) => c.inDemo).length,
      );
      expect(kCapabilityTotal, total);
      expect(kCapabilityInDemo, inDemo);
    });

    test('it is a comparison, not a paywall', () {
      // Both halves have to be non-trivial. A list where nothing is reachable
      // reads as a paywall; a list where everything is reachable is not telling
      // the visitor anything about the full product.
      expect(kCapabilityInDemo, greaterThan(20), reason: 'the demo does a lot');
      expect(
        kCapabilityTotal - kCapabilityInDemo,
        greaterThan(20),
        reason: 'and the full application does considerably more',
      );
      expect(kCapabilityInDemo, lessThan(kCapabilityTotal));
    });

    test('no group is entirely out of reach', () {
      // Every group the demo names should have at least something the visitor
      // can go and touch, except the ones that are wholly a full-product
      // concern — those are listed here by name rather than discovered, so
      // adding a third one is a decision somebody makes on purpose.
      const fullOnly = {'Reports and exports', 'Administration'};
      for (final group in kAccounicCapabilities) {
        if (fullOnly.contains(group.title)) continue;
        expect(
          group.demoCount,
          greaterThan(0),
          reason: '${group.title} has nothing the visitor can try',
        );
      }
    });
  });

  group('the full application has one address', () {
    test('it comes from configuration, over https, and is not a second copy', () {
      expect(kFullAccounicUrl, AppConfig.fullAppUrl);
      final uri = Uri.parse(kFullAccounicUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });
  });
}
