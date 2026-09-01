import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:package_info_plus/package_info_plus.dart';

import 'core/config.dart';
import 'core/telemetry.dart';
import 'core/theme.dart';
import 'ui/app_router.dart';
import 'ui/splash/splash_gate.dart';

/// Entry point for both Android and Windows (context.md §20).
///
/// One `main`, one widget tree, one data layer. The only thing that differs
/// between the two platforms is layout, and that is decided by width, not by
/// `Platform.isWindows` — which is also what makes a phone in landscape and a
/// small desktop window behave sensibly.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Nothing fails quietly. A framework error used to reach the console only if
  // the app happened to be run attached; both hooks log with the stack, and
  // every async screen renders an ErrorNote rather than nothing (§26).
  //
  // A console nobody can read is not much use on a phone, though, which is what
  // Telemetry.installGlobalHandlers() below adds: the same two hooks also send
  // a sanitised report to the user's own database (core/telemetry.dart). It is
  // installed here, before Supabase, so a failure during startup is reported
  // too — it is simply dropped until install() has a client to send with.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousOnError?.call(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };
  Telemetry.installGlobalHandlers();

  if (!AppConfig.isConfigured) {
    runApp(const _MisconfiguredApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    // The publishable (anon) key — the only credential a client binary ever
    // holds. Everything it can do is bounded by RLS (context.md §24).
    publishableKey: AppConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      // Sessions persist across restarts. Be precise about where:
      // supabase_flutter stores them in plain SharedPreferences on Android
      // (its local_storage.dart) and in the app-data directory on Windows —
      // NOT in encrypted storage, whatever an earlier comment here claimed.
      //
      // What keeps the refresh token on the device is therefore the platform
      // sandbox plus `android:allowBackup="false"` and the extraction rules in
      // android/app/src/main/res/xml/. Moving to flutter_secure_storage would
      // add real at-rest protection and is the next step worth taking; see
      // docs/security.md.
      autoRefreshToken: true,
    ),
  );

  // Now there is somewhere to send reports. The version comes from the
  // platform's own package info, so a report names the build it came from.
  String? version;
  try {
    final info = await PackageInfo.fromPlatform();
    version = '${info.version}+${info.buildNumber}';
  } catch (_) {
    // Not fatal: a report without a version is still a report.
  }
  Telemetry.install(Supabase.instance.client, appVersion: version);

  runApp(const ProviderScope(child: AccounicApp()));
}

class AccounicApp extends StatelessWidget {
  const AccounicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Accounic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Dark is the product's face; the light scheme is there for anyone whose
      // system asks for it (docs/decisions.md).
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      // The splash is an overlay on the router, not a route in it. The router
      // resolves the auth redirect and the first screen paints underneath while
      // the sequence plays, so the handover has nothing left to load — and no
      // navigation the user performs later can ever land back on a splash.
      builder: (context, child) => _SystemBars(
        child: SplashGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Tells Android which way to draw the status and navigation bar glyphs.
///
/// Found on a real device, and invisible everywhere else: the app never set an
/// overlay style, so Android kept its default of *light* (white) glyphs. On the
/// dark scheme that is right by accident. On the light scheme — a #f6f7f9 page —
/// the clock, the battery and the signal bars are white on near-white, and the
/// top of the screen reads as broken.
///
/// The rule is the inverse of the page: a light page takes dark glyphs.
/// `statusBarBrightness` is the iOS spelling of the same idea and is set too, so
/// the one widget covers both. The bars themselves stay transparent — the app
/// draws its own ground behind them.
class _SystemBars extends StatelessWidget {
  const _SystemBars({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final glyphs = light ? Brightness.dark : Brightness.light;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: glyphs,
        statusBarBrightness: light ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: glyphs,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: child,
    );
  }
}

/// Shown when the binary was built without --dart-define values. Failing loudly
/// here beats a blank screen and a network error later (context.md §26).
class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              AppConfig.missingConfigMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6, fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
    );
  }
}
