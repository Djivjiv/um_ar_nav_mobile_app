import 'package:latlong2/latlong.dart';

import '../../core/config/ar_nav_config.dart';
import '../../data/models/outdoor_ar_network_model.dart';
import 'ar_route_geometry.dart';
import 'dijkstra_service.dart';

const Distance _distance = Distance();

/// The AR guidance path chosen for one trip.
class ArRoutePlan {
  final DenseRoute route;

  /// True when [route] follows the AR path network; false when it is the
  /// outdoor route's own points (6 m fill-in) because the network had no
  /// usable path.
  final bool usedNetwork;

  /// AR network node ids along [route] (empty for the fallback).
  final List<String> nodeIds;

  /// One line for the debug overlay.
  final String description;

  const ArRoutePlan({
    required this.route,
    required this.usedNetwork,
    required this.description,
    this.nodeIds = const [],
  });
}

/// Builds the AR path for a trip from the `outdoor_ar_nodes` /
/// `outdoor_ar_edges` network:
///
/// 1. start = the active AR node nearest to [routeStart] (the outdoor route's
///    first point), if within [maxStartDistanceMeters];
/// 2. targets = active AR nodes linked to [destinationBuildingId];
/// 3. Dijkstra over active edges (undirected; `weight_m`, else straight-line
///    length) to the nearest reachable target;
/// 4. the path's node positions become the dense AR route.
///
/// When any step fails — no nodes, no node near the start, no node linked to
/// the building, or the pieces aren't connected — it falls back to
/// [fallbackRoutePoints] with [ArNavConfig.fallbackPointSpacingMeters] fill-in.
ArRoutePlan planArRoute({
  required List<OutdoorArNodeModel> nodes,
  required List<OutdoorArEdgeModel> edges,
  required List<LatLng> fallbackRoutePoints,
  LatLng? routeStart,
  int? destinationBuildingId,
  double maxStartDistanceMeters = ArNavConfig.arNetworkMaxStartDistanceMeters,
}) {
  ArRoutePlan fallback(String reason) => ArRoutePlan(
        route: densifyPolyline(fallbackRoutePoints),
        usedNetwork: false,
        description: 'AR network: no path, using route points ($reason)',
      );

  final active = <String, OutdoorArNodeModel>{
    for (final n in nodes)
      if (n.isActive && n.id.isNotEmpty && n.lat != 0 && n.lng != 0) n.id: n,
  };
  if (active.isEmpty) return fallback('no AR nodes');

  final start = routeStart ??
      (fallbackRoutePoints.isNotEmpty ? fallbackRoutePoints.first : null);
  if (start == null) return fallback('no route start');
  if (destinationBuildingId == null) return fallback('destination building unknown');

  // 1. Nearest node to the start.
  OutdoorArNodeModel? startNode;
  var startGap = double.infinity;
  for (final n in active.values) {
    final d = _distance.as(LengthUnit.Meter, start, n.point);
    if (d < startGap) {
      startGap = d;
      startNode = n;
    }
  }
  if (startNode == null || startGap > maxStartDistanceMeters) {
    return fallback('no AR node within '
        '${maxStartDistanceMeters.toStringAsFixed(0)} m of the start');
  }

  // 2. Nodes linked to the destination building.
  final targets = {
    for (final n in active.values)
      if (n.buildingId == destinationBuildingId) n.id,
  };
  if (targets.isEmpty) return fallback('no AR node linked to the building');

  // 3. Dijkstra.
  final result = shortestArPath(
    nodes: active,
    edges: edges,
    fromId: startNode.id,
    targetIds: targets,
  );
  if (result == null) return fallback('start and building not connected');

  final points = [for (final id in result.nodeIds) active[id]!.point];
  if (points.length < 2) {
    // Already at the building's node — nothing to follow.
    return fallback('start is the building node');
  }
  return ArRoutePlan(
    route: DenseRoute.fromPoints(points),
    usedNetwork: true,
    nodeIds: result.nodeIds,
    description: 'AR network: ${result.nodeIds.length} nodes, '
        '${result.meters.toStringAsFixed(0)} m',
  );
}

/// Shortest path from [fromId] to the nearest of [targetIds] over the active
/// edges between [nodes] (undirected). Null when no target is reachable.
({List<String> nodeIds, double meters})? shortestArPath({
  required Map<String, OutdoorArNodeModel> nodes,
  required List<OutdoorArEdgeModel> edges,
  required String fromId,
  required Set<String> targetIds,
}) {
  if (!nodes.containsKey(fromId)) return null;

  final adjacency = <String, List<GraphEdge>>{};
  for (final e in edges) {
    if (!e.isActive) continue;
    final a = nodes[e.fromNode], b = nodes[e.toNode];
    if (a == null || b == null || a.id == b.id) continue;
    final w = (e.weightM != null && e.weightM! > 0)
        ? e.weightM!
        : _distance.as(LengthUnit.Meter, a.point, b.point);
    adjacency.putIfAbsent(a.id, () => []).add(GraphEdge(b.id, w));
    adjacency.putIfAbsent(b.id, () => []).add(GraphEdge(a.id, w));
  }

  final found = DijkstraService.search(
    start: fromId,
    adjacency: adjacency,
    targets: targetIds,
    ties: DijkstraTies.firstReached,
  );
  final end = found.reached;
  if (end == null) return null;
  return (
    nodeIds: DijkstraService.pathTo(found, fromId, end),
    meters: found.dist[end]!,
  );
}
