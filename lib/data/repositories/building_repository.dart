import 'package:collection/collection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/building_model.dart';
import 'repository_exception.dart';

class BuildingRepository {
  final SupabaseClient _client;
  BuildingRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  List<BuildingModel>? _cache;

  Future<List<BuildingModel>> getBuildings({bool forceRefresh = false}) async {
    if (_cache != null && !forceRefresh) return _cache!;
    try {
      final rows = await _client
          .from('buildings')
          .select()
          .eq('is_active', true)
          .order('name');
      _cache = (rows as List)
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
      throw RepositoryException('Could not load that building.');
    }
  }
}
