import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/offline_cache.dart';
import '../local/pending_write_queue.dart';
import '../models/outdoor_node_model.dart';
import '../models/outdoor_edge_model.dart';
import 'paging.dart';
import 'repository_exception.dart';

/// Loads and caches the outdoor navigation graph. Fetched once on app start;
/// offline, the last saved copy is used.
class OutdoorNavigationRepository {
  final SupabaseClient _client;
  final OfflineCache _offline;
  final PendingWriteQueue _queue;
  OutdoorNavigationRepository([
    SupabaseClient? client,
    OfflineCache? offline,
    PendingWriteQueue? queue,
  ])  : _client = client ?? Supabase.instance.client,
        _offline = offline ?? OfflineCache.instance,
        _queue = queue ?? PendingWriteQueue.instance;

  static const String nodesCacheKey = 'outdoor_nodes';
  static const String edgesCacheKey = 'outdoor_edges';

  List<OutdoorNodeModel> _nodes = const [];
  List<OutdoorEdgeModel> _edges = const [];
  bool _loaded = false;

  List<OutdoorNodeModel> get nodes => _nodes;
  List<OutdoorEdgeModel> get edges => _edges;
  bool get isLoaded => _loaded;

  Future<void> loadGraph({bool forceRefresh = false}) async {
    if (_loaded && !forceRefresh) return;
    try {
      final nodeRows = await _offline.fetch<List<dynamic>>(
        nodesCacheKey,
        () => fetchAllPages((from, to) async => await _client
            .from('outdoor_nodes')
            .select()
            .eq('is_active', true)
            .order('id')
            .range(from, to)),
      );
      final edgeRows = await _offline.fetch<List<dynamic>>(
        edgesCacheKey,
        () => fetchAllPages((from, to) async => await _client
            .from('outdoor_edges')
            .select()
            .eq('is_active', true)
            .order('id')
            .range(from, to)),
      );

      _nodes = nodeRows
          .map((e) => OutdoorNodeModel.fromMap(e as Map<String, dynamic>))
          .where((n) => n.lat != 0 && n.lng != 0)
          .toList();
      _edges = edgeRows
          .map((e) => OutdoorEdgeModel.fromMap(e as Map<String, dynamic>))
          .toList();
      _loaded = true;
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load the campus map: ${e.message}');
    } catch (_) {
      throw RepositoryException('Could not load the campus map.');
    }
  }

  /// Nearest graph node to an arbitrary point.
  OutdoorNodeModel? nearestNode(double lat, double lng) {
    OutdoorNodeModel? best;
    double bestD = double.infinity;
    for (final n in _nodes) {
      final d = (n.lat - lat) * (n.lat - lat) + (n.lng - lng) * (n.lng - lng);
      if (d < bestD) {
        bestD = d;
        best = n;
      }
    }
    return best;
  }

  /// Queues a `navigation_sessions` row (built by NavigationSessionLogger)
  /// and tries to send it. Offline, it stays queued and is sent when the
  /// connection returns. Never throws.
  Future<void> logNavigationRow(Map<String, dynamic> row) async {
    try {
      await _queue.enqueue('navigation_sessions', row);
      await _queue.flush();
    } catch (e) {
      // Non-critical analytics write; never break navigation.
      debugPrint('Navigation log not queued: $e');
    }
  }
}
