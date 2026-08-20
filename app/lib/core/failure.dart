library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error translation (context.md §26).
///
/// Mirrors `web/src/lib/errors.ts`. Two rules: never fail silently, and never
/// show the database's own words. The RPCs raise human sentences, so those pass
/// through; anything else becomes a safe fallback.

const _safeSqlStates = {'23514', '23503', '23505', 'P0002', '42501'};

const _fallbackBySqlState = {
  '23505': 'That record already exists.',
  '23503': 'A referenced record is missing.',
  '42501': 'You are not allowed to do that.',
  'P0002': 'That record could not be found.',
  '23514': 'That change is not valid.',
  '40001': 'Someone else changed this at the same time. Please try again.',
  '57014': 'That took too long. Please try again.',
};

bool _looksLikeOurMessage(String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty || trimmed.length > 200) return false;
  if (RegExp(
    r'^(new row|duplicate key|null value|invalid input|column |relation |permission denied for)',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return false;
  }
  return RegExp(r'[.!?]$').hasMatch(trimmed);
}

bool _looksLikeNetworkFailure(Object error) {
  final text = error.toString();
  return text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('ClientException') ||
      text.contains('Connection closed') ||
      text.contains('Connection refused') ||
      // Android returns this verbatim when the app holds no INTERNET permission.
      text.contains('Permission denied');
}

/// GoTrue's error codes, translated.
///
/// These were all collapsed into "That email and password combination is not
/// correct." — which is right for a failed sign-in and actively misleading
/// everywhere else. A user changing their password and being told their email
/// and password are wrong has been given a reason that cannot be acted on.
///
/// Unlike a database error, an auth error is safe to relay: it describes the
/// credential the user has just typed, not anything about another account. The
/// one deliberate exception is [invalid_credentials], which stays vague on
/// purpose so the form cannot be used to discover which addresses exist.
String _authMessage(AuthException error, String fallback) {
  // A failure to *reach* GoTrue arrives as an AuthException too —
  // `AuthRetryableFetchException` extends it — and without this it falls
  // through to the caller's fallback, which on the sign-in form is "That email
  // and password combination is not correct."
  //
  // That is how a release APK built without the INTERNET permission spent a
  // release telling the user their password was wrong. A request that never
  // left the device says nothing whatsoever about the credentials in it.
  if (error is AuthRetryableFetchException || _looksLikeNetworkFailure(error)) {
    return 'Could not reach the server. Check your connection and try again.';
  }

  switch (error.code) {
    case 'invalid_credentials':
    case 'invalid_grant':
      return 'That email and password combination is not correct.';

    // The single most common reason a password change is refused, and the one
    // the user could fix instantly if anyone told them.
    case 'same_password':
      return 'Your new password must be different from your current one.';

    case 'weak_password':
      return 'That password is too weak. Use at least 10 characters, with an '
          'uppercase letter, a lowercase letter and a number.';

    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return 'Too many attempts. Wait a minute and try again.';

    case 'session_not_found':
    case 'session_expired':
    case 'refresh_token_not_found':
    case 'refresh_token_already_used':
      return 'Your session has expired. Sign in again and retry.';

    case 'user_banned':
      return 'This account is disabled. Contact your administrator.';

    case 'email_not_confirmed':
      return 'This email address has not been confirmed yet.';

    case 'reauthentication_needed':
      return 'Sign in again before changing your password.';
  }

  // An expired or missing token arrives as a bare 401 with no code.
  if (error.statusCode == '401' || error.statusCode == '403') {
    return 'Your session has expired. Sign in again and retry.';
  }

  return fallback;
}

/// A message that is safe to put in front of a user.
///
/// The user-facing [message] is deliberately vague about the machinery. The
/// [cause] is kept alongside it so a developer can see what actually went
/// wrong: a swallowed cause is how a real RPC failure spent a session looking
/// like an empty screen (docs/decisions.md §20).
class Failure implements Exception {
  const Failure(this.message, {this.cause, this.stackTrace});

  final String message;

  /// The original error. Never shown in a release build.
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => message;

  /// A one-line technical description of [cause], for debug builds and logs.
  String? get detail {
    final error = cause;
    if (error == null) return null;
    if (error is PostgrestException) {
      return [
        if (error.code != null) 'code ${error.code}',
        error.message,
        if (error.details != null) '${error.details}',
        if (error.hint != null) 'hint: ${error.hint}',
      ].join(' · ');
    }
    return '${error.runtimeType}: $error';
  }

  static Failure from(Object error, String fallback, [StackTrace? stackTrace]) {
    if (error is Failure) return error;

    // Never silent: whatever the user is about to be told, the console gets the
    // real thing.
    assert(() {
      debugPrint('Failure.from: $error');
      if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
      return true;
    }());

    if (error is PostgrestException) {
      final code = error.code;
      if (code != null && _safeSqlStates.contains(code)) {
        if (_looksLikeOurMessage(error.message)) {
          return Failure(error.message, cause: error, stackTrace: stackTrace);
        }
        return Failure(_fallbackBySqlState[code] ?? fallback,
            cause: error, stackTrace: stackTrace);
      }
      if (code != null && _fallbackBySqlState.containsKey(code)) {
        return Failure(_fallbackBySqlState[code]!,
            cause: error, stackTrace: stackTrace);
      }
      return Failure(fallback, cause: error, stackTrace: stackTrace);
    }

    if (error is AuthException) {
      return Failure(_authMessage(error, fallback),
          cause: error, stackTrace: stackTrace);
    }

    if (_looksLikeNetworkFailure(error)) {
      return Failure(
        'Could not reach the server. Check your connection and try again.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return Failure(fallback, cause: error, stackTrace: stackTrace);
  }
}

/// Wording used when a whole operation was rolled back (context.md §26).
class Unchanged {
  const Unchanged._();
  static const settlement =
      'Settlement could not be completed. Your balance has not been changed.';
  static const transaction = 'Transaction was not saved. Please try again.';
  static const person = 'Those details could not be saved. Please try again.';
  static const profile = 'Your profile could not be saved. Please try again.';
}
