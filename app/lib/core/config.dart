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

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static const String missingConfigMessage =
      'This build has no Supabase configuration.\n\n'
      'Rebuild with:\n'
      '  --dart-define=SUPABASE_URL=…\n'
      '  --dart-define=SUPABASE_ANON_KEY=…';
}
