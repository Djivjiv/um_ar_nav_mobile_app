import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/postgrest_filter.dart';
import '../../core/utils/ttl_cache.dart';
import '../local/offline_cache.dart';
import '../models/indoor_node_model.dart';
import '../models/indoor_edge_model.dart';
import 'repository_exception.dart';

class IndoorNavigationRepository {
  final SupabaseClient _client;
  final OfflineCache _offline;

  /// How long a floor's nodes / edges are reused before being re-fetched,
  /// so admin-app edits reach a running app.
  static const Duration cacheTtl = Duration(minutes: 10);

  static const String connectionErrorMessage =
      'Could not load the indoor map. Check your connection and try again.';

  static const String nodesCachePrefix = 'indoor_nodes:floor:';
  static const String edgesCachePrefix = 'indoor_edges:floor:';
  static String nodesCacheKey(String floorPlanId) =>
      '$nodesCachePrefix$floorPlanId';
  static String edgesCacheKey(String floorPlanId) =>
      '$edgesCachePrefix$floorPlanId';

  IndoorNavigationRepository([SupabaseClient? client, OfflineCache? offline])
      : _client = client ?? Supabase.instance.client,
        _offline = offline ?? OfflineCache.instance;

  final TtlCache<String, List<IndoorNodeModel>> _nodeCache =
      TtlCache(ttl: cacheTtl);
  final TtlCache<String, List<IndoorEdgeModel>> _edgeCache =
      TtlCache(ttl: cacheTtl);

  /// Drops the in-memory floors — the next load asks the server again
  /// (falling back to the saved offline copy if it can't be reached).
  void clearCache() {
    _nodeCache.clear();
    _edgeCache.clear();
  }

  /// Active nodes from raw `indoor_nodes` rows (missing / null `is_active`
  /// counts as active). Inactive nodes never reach routing, search or the
  /// floor plan — including offline copies saved before the filter existed.
  static List<IndoorNodeModel> activeNodesFromRows(Iterable<dynamic> rows) => [
        for (final r in rows)
          if (r is Map<String, dynamic>)
            if (IndoorNodeModel.fromMap(r) case final n when n.isActive) n,
      ];

  /// Active nodes of a floor. Network first; offline, the last saved copy.
  Future<List<IndoorNodeModel>> getNodesForFloor(String floorPlanId) async {
    final cached = _nodeCache.get(floorPlanId);
    if (cached != null) return cached;
    try {
      final rows = await _offline.fetch<List<dynamic>>(
        nodesCacheKey(floorPlanId),
        () async => await _client
            .from('indoor_nodes')
            .select()
            .eq('floor_plan_id', floorPlanId),
      );
      final nodes = activeNodesFromRows(rows);
      _nodeCache.put(floorPlanId, nodes);
      return nodes;
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load indoor map: ${e.message}');
    } catch (_) {
      throw RepositoryException(connectionErrorMessage);
    }
  }

  /// Active edges for a floor. An empty list means the floor really has no
  /// edges; load failures (with no saved copy) throw [RepositoryException]
  /// instead, so callers can tell "not mapped yet" apart from "no
  /// connection".
  Future<List<IndoorEdgeModel>> getEdgesForFloor(String floorPlanId) async {
    final cached = _edgeCache.get(floorPlanId);
    if (cached != null) return cached;
    try {
      final rows = await _offline.fetch<List<dynamic>>(
        edgesCacheKey(floorPlanId),
        () async => await _client
            .from('indoor_edges')
            .select()
            .eq('floor_plan_id', floorPlanId)
            .eq('is_active', true),
      );
      final edges = rows
          .map((e) => IndoorEdgeModel.fromMap(e as Map<String, dynamic>))
          .toList();
      _edgeCache.put(floorPlanId, edges);
      return edges;
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load indoor map: ${e.message}');
    } catch (_) {
      throw RepositoryException(connectionErrorMessage);
    }
  }

  /// Active nodes whose room name / number / name contains [query].
  /// Filtered on the device (not in SQL) so a database without
  /// `is_active` still works.
  Future<List<IndoorNodeModel>> searchNodes(String query) async {
    final term = sanitizeIlikeTerm(query);
    if (term.isEmpty) return const [];
    try {
      final rows = await _client
          .from('indoor_nodes')
          .select()
          .or('room_name.ilike.%$term%,room_number.ilike.%$term%,name.ilike.%$term%')
          .limit(60)
          .timeout(_offline.networkTimeout);
      return activeNodesFromRows(rows).take(30).toList();
    } catch (_) {
      final saved = await _offline.getAll(nodesCachePrefix);
      if (saved.isEmpty) rethrow;
      final q = query.trim().toLowerCase();
      return activeNodesFromRows((await _cachedNodeRows()).where((r) =>
              ['room_name', 'room_number', 'name'].any(
                  (c) => (r[c] ?? '').toString().toLowerCase().contains(q))))
          .take(30)
          .toList();
    }
  }

  /// Whether any node in the building is labelled as an elevator.
  Future<bool> buildingHasElevator(String buildingId) async {
    try {
      final rows = await _client
          .from('indoor_nodes')
          .select()
          .eq('building_id', buildingId)
          .ilike('label', '%elevator%')
          .limit(20)
          .timeout(_offline.networkTimeout);
      return activeNodesFromRows(rows).isNotEmpty;
    } catch (_) {
      return activeNodesFromRows(await _cachedNodeRows()).any((n) =>
          n.buildingId?.toString() == buildingId &&
          (n.label ?? '').toLowerCase().contains('elevator'));
    }
  }

  /// Raw node rows of every floor saved for offline use.
  Future<List<Map<String, dynamic>>> _cachedNodeRows() async {
    final entries = await _offline.getAll(nodesCachePrefix);
    return [
      for (final e in entries.values)
        if (e.data is List) ...(e.data as List).whereType<Map<String, dynamic>>(),
    ];
  }
}
