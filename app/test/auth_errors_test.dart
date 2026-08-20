import 'package:accounic/core/failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth errors say what actually went wrong.
///
/// The regression this pins: every `AuthException` was collapsed into "That
/// email and password combination is not correct." That sentence is right for a
/// failed sign-in and misleading everywhere else — a user whose password change
/// was refused because the new password matched the old one was told their
/// email and password were wrong, which is not a thing they can act on.
///
/// Live GoTrue on this project rejects exactly two things for
/// `updateUser({password})`, verified against the real API:
///
///   422 same_password  — "New password should be different from the old password."
///   422 weak_password  — "Password should be at least 6 characters."
///
/// so `same_password` is the one that reaches a user who has already passed the
/// client's own 10-character check.
void main() {
  Failure translate(String code, {String? statusCode, String fallback = 'Fallback.'}) {
    return Failure.from(
      AuthApiException('raw gotrue text', code: code, statusCode: statusCode),
      fallback,
    );
  }

  group('auth error translation', () {
    test('a refused password change names the actual reason', () {
      final failure = translate('same_password',
          statusCode: '422', fallback: 'Your password could not be changed.');

      expect(failure.message,
          'Your new password must be different from your current one.');
      // Not the sign-in sentence, and not the useless fallback.
      expect(failure.message, isNot(contains('email')));
      expect(failure.message, isNot('Your password could not be changed.'));
    });

    test('a weak password says what would be strong enough', () {
      final failure = translate('weak_password', statusCode: '422');
      expect(failure.message, contains('at least 10 characters'));
    });

    test('sign-in stays deliberately vague about which half was wrong', () {
      // The one case that must NOT become more specific: distinguishing "no
      // such user" from "wrong password" turns the form into a way to discover
      // which email addresses have accounts.
      final failure = translate('invalid_credentials', statusCode: '400');
      expect(failure.message, 'That email and password combination is not correct.');
    });

    test('an expired session says so, with or without a code', () {
      expect(
        translate('session_not_found', statusCode: '401').message,
        contains('session has expired'),
      );
      // A bare 401 carries no code at all.
      expect(
        Failure.from(
          const AuthApiException('bad jwt', statusCode: '401'),
          'Your password could not be changed.',
        ).message,
        contains('session has expired'),
      );
    });

    test('a disabled account is told to talk to an administrator', () {
      expect(
        translate('user_banned', statusCode: '403').message,
        'This account is disabled. Contact your administrator.',
      );
    });

    test('a network failure is never reported as bad credentials', () {
      // The Android release APK shipped without android.permission.INTERNET, so
      // every request failed before it left the device. Supabase surfaces that
      // as AuthRetryableFetchException, which *extends* AuthException, so it
      // fell through to the sign-in fallback and told the user their password
      // was wrong. A request that never reached the server says nothing about
      // the credentials inside it.
      final failure = Failure.from(
        AuthRetryableFetchException(message: 'ClientException: Failed host lookup'),
        'That email and password combination is not correct.',
      );

      expect(failure.message, contains('Could not reach the server'));
      expect(failure.message, isNot(contains('not correct')));
    });

    test('an unrecognised auth code falls back rather than inventing a reason', () {
      final failure = translate('something_new_in_gotrue',
          statusCode: '400', fallback: 'Your password could not be changed.');
      expect(failure.message, 'Your password could not be changed.');
    });

    test('the raw GoTrue text is kept for the developer, never for the user', () {
      final failure = translate('same_password', statusCode: '422');
      expect(failure.message, isNot(contains('raw gotrue text')));
      expect(failure.detail, contains('raw gotrue text'));
    });
  });
}
