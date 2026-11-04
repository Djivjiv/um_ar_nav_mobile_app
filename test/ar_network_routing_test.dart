import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_ar_network_model.dart';
import 'package:um_ar_mobile_app/domain/services/ar_network_routing.dart';

const _origin = LatLng(7.0673, 125.5951);
const _mPerDeg = 6371008.8 * math.pi / 180;
const _distance = Distance();

LatLng at(double eastM, double northM) => LatLng(
      _origin.latitude + northM / _mPerDeg,
      _origin.longitude +
          eastM / (_mPerDeg * math.cos(_origin.latitude * math.pi / 180)),
    );

double metersBetween(LatLng a, LatLng b) =>
    _distance.as(LengthUnit.Meter, a, b);

OutdoorArNodeModel node(String id, double e, double n,
    {int? building, bool active = true}) {
  final p = at(e, n);
  return OutdoorArNodeModel(
    id: id,
    lat: p.latitude,
    lng: p.longitude,
    buildingId: building,
    nodeType: building == null ? 'path' : 'building',
    isActive: active,
  );
}

OutdoorArEdgeModel edge(String from, String to,
        {double? weight, bool active = true}) =>
    OutdoorArEdgeModel(
      id: '$from-$to',
      fromNode: from,
      toNode: to,
      weightM: weight,
      isActive: active,
    );

const _noPath = 'AR network: no path, using route points';

