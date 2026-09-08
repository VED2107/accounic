/// Build-time configuration (context.md §24).
///
/// Supplied with --dart-define so nothing lands in source control:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=your-anon-key
///
/// Only the ANON key is ever given to this app. The service-role key stays on
/// the Next.js server; a mobile or desktop binary is not a secret store.
library;

class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Where releases are published. `owner/repo`, read by the update check
  /// against the public GitHub Releases API — no update server of our own, and
  /// no version number written down anywhere: what is current is whatever the
  /// newest release says it is.
  ///
  /// Overridable with --dart-define=RELEASE_REPO=owner/repo for a fork.
  static const String releaseRepo =
      String.fromEnvironment('RELEASE_REPO', defaultValue: 'VED2107/accounic');

  /// Set --dart-define=UPDATE_CHECK=off to switch the check off entirely, for a
  /// build shipped through a store that does its own updating.
  static const bool updateCheckEnabled =
      String.fromEnvironment('UPDATE_CHECK', defaultValue: 'on') != 'off';

  /// Demo mode (docs/demo.md, core/demo.dart).
  ///
  /// `--dart-define=DEMO_MODE=on` turns the SAME binary into the hosted web
  /// demo: anonymous sign-in instead of a login form, a restricted set of
  /// reachable surfaces, and a seeded sample workspace. It changes nothing
  /// about how a figure is computed.
  ///
  /// It points at the SAME Supabase project as production — there is one
  /// database and one accounting engine (docs/demo.md). What separates a demo
  /// visitor from a customer is `profiles.is_demo` and RLS, not a second
  /// backend. This flag only decides which door the visitor arrives at, and it
  /// is a build-time constant so nothing the running app is told can change it.
  static const bool demoMode =
      String.fromEnvironment('DEMO_MODE', defaultValue: 'off') == 'on';

  /// Where the full application lives (core/demo.dart).
  ///
  /// One constant, one dart-define, so the product's address is written down
  /// once. It is what an administrator hands to a user they have just
  /// converted — NOT a self-serve download for a demo visitor. Nobody reaches
  /// the full application by following a link; they reach it because an
  /// administrator enabled their account (db/migrations/0030).
  static const String fullAppUrl = String.fromEnvironment(
    'FULL_APP_URL',
    defaultValue: 'https://github.com/VED2107/accounic/releases/latest',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const String missingConfigMessage =
      'This build has no Supabase configuration.\n\n'
      'Rebuild with:\n'
      '  --dart-define=SUPABASE_URL=…\n'
      '  --dart-define=SUPABASE_ANON_KEY=…';
}
