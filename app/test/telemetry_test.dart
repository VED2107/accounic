import 'package:accounic/core/telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a crash report is allowed to say (Phase 2).
///
/// The mirror of web/src/lib/telemetry.test.ts. A report has to answer "where
/// did it fail and what was the user doing" without answering "what are this
/// user's financial records". Every case here is a way the second could leak
/// through the first.
void main() {
  group('sanitiseMessage', () {
    test('keeps the sentence', () {
      expect(sanitiseMessage('Failed to load the dashboard'),
          'Failed to load the dashboard');
    });

    test('strips anything money-shaped', () {
      expect(sanitiseMessage('Could not settle 12,500.00'), 'Could not settle [amount]');
      expect(sanitiseMessage('balance 1234.56 remains'), 'balance [amount] remains');
    });

    test('strips an email address', () {
      expect(sanitiseMessage('rejected for rahul.kumar@example.com'),
          'rejected for [email]');
    });

    test('strips a phone number and any long digit run', () {
      expect(sanitiseMessage('called +919812345678'), 'called +[number]');
    });

    test('strips an entry or person id', () {
      expect(
        sanitiseMessage('person 3f1a2b4c-5d6e-4f70-8901-abcdef123456 missing'),
        'person [id] missing',
      );
    });

    test('strips anything token-shaped', () {
      expect(
        sanitiseMessage('Authorization failed: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9abcdef'),
        'Authorization failed: [token]',
      );
    });

    test('takes an exception as readily as a string', () {
      expect(sanitiseMessage(Exception('boom 4,000.00')), contains('[amount]'));
    });

    test('never grows without limit', () {
      expect(sanitiseMessage('x' * 900).length, 500);
    });
  });

  group('sanitiseContext', () {
    test('keeps the whitelisted keys, and only scalars', () {
      expect(
        sanitiseContext({
          'screen': 'dashboard',
          'status_code': 500,
          'is_offline': true,
          'attempt': 2,
        }),
        {'screen': 'dashboard', 'status_code': 500, 'is_offline': true, 'attempt': 2},
      );
    });

    test('drops everything else, whatever it is called', () {
      expect(
        sanitiseContext({
          'amount_minor': 1250000,
          'person_name': 'Rahul Kumar',
          'note': 'rent for August',
          'access_token': 'secret',
        }),
        isEmpty,
      );
    });

    test('sanitises the values it does keep', () {
      expect(sanitiseContext({'screen': 'settle 12,500.00'}), {
        'screen': 'settle [amount]',
      });
    });

    test('skips null rather than sending it', () {
      expect(sanitiseContext({'screen': null}), isEmpty);
    });

    test('the whitelist is the same one the server keeps', () {
      // db/migrations/0028 lists these; a key here that is not there would be
      // dropped silently, and a key there that is not here would never be sent.
      expect(kTelemetryContextKeys, contains('screen'));
      expect(kTelemetryContextKeys, contains('sqlstate'));
      expect(kTelemetryContextKeys, isNot(contains('note')));
      expect(kTelemetryContextKeys, isNot(contains('amount_minor')));
    });
  });

  group('sanitiseRoute', () {
    test('keeps the screen and loses the person', () {
      expect(
        sanitiseRoute('/people/3f1a2b4c-5d6e-4f70-8901-abcdef123456'),
        '/people/[id]',
      );
    });

    test('drops the query string, where filters and search terms live', () {
      expect(sanitiseRoute('/activity?q=rahul&from=2026-01-01'), '/activity');
    });

    test('passes a plain route through', () {
      expect(sanitiseRoute('/profile'), '/profile');
      expect(sanitiseRoute(null), isNull);
    });
  });

  group('telemetryFingerprint', () {
    test('is the same for two occurrences of one fault', () {
      final a = telemetryFingerprint(
        errorType: 'PostgrestException',
        message: 'Failed to settle 12,500.00 for rahul@example.com',
        operation: 'create_settlement',
      );
      final b = telemetryFingerprint(
        errorType: 'PostgrestException',
        message: 'Failed to settle 300.00 for priya@example.com',
        operation: 'create_settlement',
      );

      expect(a, b);
    });

    test('differs for a different fault', () {
      expect(
        telemetryFingerprint(
          errorType: 'PostgrestException',
          message: 'Failed to settle',
          operation: 'create_settlement',
        ),
        isNot(telemetryFingerprint(
          errorType: 'StateError',
          message: 'Bad state: no element',
          operation: 'load_dashboard',
        )),
      );
    });

    test('carries nothing private itself', () {
      final value = telemetryFingerprint(
        errorType: 'Error',
        message: 'settle 12,500.00 for rahul@example.com on +919812345678',
        operation: 'create_settlement',
      );

      expect(RegExp(r'\d{3,}|@').hasMatch(value), isFalse);
      expect(value.length, lessThanOrEqualTo(64));
    });
  });

  group('the reporter itself', () {
    setUp(Telemetry.reset);

    test('drops a report rather than throwing when nothing is installed', () async {
      // A crash before startup finishes must not become a second crash.
      await expectLater(
        Telemetry.report(Exception('early failure'), operation: 'startup'),
        completes,
      );
    });

    test('names the platform the table accepts', () {
      expect(
        ['android', 'windows', 'macos', 'linux', 'ios'],
        contains(telemetryApp()),
      );
    });
  });
}
