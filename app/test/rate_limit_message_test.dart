import 'package:accounic/core/failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Being refused for writing too fast (Phase 9).
///
/// A rate limit the user cannot understand is indistinguishable from the app
/// being broken. The database raises SQLSTATE AC429 with a sentence that says
/// what happened, what to do, and — the part that matters on a form with a
/// half-typed amount in it — that nothing was saved. These pin that the
/// sentence survives the translation layer intact.
void main() {
  group('a rate-limit refusal reaches the user in words', () {
    test('the database sentence passes through unchanged', () {
      final failure = Failure.from(
        const PostgrestException(
          message: 'Too many transactions in a short time. Wait a moment and '
              'try again — nothing has been saved.',
          code: 'AC429',
        ),
        'The transaction could not be saved.',
      );

      expect(failure.message, startsWith('Too many transactions'));
      expect(failure.message, contains('nothing has been saved'));
    });

    test('and a bare code still becomes something a person can read', () {
      final failure = Failure.from(
        const PostgrestException(message: 'AC429', code: 'AC429'),
        'The transaction could not be saved.',
      );

      expect(failure.message, contains('Too many changes'));
      expect(failure.message, contains('nothing has been saved'));
    });

    test('it never shows the caller a raw SQLSTATE', () {
      final failure = Failure.from(
        const PostgrestException(message: 'AC429', code: 'AC429'),
        'The transaction could not be saved.',
      );

      expect(failure.message.contains('AC429'), isFalse);
    });
  });
}