void main() {
  // A ── B ── C ── D(building 7), plus a detour A ── E ── D.
  final a = node('A', 0, 0);
  final b = node('B', 20, 0);
  final c = node('C', 40, 0);
  final d = node('D', 60, 0, building: 7);
  final e = node('E', 30, 25);
  final nodes = [a, b, c, d, e];
  final edges = [
    edge('A', 'B'),
    edge('B', 'C'),
    edge('C', 'D'),
    edge('A', 'E'),
    edge('E', 'D'),
  ];
  // The outdoor route (fallback) from near A to the building.
  final routePoints = [at(2, -3), at(62, -3)];

  group('AR network routing', () {
    test('nearest node to the start → building node, shortest path', () {
      final plan = planArRoute(
        nodes: nodes,
        edges: edges,
        fallbackRoutePoints: routePoints,
        destinationBuildingId: 7,
      );
      expect(plan.usedNetwork, isTrue);
      expect(plan.nodeIds, ['A', 'B', 'C', 'D']);
      expect(plan.route.points, hasLength(4));
      expect(metersBetween(plan.route.points.first, a.point), lessThan(0.01));
      expect(metersBetween(plan.route.points.last, d.point), lessThan(0.01));
      expect(plan.route.totalLength, closeTo(60, 0.5));
      expect(plan.description, startsWith('AR network: 4 nodes'));
    });

    test('weight_m overrides straight-line length', () {
      final plan = planArRoute(
        nodes: nodes,
        edges: [
          edge('A', 'B'),
          edge('B', 'C', weight: 500), // e.g. stairs / a slow stretch
          edge('C', 'D'),
          edge('A', 'E'),
          edge('E', 'D'),
        ],
        fallbackRoutePoints: routePoints,
        destinationBuildingId: 7,
      );
      expect(plan.nodeIds, ['A', 'E', 'D']);
    });

    test('edges are walkable in both directions', () {
      final plan = planArRoute(
        nodes: nodes,
        edges: [edge('B', 'A'), edge('C', 'B'), edge('D', 'C')],
        fallbackRoutePoints: routePoints,
        destinationBuildingId: 7,
      );
      expect(plan.nodeIds, ['A', 'B', 'C', 'D']);
    });

    test('inactive edges and nodes are skipped', () {
      final plan = planArRoute(
        nodes: [a, node('B', 20, 0, active: false), c, d, e],
        edges: [...edges.take(4), edge('E', 'D', active: true)],
        fallbackRoutePoints: routePoints,
        destinationBuildingId: 7,
      );
      expect(plan.nodeIds, ['A', 'E', 'D']);

      final none = planArRoute(
        nodes: nodes,
        edges: [
          edge('A', 'B'),
          edge('B', 'C'),
          edge('C', 'D', active: false),
          edge('A', 'E'),
          edge('E', 'D', active: false),
        ],
        fallbackRoutePoints: routePoints,
        destinationBuildingId: 7,
      );
      expect(none.usedNetwork, isFalse);
    });

    test('several building nodes: ends at the nearest reachable one', () {
      final plan = planArRoute(
        nodes: [...nodes, node('F', 25, 0, building: 7)],
        edges: [...edges, edge('B', 'F')],
        fallbackRoutePoints: routePoints,
        destinationBuildingId: 7,
      );
      expect(plan.nodeIds, ['A', 'B', 'F']);
    });

    test('shortestArPath returns null when the target is unreachable', () {
      final r = shortestArPath(
        nodes: {for (final n in nodes) n.id: n},
        edges: [edge('A', 'B')],
        fromId: 'A',
        targetIds: {'D'},
      );
      expect(r, isNull);
    });
  });

  group('fallback to the outdoor route points (6 m fill-in)', () {
    void expectFallback(ArRoutePlan plan, String reason) {
      expect(plan.usedNetwork, isFalse);
      expect(plan.nodeIds, isEmpty);
      expect(plan.description, startsWith(_noPath));
      expect(plan.description, contains(reason));
      // The outdoor route, densified every 6 m: 60 m → 11 points.
      expect(plan.route.points, hasLength(11));
      expect(metersBetween(plan.route.points.first, routePoints.first),
          lessThan(0.01));
      expect(metersBetween(plan.route.points.last, routePoints.last),
          lessThan(0.01));
    }

    test('disconnected pieces and no building links (current live data)', () {
      // 4 separate pieces, no node linked to any building.
      final pieces = [
        node('p1', 0, 0), node('p2', 10, 0),
        node('q1', 100, 0), node('q2', 110, 0),
        node('r1', 0, 100), node('r2', 10, 100),
        node('s1', 100, 100), node('s2', 110, 100),
      ];
      final plan = planArRoute(
        nodes: pieces,
        edges: [
          edge('p1', 'p2'),
          edge('q1', 'q2'),
          edge('r1', 'r2'),
          edge('s1', 's2'),
        ],
        fallbackRoutePoints: routePoints,
        destinationBuildingId: 7,
      );
      expectFallback(plan, 'no AR node linked to the building');
    });

    test('building linked but in another piece', () {
      final plan = planArRoute(
        nodes: nodes,
        edges: [edge('A', 'B'), edge('C', 'D')],
        fallbackRoutePoints: routePoints,
        destinationBuildingId: 7,
      );
      expectFallback(plan, 'not connected');
    });

    test('no AR node near the route start', () {
      final plan = planArRoute(
        nodes: [node('far', 500, 500), node('D', 560, 500, building: 7)],
        edges: [edge('far', 'D')],
        fallbackRoutePoints: routePoints,
        destinationBuildingId: 7,
      );
      expectFallback(plan, 'no AR node within 40 m');
    });

    test('empty network (e.g. offline with nothing saved)', () {
      expectFallback(
        planArRoute(
          nodes: const [],
          edges: const [],
          fallbackRoutePoints: routePoints,
          destinationBuildingId: 7,
        ),
        'no AR nodes',
      );
    });

    test('unknown destination building', () {
      expectFallback(
        planArRoute(
          nodes: nodes,
          edges: edges,
          fallbackRoutePoints: routePoints,
        ),
        'destination building unknown',
      );
    });
  });

  group('row parsing', () {
    test('null or missing is_active counts as active; weight_m optional', () {
      final n = OutdoorArNodeModel.fromMap({
        'id': 'n1',
        'lat': 7.06,
        'lng': 125.59,
        'building_id': '12',
        'is_active': null,
      });
      expect(n.isActive, isTrue);
      expect(n.buildingId, 12);
      expect(n.nodeType, 'path');

      final e = OutdoorArEdgeModel.fromMap(
          {'id': 'e1', 'from_node': 'a', 'to_node': 'b'});
      expect(e.isActive, isTrue);
      expect(e.weightM, isNull);
      expect(
          OutdoorArEdgeModel.fromMap({'id': 'e2', 'is_active': false}).isActive,
          isFalse);
    });
  });
}
