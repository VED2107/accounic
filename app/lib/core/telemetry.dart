import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


/// Production error telemetry — Flutter (milestone 1.9.0, Phase 2).
///
/// The mirror of `web/src/lib/telemetry.ts`, and the more important half: a
/// crash on a phone leaves no trace at all otherwise. Every bug since v1.0.0
/// was found by one person using the app and noticing something wrong.
///
/// WHAT A REPORT SAYS, AND WHAT IT REFUSES TO.
///
/// It answers *where did it fail and what was the user doing* — screen,
/// operation, error type, a sanitised message, the build, the platform. It must
/// never answer *what are this user's financial records*, so:
///
///   * [sanitiseMessage] strips anything money-shaped, any email address, any
///     long digit run and any id before the report leaves the device;
///   * context is a fixed set of keys and only scalars;
///   * `report_client_error()` redacts and whitelists again on arrival
///     (db/migrations/0028), because a client is a thing that can be wrong.
///
/// Reports go to the user's own database, never to a third party — an
/// accounting product's crash reports are not somebody else's to index. The one
/// call site for that is [_send]; pointing it at Sentry later changes this file
/// and nothing else.

/// The keys the server keeps. Anything else is dropped there; drop it here too.
const Set<String> kTelemetryContextKeys = {
  'screen',
  'action',
  'status_code',
  'sqlstate',
  'attempt',
  'is_offline',
  'locale',
  'theme',
  'device_class',
  'os_version',
  'flutter_version',
  'duration_ms',
  'entry_count',
};

final _email = RegExp(r'[\w.%+-]+@[\w.-]+\.[A-Za-z]{2,}');
final _money = RegExp(r'\d{1,3}(,\d{3})+(\.\d+)?|\d+\.\d{2,}');
final _longDigits = RegExp(r'\d{7,}');
final _uuid = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);
final _tokenish = RegExp(r'\b(ey[A-Za-z0-9._-]{20,}|sb[pk]_[A-Za-z0-9_-]{10,})\b');
final _whitespace = RegExp(r'\s+');

/// A message with everything private taken out of it.
///
/// Order matters: tokens first (they contain digits), then emails, then
/// anything money-shaped, then any long digit run, then ids. What survives is
/// the sentence — "Failed to settle [amount] for [email]" — which is what makes
/// a report useful without making it a leak.
String sanitiseMessage(Object? input, {int limit = 500}) {
  final raw = input == null ? 'Unknown error' : input.toString();
  final cleaned = raw
      .replaceAll(_tokenish, '[token]')
      .replaceAll(_email, '[email]')
      .replaceAll(_money, '[amount]')
      .replaceAll(_longDigits, '[number]')
      .replaceAll(_uuid, '[id]')
      .replaceAll(_whitespace, ' ')
      .trim();
  return cleaned.length <= limit ? cleaned : cleaned.substring(0, limit);
}

/// Only the whitelisted keys, only scalars, each one sanitised.
Map<String, Object?> sanitiseContext(Map<String, Object?>? context) {
  final out = <String, Object?>{};
  if (context == null) return out;
  for (final entry in context.entries) {
    if (!kTelemetryContextKeys.contains(entry.key)) continue;
    final value = entry.value;
    if (value == null) continue;
    if (value is num || value is bool) {
      out[entry.key] = value;
    } else if (value is String) {
      out[entry.key] = sanitiseMessage(value, limit: 80);
    }
  }
  return out;
}

/// A route with its parameters removed.
///
/// `/people/3f1a…` identifies a person; `/people/[id]` identifies a screen.
/// Only the second belongs in a crash report.
String? sanitiseRoute(String? route) {
  if (route == null || route.isEmpty) return null;
  final path = route.split('?').first;
  final cleaned = path
      .replaceAll(_uuid, '[id]')
      .replaceAllMapped(RegExp(r'/\d+(?=/|$)'), (_) => '/[n]');
  return cleaned.length <= 120 ? cleaned : cleaned.substring(0, 120);
}

