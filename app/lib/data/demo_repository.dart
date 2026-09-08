import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/failure.dart';

/// The demo's front door (docs/demo.md).
///
/// Three calls, none of which knows anything about accounting. Getting in is an
/// anonymous sign-in; the sample workspace is `demo_seed()`; putting it back is
/// `demo_reset()`. Both RPCs run as the caller and are built on
/// `create_person()`, `create_transaction()` and `create_settlement()`, so the
/// demo's figures come out of the same engine as a paying install's — this
/// class never sees an amount.
///
/// It is deliberately NOT a second [LedgerRepository]. Once the visitor is
/// signed in, every screen reads and writes through the ordinary one.
class DemoRepository {
  DemoRepository(this._client);

  final SupabaseClient _client;

  /// Signs the visitor in and makes sure they have something to look at.
  ///
  /// Anonymous sign-in gives each visitor their own `auth.users` row, so RLS
  /// gives each of them a private workspace — there is no shared demo account
  /// for one visitor to leave in a state the next one inherits.
  ///
  /// Seeding is idempotent and separate from the sign-in on purpose: a returning
  /// visitor whose session survived a reload keeps the ledger they were working
  /// in rather than having it silently rebuilt underneath them.
  Future<void> enter() async {
    try {
      if (_client.auth.currentSession == null) {
        await _client.auth.signInAnonymously();
      }
      await _client.rpc('demo_seed');
    } catch (error, stack) {
      throw Failure.from(error, 'The demo could not be started. Please try again.', stack);
    }
  }

  /// Retracts and rebuilds the sample workspace.
  Future<void> reset() async {
    try {
      await _client.rpc('demo_reset');
    } catch (error, stack) {
      throw Failure.from(error, 'The demo data could not be reset.', stack);
    }
  }

  /// Ends the session, so the next visit starts clean.
  Future<void> leave() async {
    try {
      await _client.auth.signOut();
    } catch (error, stack) {
      throw Failure.from(error, 'The demo could not be closed.', stack);
    }
  }
}
