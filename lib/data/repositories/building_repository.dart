import 'package:collection/collection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/offline_cache.dart';
import '../models/building_model.dart';
import 'repository_exception.dart';

class BuildingRepository {
  final SupabaseClient _client;
  final OfflineCache _offline;
  BuildingRepository([SupabaseClient? client, OfflineCache? offline])
      : _client = client ?? Supabase.instance.client,
        _offline = offline ?? OfflineCache.instance;

  static const String cacheKey = 'buildings';

  List<BuildingModel>? _cache;

  /// Active buildings. Network first; offline, the last saved copy.
  Future<List<BuildingModel>> getBuildings({bool forceRefresh = false}) async {
    if (_cache != null && !forceRefresh) return _cache!;
    try {
      final rows = await _offline.fetch<List<dynamic>>(
        cacheKey,
        () async => await _client
            .from('buildings')
            .select()
            .eq('is_active', true)
            .order('name'),
      );
      _cache = rows
          .map((e) => BuildingModel.fromMap(e as Map<String, dynamic>))
          .where((b) => b.lat != 0 && b.lng != 0)
          .toList();
      return _cache!;
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load buildings: ${e.message}');
    } catch (_) {
      throw RepositoryException('Could not load buildings.');
    }
  }

  Future<BuildingModel?> getBuildingById(int id) async {
    final cached = _cache?.firstWhereOrNull((b) => b.id == id);
    if (cached != null) return cached;
    try {
      final row =
          await _client.from('buildings').select().eq('id', id).maybeSingle();
      return row == null ? null : BuildingModel.fromMap(row);
    } catch (_) {
      // Offline: look in the saved building list.
      try {
        final all = await getBuildings();
        final hit = all.firstWhereOrNull((b) => b.id == id);
        if (hit != null) return hit;
      } catch (_) {}
      throw RepositoryException('Could not load that building.');
    }
  }
}