/// What groups repeats of one fault together.
///
/// The sanitised shape of the message rather than a stack: a stack from a
/// release build is obfuscated and changes with every build, so a hundred
/// reports of one bug would read as a hundred bugs.
String telemetryFingerprint({
  required String errorType,
  required String message,
  String? operation,
}) {
  final shape = sanitiseMessage(message, limit: 120)
      .toLowerCase()
      .replaceAll(RegExp(r'\[(amount|email|number|id|token)\]'), '')
      .replaceAll(RegExp(r'[^a-z ]+'), '')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .take(6)
      .join('-');

  final platform = defaultTargetPlatform == TargetPlatform.android
      ? 'android'
      : Platform.isWindows
      ? 'windows'
      : 'flutter';

  final value = [platform, operation ?? 'unknown', errorType, shape].join(':');
  return value.length <= 64 ? value : value.substring(0, 64);
}

/// Which build this is, in the words the table expects.
String telemetryApp() {
  if (defaultTargetPlatform == TargetPlatform.android) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isIOS) return 'ios';
  return 'android';
}

/// Reporting, as the app uses it.
///
/// Never throws, never blocks anything the user is waiting on, and gives up
/// after the first failure that is not a rate limit: telemetry that can break
/// the app it is reporting on is worse than no telemetry at all.
class Telemetry {
  Telemetry._();

  static bool _sinkIsDown = false;
  static SupabaseClient? _client;

  /// The running build, read once at install time from the platform package
  /// info. Null until then, which only happens for a failure before startup
  /// finished — and a report with no version still beats no report.
  static String? _version;

  /// Wired once at startup with the app's client. Until then, reports are
  /// dropped rather than queued — a report is worth less than a crash loop.
  static void install(SupabaseClient client, {String? appVersion}) {
    _client = client;
    _version = appVersion;
    _sinkIsDown = false;
  }

  /// For tests.
  static void reset() {
    _client = null;
    _version = null;
    _sinkIsDown = false;
  }

  static Future<void> report(
    Object error, {
    StackTrace? stack,
    String? route,
    String? operation,
    Map<String, Object?>? context,
  }) async {
    final client = _client;
    if (client == null || _sinkIsDown) {
      // Still say it out loud in a debug build, where somebody is watching.
      if (kDebugMode) debugPrint('[telemetry:dropped] ${sanitiseMessage(error)}');
      return;
    }

    final errorType = sanitiseMessage(error.runtimeType.toString(), limit: 120);
    final message = sanitiseMessage(error);

    try {
      await client.rpc(
        'report_client_error',
        params: {
          'p_app': telemetryApp(),
          'p_error_type': errorType.isEmpty ? 'Error' : errorType,
          'p_message': message.isEmpty ? 'Unknown error' : message,
          'p_fingerprint': telemetryFingerprint(
            errorType: errorType,
            message: message,
            operation: operation,
          ),
          'p_app_version': _version,
          'p_environment': kDebugMode ? 'development' : 'production',
          'p_route': sanitiseRoute(route),
          'p_operation': operation,
          'p_context': sanitiseContext(context),
        },
      );
    } on PostgrestException catch (failure) {
      // A rate limit is the system working, not a broken sink (0026).
      if (failure.code != 'AC429') _sinkIsDown = true;
    } catch (_) {
      _sinkIsDown = true;
    }
  }

  /// Catches everything Flutter and Dart can throw at the top level.
  ///
  /// Both hooks are needed and they catch different things: `FlutterError`
  /// covers a build, layout or paint failure, and `PlatformDispatcher.onError`
  /// covers everything else on the zone — a future nobody awaited, an
  /// asynchronous callback, a stream with no error handler.
  static void installGlobalHandlers() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(
        report(
          details.exception,
          stack: details.stack,
          operation: 'flutter_error',
          context: {'action': details.library ?? 'framework'},
        ),
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(error, stack: stack, operation: 'uncaught'));
      // Returning true means handled: the app keeps running, and the failure
      // is now recorded somewhere a person can read it.
      return true;
    };
  }
}
