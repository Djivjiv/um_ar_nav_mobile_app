import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/indoor_node_model.dart';
import '../models/indoor_edge_model.dart';
import 'repository_exception.dart';

class IndoorNavigationRepository {
  final SupabaseClient _client;
  IndoorNavigationRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final Map<String, List<IndoorNodeModel>> _nodeCache = {};
  final Map<String, List<IndoorEdgeModel>> _edgeCache = {};

  Future<List<IndoorNodeModel>> getNodesForFloor(String floorPlanId) async {
    if (_nodeCache.containsKey(floorPlanId)) return _nodeCache[floorPlanId]!;
    try {
      final rows = await _client
          .from('indoor_nodes')
          .select()
          .eq('floor_plan_id', floorPlanId);
      final nodes = (rows as List)
          .map((e) => IndoorNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();
      _nodeCache[floorPlanId] = nodes;
      return nodes;
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load indoor map: ${e.message}');
    } catch (_) {
      throw RepositoryException('Could not load indoor map.');
    }
  }

  Future<List<IndoorEdgeModel>> getEdgesForFloor(String floorPlanId) async {
    if (_edgeCache.containsKey(floorPlanId)) return _edgeCache[floorPlanId]!;
    try {
      final rows = await _client
          .from('indoor_edges')
          .select()
          .eq('floor_plan_id', floorPlanId)
          .eq('is_active', true);
      final edges = (rows as List)
          .map((e) => IndoorEdgeModel.fromMap(e as Map<String, dynamic>))
          .toList();
      _edgeCache[floorPlanId] = edges;
      return edges;
    } catch (_) {
      return const [];
    }
  }

  Future<List<IndoorNodeModel>> searchNodes(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final rows = await _client
          .from('indoor_nodes')
          .select()
          .or('room_name.ilike.%$query%,room_number.ilike.%$query%,name.ilike.%$query%')
          .limit(30);
      return (rows as List)
          .map((e) => IndoorNodeModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
