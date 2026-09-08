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
  /// It must only ever be set on a build pointed at the isolated demo Supabase
  /// project. A demo build against production would put anonymous visitors in
  /// real workspaces, which is why the value is a build-time constant rather
  /// than anything the running app can be talked into.
  static const bool demoMode =
      String.fromEnvironment('DEMO_MODE', defaultValue: 'off') == 'on';

  /// Where the full application lives, for every call to action the demo makes
  /// (core/demo.dart).
  ///
  /// One constant, one dart-define, so the product's address is written down
  /// once. The default is the releases page, which is where an installable
  /// Accounic actually comes from today; a deployment that fronts the product
  /// with a site of its own overrides it with
  /// `--dart-define=FULL_APP_URL=https://…`.
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
