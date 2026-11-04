/// Supabase connection configuration, passed at run/build time (see README):
///   --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
///
/// Nothing is kept in the source. Without them the app shows
/// `SetupRequiredScreen` instead of starting.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');

  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
