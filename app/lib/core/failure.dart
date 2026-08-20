library;

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

/// A message that is safe to put in front of a user.
class Failure implements Exception {
  const Failure(this.message);
  final String message;

  @override
  String toString() => message;

  static Failure from(Object error, String fallback) {
    if (error is Failure) return error;

    if (error is PostgrestException) {
      final code = error.code;
      if (code != null && _safeSqlStates.contains(code)) {
        if (_looksLikeOurMessage(error.message)) return Failure(error.message);
        return Failure(_fallbackBySqlState[code] ?? fallback);
      }
      if (code != null && _fallbackBySqlState.containsKey(code)) {
        return Failure(_fallbackBySqlState[code]!);
      }
      return Failure(fallback);
    }

    if (error is AuthApiException || error is AuthException) {
      return const Failure('That email and password combination is not correct.');
    }

    if (error.toString().contains('SocketException') ||
        error.toString().contains('Failed host lookup') ||
        error.toString().contains('ClientException')) {
      return const Failure(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    return Failure(fallback);
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
