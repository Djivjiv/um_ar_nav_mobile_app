import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/offline_cache.dart';
import '../models/about_um_model.dart';

class AboutRepository {
  final SupabaseClient _client;
  final OfflineCache _offline;
  AboutRepository([SupabaseClient? client, OfflineCache? offline])
      : _client = client ?? Supabase.instance.client,
        _offline = offline ?? OfflineCache.instance;

  static const String cacheKey = 'about_um';

  /// Network first; offline, the last saved copy; else built-in content.
  Future<AboutUmModel> getAbout() async {
    try {
      final row = await _offline.fetch<Map<String, dynamic>?>(
        cacheKey,
        () async =>
            await _client.from('about_um').select().limit(1).maybeSingle(),
      );
      if (row == null) return AboutUmModel.fallback;
      return AboutUmModel.fromMap(row);
    } catch (_) {
      return AboutUmModel.fallback;
    }
  }
}
