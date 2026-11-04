import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/floor_plan_image_cache.dart';
import '../local/offline_cache.dart';
import '../models/floor_plan_model.dart';
import 'repository_exception.dart';

class FloorPlanRepository {
  final SupabaseClient _client;
  final OfflineCache _offline;
  FloorPlanRepository([SupabaseClient? client, OfflineCache? offline])
      : _client = client ?? Supabase.instance.client,
        _offline = offline ?? OfflineCache.instance;

  static String buildingCacheKey(int buildingId) =>
      'building_floors:building:$buildingId';

  /// Active floors of a building. Network first; offline, the last saved
  /// copy. After a live load the floor plan images are saved to disk too.
  Future<List<FloorPlanModel>> getFloorsForBuilding(int buildingId) async {
    try {
      final read = await _offline.read<List<dynamic>>(
        buildingCacheKey(buildingId),
        () async => await _client
            .from('building_floors')
            .select()
            .eq('building_id', buildingId)
            .eq('is_active', true)
            .order('floor_number'),
      );
      final floors = read.data
          .map((e) => FloorPlanModel.fromMap(e as Map<String, dynamic>))
          .toList();
      if (!read.fromCache) {
        unawaited(FloorPlanImageCache.instance
            .prefetch(floors.map((f) => f.imageUrl)));
      }
      return floors;
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load floor plans: ${e.message}');
    } catch (_) {
      throw RepositoryException('Could not load floor plans.');
    }
  }
}
