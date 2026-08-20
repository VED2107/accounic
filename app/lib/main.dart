import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'ui/app_router.dart';

/// Entry point for both Android and Windows (context.md §20).
///
/// One `main`, one widget tree, one data layer. The only thing that differs
/// between the two platforms is layout, and that is decided by width, not by
/// `Platform.isWindows` — which is also what makes a phone in landscape and a
/// small desktop window behave sensibly.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      // Sessions persist across restarts; on Android this is encrypted storage,
      // on Windows the app-data directory.
      autoRefreshToken: true,
    ),
  );

  runApp(const ProviderScope(child: LedgerApp()));
}

class LedgerApp extends StatelessWidget {
  const LedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ledger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
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
