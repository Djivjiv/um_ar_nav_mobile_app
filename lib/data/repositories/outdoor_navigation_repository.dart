import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/outdoor_node_model.dart';
import '../models/outdoor_edge_model.dart';
import 'repository_exception.dart';

/// Loads and caches the outdoor navigation graph. Fetched once on app start.
class OutdoorNavigationRepository {
  final SupabaseClient _client;
  OutdoorNavigationRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  List<OutdoorNodeModel> _nodes = const [];
  List<OutdoorEdgeModel> _edges = const [];
  bool _loaded = false;

  List<OutdoorNodeModel> get nodes => _nodes;
  List<OutdoorEdgeModel> get edges => _edges;
  bool get isLoaded => _loaded;

  Future<void> loadGraph({bool forceRefresh = false}) async {
    if (_loaded && !forceRefresh) return;
    try {
      final nodeRows = await _client
          .from('outdoor_nodes')
          .select()
          .eq('is_active', true);
      final edgeRows = await _client
          .from('outdoor_edges')
          .select()
          .eq('is_active', true);

      _nodes = (nodeRows as List)
          .map((e) => OutdoorNodeModel.fromMap(e as Map<String, dynamic>))
          .where((n) => n.lat != 0 && n.lng != 0)
          .toList();
      _edges = (edgeRows as List)
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

  Future<void> logNavigationSession({
    String? userId,
    String? visitorSessionId,
    required String fromNode,
    required String toNode,
    required String fromName,
    required String toName,
    required double distanceMeters,
    int? durationSeconds,
    bool completed = false,
  }) async {
    try {
      await _client.from('navigation_sessions').insert({
        'user_id': userId,
        'visitor_session_id': visitorSessionId,
        'from_node': fromNode,
        'to_node': toNode,
        'from_name': fromName,
        'to_name': toName,
        'distance_meters': distanceMeters,
        'duration_seconds': durationSeconds,
        'completed': completed,
        'started_at': DateTime.now().toIso8601String(),
        if (completed) 'completed_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Non-critical analytics write; ignore failures.
    }
  }
}
