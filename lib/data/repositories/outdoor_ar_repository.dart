import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/offline_cache.dart';
import '../models/outdoor_ar_network_model.dart';
import 'paging.dart';
import 'repository_exception.dart';

/// The AR path network (`outdoor_ar_nodes` + `outdoor_ar_edges`).
class ArNetwork {
  final List<OutdoorArNodeModel> nodes;
  final List<OutdoorArEdgeModel> edges;
  const ArNetwork({required this.nodes, required this.edges});
}

/// Loads and caches the AR path network. Fetched once per app run, then
/// served from memory; offline, the last saved copy is used.
class OutdoorArRepository {
  final SupabaseClient _client;
  final OfflineCache _offline;
  OutdoorArRepository([SupabaseClient? client, OfflineCache? offline])
      : _client = client ?? Supabase.instance.client,
        _offline = offline ?? OfflineCache.instance;

  static const String nodesCacheKey = 'outdoor_ar_nodes';
  static const String edgesCacheKey = 'outdoor_ar_edges';

  /// Saved copy of the dropped `outdoor_ar_points` table — deleted on the
  /// next successful load.
  static const String _legacyPointsCacheKey = 'outdoor_ar_points';

  ArNetwork? _network;
  Future<ArNetwork>? _inFlight;

  /// Active nodes and edges (null / missing `is_active` counts as active).
  /// Throws [RepositoryException] when neither the server nor a saved copy
  /// is available (failures are not kept, so the next call retries).
  Future<ArNetwork> getNetwork({bool forceRefresh = false}) {
    if (!forceRefresh && _network != null) return Future.value(_network!);
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<ArNetwork> _load() async {
    try {
      final nodeRows = await _offline.fetch<List<dynamic>>(
        nodesCacheKey,
        () => fetchAllPages((from, to) async => await _client
            .from('outdoor_ar_nodes')
            .select()
            .order('id')
            .range(from, to)),
      );
      final edgeRows = await _offline.fetch<List<dynamic>>(
        edgesCacheKey,
        () => fetchAllPages((from, to) async => await _client
            .from('outdoor_ar_edges')
            .select()
            .order('id')
            .range(from, to)),
      );
      final network = ArNetwork(
        nodes: nodeRows
            .map((e) => OutdoorArNodeModel.fromMap(e as Map<String, dynamic>))
            .where((n) => n.isActive)
            .toList(),
        edges: edgeRows
            .map((e) => OutdoorArEdgeModel.fromMap(e as Map<String, dynamic>))
            .where((e) => e.isActive)
            .toList(),
      );
      _network = network;
      unawaited(_offline.remove(_legacyPointsCacheKey));
      return network;
    } on PostgrestException catch (e) {
      throw RepositoryException(
          'Could not load the AR path network: ${e.message}');
    } catch (_) {
      throw RepositoryException('Could not load the AR path network.');
    }
  }
}
