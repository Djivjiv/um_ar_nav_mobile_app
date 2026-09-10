import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/floor_plan_model.dart';
import 'repository_exception.dart';

class FloorPlanRepository {
  final SupabaseClient _client;
  FloorPlanRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  Future<List<FloorPlanModel>> getFloorsForBuilding(int buildingId) async {
    try {
      final rows = await _client
          .from('building_floors')
          .select()
          .eq('building_id', buildingId)
          .eq('is_active', true)
          .order('floor_number');
      return (rows as List)
          .map((e) => FloorPlanModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load floor plans: ${e.message}');
    } catch (_) {
      throw RepositoryException('Could not load floor plans.');
    }
  }

  Future<FloorPlanModel?> getFloorPlanById(dynamic floorPlanId) async {
    try {
      final row = await _client
          .from('building_floors')
          .select()
          .eq('id', floorPlanId)
          .maybeSingle();
      return row == null ? null : FloorPlanModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }
}
