import 'maptiler_config.dart';
import 'supabase_config.dart';

/// The `--dart-define` names that are missing or unusable. Empty when the app
/// can start. Only names are returned, never values.
List<String> missingKeys({
  String supabaseUrl = SupabaseConfig.url,
  String supabaseAnonKey = SupabaseConfig.anonKey,
  String mapTilerKey = MapTilerConfig.apiKey,
}) {
  final url = Uri.tryParse(supabaseUrl.trim());
  final urlOk = url != null &&
      (url.scheme == 'https' || url.scheme == 'http') &&
      url.host.isNotEmpty;
  return [
    if (!urlOk) 'SUPABASE_URL',
    if (supabaseAnonKey.trim().isEmpty) 'SUPABASE_ANON_KEY',
    if (mapTilerKey.trim().isEmpty) 'MAPTILER_KEY',
  ];
}
