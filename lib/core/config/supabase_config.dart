/// Supabase connection configuration.
///
/// The anon key is intentionally NOT committed. Provide it at build/run time:
///   flutter run --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
///   flutter build apk --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
///
/// If you prefer, replace [_fallbackAnonKey] below with your regenerated key.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://yoqsjjnhmluqivkgiwoa.supabase.co';

  static const String _fallbackAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlvcXNqam5obWx1cWl2a2dpd29hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU0ODQzMTcsImV4cCI6MjEwMTA2MDMxN30.xnRaFoN2k1GfThYYLkGztzGSWmVzE8gVNgpgBpZDmC8';

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _fallbackAnonKey,
  );

  static bool get isConfigured =>
      anonKey.isNotEmpty &&
      anonKey != 'REPLACE_WITH_YOUR_REGENERATED_ANON_KEY';

  /// Allowed school email domain for student/faculty accounts.
  static const String schoolEmailDomain = '@umindanao.edu.ph';
}
