import 'package:collection/collection.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/outdoor_node_model.dart';
import '../../data/models/outdoor_edge_model.dart';
import '../../data/models/indoor_node_model.dart';
import '../../data/models/indoor_edge_model.dart';

/// Result of a pathfinding query.
class PathResult {
  final List<String> nodeIds;
  final List<LatLng> points;
  final double distanceMeters;

  const PathResult({
    required this.nodeIds,
    required this.points,
    required this.distanceMeters,
  });

  bool get isEmpty => nodeIds.isEmpty;
}

/// Generic Dijkstra shortest-path over the campus graph (outdoor + indoor).
class DijkstraService {
  DijkstraService._();

  static const Distance _distance = Distance();

  // ───────────────────────── Outdoor ─────────────────────────

  /// Shortest path between two outdoor nodes. Returns `null` if unreachable.
  static PathResult? findShortestPath({
    required String startNodeId,
    required String endNodeId,
    required List<OutdoorNodeModel> nodes,
    required List<OutdoorEdgeModel> edges,
  }) {
    final nodeById = {for (final n in nodes) n.id: n};
    if (!nodeById.containsKey(startNodeId) ||
        !nodeById.containsKey(endNodeId)) {
      return null;
    }

    final adjacency = _buildOutdoorAdjacency(nodes, edges, nodeById);
    final path = _dijkstra(startNodeId, {endNodeId}, adjacency);
    if (path == null) return null;

    final points = path.map((id) => nodeById[id]!.point).toList();
    return PathResult(
      nodeIds: path,
      points: points,
      distanceMeters: _routeLength(points),
    );
  }

  /// Finds the shortest path from [startNodeId] to any entrance of a building.
  static PathResult? findPathToBuilding({
    required String startNodeId,
    required dynamic buildingId,
    required List<OutdoorNodeModel> nodes,
    required List<OutdoorEdgeModel> edges,
  }) {
    final int? bId = buildingId is int
        ? buildingId
        : int.tryParse(buildingId.toString());
    if (bId == null) return null;

    final nodeById = {for (final n in nodes) n.id: n};
    if (!nodeById.containsKey(startNodeId)) return null;

    final entrances = nodes
        .where((n) =>
            n.buildingId == bId && (n.isEntrance || n.indoorNodeId != null))
        .map((n) => n.id)
        .toSet();

    // Fall back to any node that belongs to the building.
    if (entrances.isEmpty) {
      entrances.addAll(
        nodes.where((n) => n.buildingId == bId).map((n) => n.id),
      );
    }
    if (entrances.isEmpty) return null;

    final adjacency = _buildOutdoorAdjacency(nodes, edges, nodeById);
    final path = _dijkstra(startNodeId, entrances, adjacency);
    if (path == null) return null;

    final points = path.map((id) => nodeById[id]!.point).toList();
    return PathResult(
      nodeIds: path,
      points: points,
      distanceMeters: _routeLength(points),
    );
  }

  // ───────────────────────── Indoor ─────────────────────────

  static PathResult? findIndoorPath({
    required String startNodeId,
    required String endNodeId,
    required List<IndoorNodeModel> nodes,
    required List<IndoorEdgeModel> edges,
  }) {
    final nodeById = {for (final n in nodes) n.id: n};
    if (!nodeById.containsKey(startNodeId) ||
        !nodeById.containsKey(endNodeId)) {
      return null;
    }

    final adjacency = <String, List<_Edge>>{};
    void add(String from, String to, double w) {
      adjacency.putIfAbsent(from, () => []).add(_Edge(to, w));
    }

    for (final e in edges) {
      if (!e.isActive) continue;
      final a = nodeById[e.fromNode];
      final b = nodeById[e.toNode];
      if (a == null || b == null) continue;
      if (a.isNavigable == false || b.isNavigable == false) continue;
      final w = e.weight > 0
          ? e.weight
          : (a.position - b.position).distance;
      add(e.fromNode, e.toNode, w);
      if (e.isTwoWay) add(e.toNode, e.fromNode, w);
    }

    final path = _dijkstra(startNodeId, {endNodeId}, adjacency);
    if (path == null) return null;

    // Use pixel coords packed as LatLng(y, x) for the painter; distance in px.
    final points =
        path.map((id) => LatLng(nodeById[id]!.y, nodeById[id]!.x)).toList();
    double px = 0;
    for (var i = 0; i < path.length - 1; i++) {
      px += (nodeById[path[i]]!.position - nodeById[path[i + 1]]!.position)
          .distance;
    }
    return PathResult(nodeIds: path, points: points, distanceMeters: px);
  }

  // ───────────────────────── Internals ─────────────────────────

  static Map<String, List<_Edge>> _buildOutdoorAdjacency(
    List<OutdoorNodeModel> nodes,
    List<OutdoorEdgeModel> edges,
    Map<String, OutdoorNodeModel> nodeById,
  ) {
    final adjacency = <String, List<_Edge>>{};
    void add(String from, String to, double w) {
      adjacency.putIfAbsent(from, () => []).add(_Edge(to, w));
    }

    for (final e in edges) {
      if (!e.isActive) continue;
      final a = nodeById[e.fromNode];
      final b = nodeById[e.toNode];
      if (a == null || b == null) continue;
      if (!a.isActive || !b.isActive) continue;

      // Prefer stored weight; otherwise use geodesic distance in meters.
      final w =
          e.weight > 0 ? e.weight : _distance.as(LengthUnit.Meter, a.point, b.point);

      add(e.fromNode, e.toNode, w);
      if (e.isTwoWay) add(e.toNode, e.fromNode, w);
    }
    return adjacency;
  }

  /// Dijkstra from [start] to the nearest of [targets].
  static List<String>? _dijkstra(
    String start,
    Set<String> targets,
    Map<String, List<_Edge>> adjacency,
  ) {
    final dist = <String, double>{start: 0};
    final prev = <String, String>{};
    final visited = <String>{};

    final queue = PriorityQueue<_QueueItem>(
      (a, b) => a.dist.compareTo(b.dist),
    )..add(_QueueItem(start, 0));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (visited.contains(current.id)) continue;
      visited.add(current.id);

      if (targets.contains(current.id)) {
        return _reconstruct(prev, start, current.id);
      }

      for (final edge in adjacency[current.id] ?? const <_Edge>[]) {
        if (visited.contains(edge.to)) continue;
        final nd = current.dist + edge.weight;
        if (nd < (dist[edge.to] ?? double.infinity)) {
          dist[edge.to] = nd;
          prev[edge.to] = current.id;
          queue.add(_QueueItem(edge.to, nd));
        }
      }
    }
    return null;
  }

  static List<String> _reconstruct(
    Map<String, String> prev,
    String start,
    String end,
  ) {
    final path = <String>[end];
    var cur = end;
    while (cur != start) {
      final p = prev[cur];
      if (p == null) break;
      path.add(p);
      cur = p;
    }
    return path.reversed.toList();
  }

  static double _routeLength(List<LatLng> points) {
    double total = 0;
    for (var i = 0; i < points.length - 1; i++) {
      total += _distance.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
  }
}

class _Edge {
  final String to;
  final double weight;
  const _Edge(this.to, this.weight);
}

class _QueueItem {
  final String id;
  final double dist;
  const _QueueItem(this.id, this.dist);
}
