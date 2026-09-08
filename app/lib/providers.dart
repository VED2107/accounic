import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/demo.dart';
import 'data/auth_repository.dart';
import 'data/demo_repository.dart';
import 'data/export_models.dart';
import 'data/export_repository.dart';
import 'data/ledger_repository.dart';
import 'data/models.dart';
import 'data/rates_repository.dart';
import 'data/update_repository.dart';

/// Application state wiring (context.md §20).
///
/// Riverpod, no code generation. Screens read providers; providers read
/// repositories; repositories read the RPCs. No screen touches Supabase
/// directly, and no provider does arithmetic on money.
///
/// After a mutation a screen invalidates the providers whose numbers changed —
/// the refreshed balance the RPC already returned is used for the immediate
/// update, and the invalidation reconciles everything else.

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => LedgerRepository(ref.watch(supabaseClientProvider)),
);

/// The demo's front door (data/demo_repository.dart). Present in every build;
/// reached only by a build made with --dart-define=DEMO_MODE=on.
final demoRepositoryProvider = Provider<DemoRepository>(
  (ref) => DemoRepository(ref.watch(supabaseClientProvider)),
);

final ratesRepositoryProvider = Provider<RatesRepository>(
  (ref) => RatesRepository(ref.watch(supabaseClientProvider)),
);

final exportRepositoryProvider = Provider<ExportRepository>(
  (ref) => ExportRepository(ref.watch(supabaseClientProvider)),
);

/// What an export WOULD contain, before one is generated.
///
/// The export sheet watches this as the filters change, so the user can answer
/// "what am I exporting?" from the counts rather than from the file they get
/// afterwards. It fetches only the header, never the entries.
final exportPreviewProvider =
    FutureProvider.autoDispose.family<ExportHeader, ExportFilters>((ref, filters) {
  return ref.watch(exportRepositoryProvider).header(filters);
});

/// Auth changes drive routing. Seeded with the current session so the first
/// frame after a cold start already knows whether we are signed in.
final updateRepositoryProvider = Provider<UpdateRepository>(
  (ref) => const UpdateRepository(),
);

/// The newer release, if there is one (data/update_repository.dart).
///
/// Null covers every case that is not an update: already current, ahead of the
/// newest release, no releases published, no network. None of them is an error
/// the user has to see, so this provider never carries one — a failed check is
/// simply "nothing to update to".
final appUpdateProvider = FutureProvider<AppRelease?>((ref) async {
  try {
    return await ref.watch(updateRepositoryProvider).availableUpdate();
  } catch (_) {
    return null;
  }
});

/// The demo build for the device this is running on, when there is one
/// (data/update_repository.dart, docs/demo.md).
///
/// Null covers every case that is not an offer: no release, no demo asset for
/// this platform, no network, a platform with nothing to install. None of them
/// is an error the visitor has to see, so this provider never carries one —
/// the card simply does not appear.
final demoDownloadProvider = FutureProvider<DemoDownload?>((ref) async {
  try {
    return await ref.watch(updateRepositoryProvider).demoDownload();
  } catch (_) {
    return null;
  }
});

/// The FULL build for this device, for a user whose account is real.
///
/// What a converted demo user is offered: they have the whole product now, and
/// the next useful thing is the application for the machine they are on. Null
/// whenever there is nothing to offer, which the card reads as "draw nothing".
final fullDownloadProvider = FutureProvider<DemoDownload?>((ref) async {
  try {
    return await ref.watch(updateRepositoryProvider).fullDownload();
  } catch (_) {
    return null;
  }
});

final authStateProvider = StreamProvider<AuthState?>((ref) {
  return ref.watch(authRepositoryProvider).changes;
});

final isSignedInProvider = Provider<bool>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authRepositoryProvider).isSignedIn;
});

/// The signed-in profile. Everything that needs a currency reads it from here,
/// so a currency change propagates to every screen at once.
final meProvider = FutureProvider<Me?>((ref) async {
  if (!ref.watch(isSignedInProvider)) return null;
  return ref.watch(ledgerRepositoryProvider).me();
});

/// Whether the SIGNED-IN ACCOUNT is a demo one — `profiles.is_demo` (0030).
///
/// Nothing to do with which build this is. A demo account carries this into the
/// Windows and Android applications too, which is the point: the restriction
/// belongs to the account, and it is lifted by an administrator converting the
/// account, not by the user finding a different binary.
final isDemoAccountProvider = Provider<bool>((ref) {
  return ref.watch(meProvider).valueOrNull?.isDemo ?? false;
});

/// Whether the experience in front of the user is the restricted one.
///
/// The ONLY question a feature gate should ask, and the answer belongs to the
/// ACCOUNT rather than to the binary:
///
///   * once `me` has loaded, `profiles.is_demo` decides, on every platform. A
///     demo account is restricted in the Windows build; a real account is NOT
///     restricted in the demo build.
///   * before it has loaded — and on the demo build's own door, where nobody is
///     signed in yet — the build flag stands in, so a demo deployment never
///     flashes the full product for a frame.
///
/// That second rule is the whole of what the build flag does here. It used to
/// win outright, which was wrong in the case the product cares most about: an
/// administrator converts a visitor to a real user, the visitor reloads the
/// demo they were already using, and stays locked out of the thing they were
/// just granted. Their account is real; the page they happen to be on is not a
/// reason to keep restricting them (docs/demo.md).
///
/// Restriction is presentation either way. Not one of the capabilities behind
/// these gates is enforced here — administration is refused by `is_admin()` in
/// the database, and every ledger row by RLS, whatever this provider says.
final demoRestrictedProvider = Provider<bool>((ref) {
  final me = ref.watch(meProvider).valueOrNull;
  if (me != null) return me.isDemo;
  return isDemoBuild;
});

