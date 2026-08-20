import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/auth_repository.dart';
import 'data/ledger_repository.dart';
import 'data/models.dart';

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

/// Auth changes drive routing. Seeded with the current session so the first
/// frame after a cold start already knows whether we are signed in.
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

final currencyProvider = Provider<String>((ref) {
  return ref.watch(meProvider).maybeWhen(
        data: (me) => me?.currency ?? 'INR',
        orElse: () => 'INR',
      );
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
