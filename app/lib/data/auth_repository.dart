import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/failure.dart';

/// Authentication (context.md §2).
///
/// Email and password only. No social providers, no signup: an administrator
/// creates accounts in the web admin area.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get changes => _client.auth.onAuthStateChange;

  Session? get session => _client.auth.currentSession;

  bool get isSignedIn => session != null;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } catch (error) {
      // Deliberately one message for both "no such user" and "wrong password",
      // so the form cannot be used to discover which emails have accounts.
      throw Failure.from(error, 'That email and password combination is not correct.');
    }

    // A disabled account can still hold valid credentials; the database is what
    // refuses it. Check immediately and sign back out rather than showing an
    // empty workspace.
    try {
      final profile = await _client.rpc('me');
      final active = profile is Map ? profile['is_active'] as bool? ?? false : false;
      if (!active) {
        await _client.auth.signOut();
        throw const Failure(
          'This account has been disabled. Contact your administrator.',
        );
      }
    } on Failure {
      rethrow;
    } catch (error) {
      await _client.auth.signOut();
      throw Failure.from(error, 'Your account could not be verified. Please try again.');
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (error) {
      throw Failure.from(error, 'You could not be signed out.');
    }
  }

  Future<void> changePassword(String password) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } catch (error) {
      throw Failure.from(error, 'Your password could not be changed.');
    }
  }
}