final currencyProvider = Provider<String>((ref) {
  return ref.watch(meProvider).maybeWhen(
        data: (me) => me?.currency ?? 'INR',
        orElse: () => 'INR',
      );
});

/// The rate for one currency pair (upgrade §5).
///
/// Kept alive rather than auto-disposed: the answer is good for hours, and a
/// sheet that reopens should not pay for a second lookup. A pair with no rate
/// resolves to null, which every caller reads as "cannot convert" — never as
/// zero.
final rateProvider =
    FutureProvider.autoDispose.family<RateQuote?, ({String from, String to})>((ref, pair) {
  ref.keepAlive();
  if (pair.from.isEmpty || pair.to.isEmpty || pair.from == pair.to) {
    return Future.value(pair.from.isEmpty ? null : RateQuote.identity(pair.from));
  }
  return ref.watch(ratesRepositoryProvider).rate(pair.from, pair.to);
});

final dashboardProvider = FutureProvider.autoDispose<Dashboard>((ref) {
  // Held briefly after the last listener leaves so tab switching does not
  // re-fetch the dashboard on every visit (context.md §23).
  ref.keepAlive();
  return ref.watch(ledgerRepositoryProvider).dashboard();
});

typedef PeopleQuery = ({String query, bool includeArchived, PeopleSort sort});

final peopleProvider =
    FutureProvider.autoDispose.family<List<PersonBalance>, PeopleQuery>((ref, args) {
  return ref.watch(ledgerRepositoryProvider).people(
        query: args.query,
        includeArchived: args.includeArchived,
        sort: args.sort,
      );
});

final personPageProvider =
    FutureProvider.autoDispose.family<PersonPage, String>((ref, personId) {
  return ref.watch(ledgerRepositoryProvider).personPage(personId);
});

typedef ActivityQuery = ({int page, String? kind});

final activityProvider =
    FutureProvider.autoDispose.family<ActivityPage, ActivityQuery>((ref, args) {
  return ref.watch(ledgerRepositoryProvider).activity(page: args.page, kind: args.kind);
});

/// Thirty days of daily totals, for the activity screen's summary strip.
final activitySummaryProvider =
    FutureProvider.autoDispose<List<ActivityBucket>>((ref) {
  return ref.watch(ledgerRepositoryProvider).activitySummary();
});

final searchProvider =
    FutureProvider.autoDispose.family<SearchResults, String>((ref, query) async {
  if (query.trim().isEmpty) {
    return const SearchResults(people: [], transactions: []);
  }
  // Debounce inside the provider: while the user is still typing, each new
  // keystroke disposes this provider before the delay elapses, so the request
  // is never sent at all (context.md §15, §23).
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  await Future<void>.delayed(const Duration(milliseconds: 180));
  if (cancelled) return const SearchResults(people: [], transactions: []);

  return ref.watch(ledgerRepositoryProvider).search(query);
});

/// Administration. Guarded by `me.isAdmin` in the UI and by `is_admin()` in
/// every RPC these call, so a forced navigation shows an error, not data.
/// The account directory's arguments: what was typed, and which accounts are
/// being asked for — null for everyone, true for the demo ones, false for the
/// real ones (db/migrations/0030).
typedef AdminUsersQuery = ({String query, bool? demoOnly});

final adminUsersProvider =
    FutureProvider.autoDispose.family<AdminUserPage, AdminUsersQuery>((ref, args) async {
  // Same debounce shape as [searchProvider]: while the admin is still typing,
  // each keystroke disposes the previous provider before the delay elapses.
  if (args.query.isNotEmpty) {
    var cancelled = false;
    ref.onDispose(() => cancelled = true);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (cancelled) return const AdminUserPage(users: [], total: 0);
  }
  return ref.watch(ledgerRepositoryProvider).adminUsers(
        query: args.query,
        demoOnly: args.demoOnly,
      );
});

final systemInfoProvider = FutureProvider.autoDispose<SystemInfo>((ref) {
  return ref.watch(ledgerRepositoryProvider).systemInfo();
});

/// Called after any write. One place decides what a mutation invalidates, so no
/// screen can forget to refresh the dashboard.
void invalidateLedger(Ref ref, {String? personId}) {
  ref.invalidate(dashboardProvider);
  ref.invalidate(peopleProvider);
  ref.invalidate(activityProvider);
  if (personId != null) ref.invalidate(personPageProvider(personId));
}

extension LedgerRefresh on WidgetRef {
  void refreshLedger({String? personId}) {
    invalidate(dashboardProvider);
    invalidate(peopleProvider);
    invalidate(activityProvider);
    if (personId != null) invalidate(personPageProvider(personId));
  }
}
