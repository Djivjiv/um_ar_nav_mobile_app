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

/// One directed edge of a graph handed to [DijkstraService.search].
class GraphEdge {
  final String to;
  final double weight;
  const GraphEdge(this.to, this.weight);
}

/// Which of two equally distant nodes [DijkstraService.search] takes first.
/// It only matters between routes of exactly equal cost, but it decides which
/// of them is returned, so each caller keeps the rule it has always had.
enum DijkstraTies {
  /// Whatever the priority queue pops first (outdoor and indoor paths).
  queue,

  /// The node reached first (AR network).
  firstReached,

  /// The node earlier in the node list (indoor floor sweep).
  listOrder,
}

/// What one [DijkstraService.search] found.
class DijkstraSearch {
  /// Shortest distance from the start to each node reached.
  final Map<String, double> dist;

  /// The node before each reached node on its shortest path.
  final Map<String, String> prev;

  /// The target reached, or null when there was none to reach.
  final String? reached;

  const DijkstraSearch(this.dist, this.prev, this.reached);
}

/// The app's one Dijkstra ([search]) and the graphs built for it: the campus
/// graph (outdoor + indoor) here, the AR network in `ar_network_routing.dart`.
class DijkstraService {
  DijkstraService._();

  static const Distance _distance = Distance();

  /// Dijkstra from [start] over [adjacency]. Stops at the nearest of
  /// [targets], or, with no targets, sweeps every reachable node.
  /// [nodeOrder] is the list that [DijkstraTies.listOrder] follows.
  static DijkstraSearch search({
    required String start,
    required Map<String, List<GraphEdge>> adjacency,
    Set<String>? targets,
    DijkstraTies ties = DijkstraTies.queue,
    List<String> nodeOrder = const [],
  }) {
    final dist = <String, double>{start: 0};
    final prev = <String, String>{};
    final visited = <String>{};

    final rank = <String, int>{};
    if (ties == DijkstraTies.firstReached) rank[start] = 0;
    if (ties == DijkstraTies.listOrder) {
      for (final id in nodeOrder) {
        rank.putIfAbsent(id, () => rank.length);
      }
    }

    final queue = PriorityQueue<_QueueItem>((a, b) {
      final byDist = a.dist.compareTo(b.dist);
      if (byDist != 0 || ties == DijkstraTies.queue) return byDist;
      return rank[a.id]!.compareTo(rank[b.id]!);
    })
      ..add(_QueueItem(start, 0));

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (visited.contains(current.id)) continue;
      visited.add(current.id);

      if (targets != null && targets.contains(current.id)) {
        return DijkstraSearch(dist, prev, current.id);
      }

      for (final edge in adjacency[current.id] ?? const <GraphEdge>[]) {
        if (visited.contains(edge.to)) continue;
        final nd = current.dist + edge.weight;
        if (nd < (dist[edge.to] ?? double.infinity)) {
          dist[edge.to] = nd;
          prev[edge.to] = current.id;
          if (ties == DijkstraTies.firstReached) {
            rank.putIfAbsent(edge.to, () => rank.length);
          }
          queue.add(_QueueItem(edge.to, nd));
        }
      }
    }
    return DijkstraSearch(dist, prev, null);
  }

  /// The node ids from [start] to [end] in [found].
  static List<String> pathTo(DijkstraSearch found, String start, String end) {
    final path = <String>[end];
    var cur = end;
    while (cur != start) {
      final p = found.prev[cur];
      if (p == null) break;
      path.add(p);
      cur = p;
    }
    return path.reversed.toList();
  }

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
    final path = _pathToNearest(startNodeId, {endNodeId}, adjacency);
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
    final path = _pathToNearest(startNodeId, entrances, adjacency);
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

    final adjacency = _buildIndoorAdjacency(edges, nodeById);
    final path = _pathToNearest(startNodeId, {endNodeId}, adjacency);
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

  /// Sweeps a whole floor from [fromId]: the distance and predecessor of
  /// every node, so the caller can pick the nearest of several destination
  /// nodes. A node that can't be reached has an infinite distance. Null when
  /// [fromId] isn't on the floor or no edge is usable.
  static ({Map<String, double> dist, Map<String, String?> prev})?
      indoorDistances({
    required List<IndoorNodeModel> nodes,
    required List<IndoorEdgeModel> edges,
    required String fromId,
  }) {
    final nodeById = {for (final n in nodes) n.id: n};
    if (!nodeById.containsKey(fromId)) return null;

    final adjacency = _buildIndoorAdjacency(edges, nodeById);
    if (adjacency.isEmpty) return null;

    final found = search(
      start: fromId,
      adjacency: adjacency,
      ties: DijkstraTies.listOrder,
      nodeOrder: [for (final n in nodes) n.id],
    );
    return (
      dist: {
        for (final n in nodes) n.id: found.dist[n.id] ?? double.infinity,
      },
      prev: found.prev,
    );
  }

  // ───────────────────────── Internals ─────────────────────────

  static Map<String, List<GraphEdge>> _buildIndoorAdjacency(
    List<IndoorEdgeModel> edges,
    Map<String, IndoorNodeModel> nodeById,
  ) {
    final adjacency = <String, List<GraphEdge>>{};
    void add(String from, String to, double w) {
      adjacency.putIfAbsent(from, () => []).add(GraphEdge(to, w));
    }

    for (final e in edges) {
      if (!e.isActive) continue;
      final a = nodeById[e.fromNode];
      final b = nodeById[e.toNode];
      if (a == null || b == null) continue;
      if (a.isNavigable == false || b.isNavigable == false) continue;
      if (!a.isActive || !b.isActive) continue;
      final w = e.weight > 0
          ? e.weight
          : (a.position - b.position).distance;
      add(e.fromNode, e.toNode, w);
      if (e.isTwoWay) add(e.toNode, e.fromNode, w);
    }
    return adjacency;
  }

  static Map<String, List<GraphEdge>> _buildOutdoorAdjacency(
    List<OutdoorNodeModel> nodes,
    List<OutdoorEdgeModel> edges,
    Map<String, OutdoorNodeModel> nodeById,
  ) {
    final adjacency = <String, List<GraphEdge>>{};
    void add(String from, String to, double w) {
      adjacency.putIfAbsent(from, () => []).add(GraphEdge(to, w));
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

  /// The path from [start] to the nearest of [targets], or null.
  static List<String>? _pathToNearest(
    String start,
    Set<String> targets,
    Map<String, List<GraphEdge>> adjacency,
  ) {
    final found = search(start: start, adjacency: adjacency, targets: targets);
    final end = found.reached;
    return end == null ? null : pathTo(found, start, end);
  }

  static double _routeLength(List<LatLng> points) {
    double total = 0;
    for (var i = 0; i < points.length - 1; i++) {
      total += _distance.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
  }
}

class _QueueItem {
  final String id;
  final double dist;
  const _QueueItem(this.id, this.dist);
}
