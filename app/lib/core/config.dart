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

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const String missingConfigMessage =
      'This build has no Supabase configuration.\n\n'
      'Rebuild with:\n'
      '  --dart-define=SUPABASE_URL=…\n'
      '  --dart-define=SUPABASE_ANON_KEY=…';
}
