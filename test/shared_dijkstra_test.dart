import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/data/models/indoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/indoor_node_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_ar_network_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_node_model.dart';
import 'package:um_ar_mobile_app/domain/services/ar_network_routing.dart';
import 'package:um_ar_mobile_app/domain/services/dijkstra_service.dart';

// ── The three implementations the app had before they were merged, kept
// verbatim as the reference the shared one must match, equal-cost ties
// included. Only their graph input was reduced to `adjacency`.

typedef LegacyEdge = ({String to, double w});

/// Was `DijkstraService._dijkstra` (outdoor and indoor paths).
List<String>? legacyQueue(
    String start, Set<String> targets, Map<String, List<LegacyEdge>> adjacency) {
  final dist = <String, double>{start: 0};
  final prev = <String, String>{};
  final visited = <String>{};
  final queue =
      PriorityQueue<(String, double)>((a, b) => a.$2.compareTo(b.$2))
        ..add((start, 0));
  while (queue.isNotEmpty) {
    final (id, d) = queue.removeFirst();
    if (visited.contains(id)) continue;
    visited.add(id);
    if (targets.contains(id)) {
      final path = <String>[id];
      var cur = id;
      while (cur != start) {
        final p = prev[cur];
        if (p == null) break;
        path.add(p);
        cur = p;
      }
      return path.reversed.toList();
    }
    for (final edge in adjacency[id] ?? const <LegacyEdge>[]) {
      if (visited.contains(edge.to)) continue;
      final nd = d + edge.w;
      if (nd < (dist[edge.to] ?? double.infinity)) {
        dist[edge.to] = nd;
        prev[edge.to] = id;
        queue.add((edge.to, nd));
      }
    }
  }
  return null;
}

/// Was the loop in `shortestArPath` (AR network).
({List<String> nodeIds, double meters})? legacyArScan(String fromId,
    Set<String> targetIds, Map<String, List<LegacyEdge>> adjacency) {
  final dist = <String, double>{fromId: 0};
  final prev = <String, String>{};
  final done = <String>{};
  while (true) {
    String? current;
    var best = double.infinity;
    dist.forEach((id, d) {
      if (!done.contains(id) && d < best) {
        best = d;
        current = id;
      }
    });
    final cur = current;
    if (cur == null) return null;
    if (targetIds.contains(cur)) {
      final path = <String>[cur];
      var step = cur;
      while (prev.containsKey(step)) {
        step = prev[step]!;
        path.insert(0, step);
      }
      return (nodeIds: path, meters: best);
    }
    done.add(cur);
    for (final edge in adjacency[cur] ?? const <LegacyEdge>[]) {
      if (done.contains(edge.to)) continue;
      final nd = best + edge.w;
      if (nd < (dist[edge.to] ?? double.infinity)) {
        dist[edge.to] = nd;
        prev[edge.to] = cur;
      }
    }
  }
}

/// Was the loop in `_MultiPhaseNavScreenState._indoorDijkstra` (floor sweep).
({Map<String, double> dist, Map<String, String?> prev}) legacyFloorSweep(
    String fromId,
    List<String> nodeIds,
    Map<String, List<LegacyEdge>> adjacency) {
  final dist = <String, double>{
    for (final id in nodeIds) id: double.infinity,
  };
  final prev = <String, String?>{};
  dist[fromId] = 0;
  final unvisited = Set<String>.from(nodeIds);
  while (unvisited.isNotEmpty) {
    String? current;
    var minDist = double.infinity;
    for (final id in unvisited) {
      final d = dist[id]!;
      if (d < minDist) {
        minDist = d;
        current = id;
      }
    }
    if (current == null || minDist == double.infinity) break;
    unvisited.remove(current);
    for (final edge in adjacency[current] ?? const <LegacyEdge>[]) {
      if (!unvisited.contains(edge.to)) continue;
      final nd = minDist + edge.w;
      if (nd < dist[edge.to]!) {
        dist[edge.to] = nd;
        prev[edge.to] = current;
      }
    }
  }
  return (dist: dist, prev: prev);
}

// ── One graph, in each caller's own models. ──

class TestGraph {
  final List<String> ids;
  final List<({String a, String b, double w, bool twoWay, bool active})> edges;
  TestGraph(this.ids, this.edges);

  /// Small whole weights, so equal-cost routes are common.
  factory TestGraph.random(Random r, {required bool allTwoWay}) {
    final size = 4 + r.nextInt(14);
    final ids = [for (var i = 0; i < size; i++) 'n$i']..shuffle(r);
    return TestGraph(ids, [
      for (var i = 0; i < ids.length * 3; i++)
        (
          a: ids[r.nextInt(ids.length)],
          b: ids[r.nextInt(ids.length)],
          w: 1.0 + r.nextInt(4),
          twoWay: allTwoWay || r.nextBool(),
          active: r.nextInt(8) != 0,
        ),
    ]);
  }

  /// The adjacency the callers built, in their edge order.
  Map<String, List<LegacyEdge>> adjacency({bool skipLoops = false}) {
    final out = <String, List<LegacyEdge>>{};
    for (final e in edges) {
      if (!e.active || (skipLoops && e.a == e.b)) continue;
      out.putIfAbsent(e.a, () => []).add((to: e.b, w: e.w));
      if (e.twoWay) out.putIfAbsent(e.b, () => []).add((to: e.a, w: e.w));
    }
    return out;
  }

  List<OutdoorNodeModel> get outdoorNodes => [
        for (final (i, id) in ids.indexed)
          OutdoorNodeModel(id: id, lat: 7 + i / 1000, lng: 125),
      ];

  List<OutdoorEdgeModel> get outdoorEdges => [
        for (final (i, e) in edges.indexed)
          OutdoorEdgeModel(
            id: 'e$i',
            fromNode: e.a,
            toNode: e.b,
            weight: e.w,
            isTwoWay: e.twoWay,
            isActive: e.active,
          ),
      ];

  List<IndoorNodeModel> get indoorNodes => [
        for (final (i, id) in ids.indexed)
          IndoorNodeModel(
            id: id,
            floorPlanId: '10',
            buildingId: 1,
            x: i * 10.0,
            y: 0,
            floor: 1,
          ),
      ];

  List<IndoorEdgeModel> get indoorEdges => [
        for (final (i, e) in edges.indexed)
          IndoorEdgeModel(
            id: 'e$i',
            fromNode: e.a,
            toNode: e.b,
            weight: e.w,
            isTwoWay: e.twoWay,
            isActive: e.active,
          ),
      ];

  Map<String, OutdoorArNodeModel> get arNodes => {
        for (final (i, id) in ids.indexed)
          id: OutdoorArNodeModel(id: id, lat: 7 + i / 1000, lng: 125),
      };

  List<OutdoorArEdgeModel> get arEdges => [
        for (final (i, e) in edges.indexed)
          OutdoorArEdgeModel(
            id: 'e$i',
            fromNode: e.a,
            toNode: e.b,
            weightM: e.w,
            isActive: e.active,
          ),
      ];
}

/// Enough graphs to meet plenty of equal-cost routes, always the same ones.
const graphCount = 400;

void main() {
  group('the shared Dijkstra', () {
    test('finds the cheaper of two routes', () {
      final found = DijkstraService.search(
        start: 'a',
        adjacency: const {
          'a': [GraphEdge('b', 1), GraphEdge('c', 5)],
          'b': [GraphEdge('c', 1)],
        },
        targets: {'c'},
      );
      expect(found.reached, 'c');
      expect(found.dist['c'], 2);
      expect(DijkstraService.pathTo(found, 'a', 'c'), ['a', 'b', 'c']);
    });

    test('stops at the nearest of several targets', () {
      final found = DijkstraService.search(
        start: 'a',
        adjacency: const {
          'a': [GraphEdge('far', 9), GraphEdge('near', 2)],
        },
        targets: {'far', 'near'},
      );
      expect(found.reached, 'near');
    });

    test('no target reachable → nothing reached', () {
      final found = DijkstraService.search(
        start: 'a',
        adjacency: const {
          'a': [GraphEdge('b', 1)],
        },
        targets: {'z'},
      );
      expect(found.reached, isNull);
    });

    test('with no targets it sweeps every reachable node', () {
      final found = DijkstraService.search(
        start: 'a',
        adjacency: const {
          'a': [GraphEdge('b', 1)],
          'b': [GraphEdge('c', 1)],
        },
      );
      expect(found.dist, {'a': 0, 'b': 1, 'c': 2});
      expect(found.reached, isNull);
    });

    test('a start that is a target is reached at once', () {
      final found = DijkstraService.search(
          start: 'a', adjacency: const {}, targets: {'a'});
      expect(DijkstraService.pathTo(found, 'a', 'a'), ['a']);
    });

    test('the tie rule picks between two equal routes', () {
      const adjacency = {
        'a': [GraphEdge('y', 1), GraphEdge('x', 1)],
        'y': [GraphEdge('z', 1)],
        'x': [GraphEdge('z', 1)],
      };
      final reachedFirst = DijkstraService.search(
        start: 'a',
        adjacency: adjacency,
        ties: DijkstraTies.firstReached,
      );
      expect(reachedFirst.prev['z'], 'y');

      final listed = DijkstraService.search(
        start: 'a',
        adjacency: adjacency,
        ties: DijkstraTies.listOrder,
        nodeOrder: const ['a', 'x', 'y', 'z'],
      );
      expect(listed.prev['z'], 'x');
    });
  });

  group('each caller matches the code it replaced', () {
    test('the graphs below do contain equal-cost routes', () {
      // Without ties these comparisons would prove nothing about tie-breaking.
      var routesThatTie = 0;
      final r = Random(1);
      for (var i = 0; i < graphCount; i++) {
        final g = TestGraph.random(r, allTwoWay: false);
        final a = g.adjacency();
        final sweep = legacyFloorSweep(g.ids.first, g.ids, a);
        for (final id in g.ids) {
          final viaOne = [
            for (final e in a.entries)
              for (final edge in e.value)
                if (edge.to == id &&
                    (sweep.dist[e.key]! + edge.w) == sweep.dist[id])
                  e.key,
          ];
          if (viaOne.toSet().length > 1) routesThatTie++;
        }
      }
      expect(routesThatTie, greaterThan(400));
    });

    test('outdoor: findShortestPath', () {
      final r = Random(2);
      for (var i = 0; i < graphCount; i++) {
        final g = TestGraph.random(r, allTwoWay: false);
        for (final end in g.ids) {
          final path = DijkstraService.findShortestPath(
            startNodeId: g.ids.first,
            endNodeId: end,
            nodes: g.outdoorNodes,
            edges: g.outdoorEdges,
          );
          expect(path?.nodeIds, legacyQueue(g.ids.first, {end}, g.adjacency()));
        }
      }
    });

    test('outdoor: findPathToBuilding, the nearest of several entrances', () {
      final r = Random(3);
      for (var i = 0; i < graphCount; i++) {
        final g = TestGraph.random(r, allTwoWay: false);
        final doors = g.ids.skip(1).take(3).toSet();
        final nodes = [
          for (final n in g.outdoorNodes)
            OutdoorNodeModel(
              id: n.id,
              lat: n.lat,
              lng: n.lng,
              buildingId: doors.contains(n.id) ? 9 : null,
              isEntrance: doors.contains(n.id),
            ),
        ];
        final path = DijkstraService.findPathToBuilding(
          startNodeId: g.ids.first,
          buildingId: 9,
          nodes: nodes,
          edges: g.outdoorEdges,
        );
        expect(path?.nodeIds, legacyQueue(g.ids.first, doors, g.adjacency()));
      }
    });

    test('indoor: findIndoorPath', () {
      final r = Random(4);
      for (var i = 0; i < graphCount; i++) {
        final g = TestGraph.random(r, allTwoWay: false);
        for (final end in g.ids) {
          final path = DijkstraService.findIndoorPath(
            startNodeId: g.ids.first,
            endNodeId: end,
            nodes: g.indoorNodes,
            edges: g.indoorEdges,
          );
          expect(path?.nodeIds, legacyQueue(g.ids.first, {end}, g.adjacency()));
        }
      }
    });

    test('multi-phase: the floor sweep, distances and predecessors', () {
      final r = Random(5);
      for (var i = 0; i < graphCount; i++) {
        final g = TestGraph.random(r, allTwoWay: false);
        final a = g.adjacency();
        final swept = DijkstraService.indoorDistances(
          nodes: g.indoorNodes,
          edges: g.indoorEdges,
          fromId: g.ids.first,
        );
        if (a.isEmpty) {
          expect(swept, isNull);
          continue;
        }
        final legacy = legacyFloorSweep(g.ids.first, g.ids, a);
        expect(swept!.dist, legacy.dist);
        expect(swept.prev, legacy.prev);
      }
    });

    test('AR: shortestArPath', () {
      final r = Random(6);
      for (var i = 0; i < graphCount; i++) {
        final g = TestGraph.random(r, allTwoWay: true);
        final targets = g.ids.skip(1).take(2).toSet();
        final found = shortestArPath(
          nodes: g.arNodes,
          edges: g.arEdges,
          fromId: g.ids.first,
          targetIds: targets,
        );
        final legacy =
            legacyArScan(g.ids.first, targets, g.adjacency(skipLoops: true));
        expect(found?.nodeIds, legacy?.nodeIds);
        expect(found?.meters, legacy?.meters);
      }
    });
  });

  test('all the callers agree on the cost of the same graph', () {
    final r = Random(7);
    for (var i = 0; i < graphCount; i++) {
      final g = TestGraph.random(r, allTwoWay: true);
      final start = g.ids.first;
      final swept = DijkstraService.indoorDistances(
        nodes: g.indoorNodes,
        edges: g.indoorEdges,
        fromId: start,
      );
      for (final end in g.ids.skip(1)) {
        double costOf(List<String>? ids) {
          if (ids == null) return double.infinity;
          var total = 0.0;
          for (var s = 0; s + 1 < ids.length; s++) {
            total += g.edges
                .where((e) =>
                    e.active &&
                    ((e.a == ids[s] && e.b == ids[s + 1]) ||
                        (e.b == ids[s] && e.a == ids[s + 1])))
                .map((e) => e.w)
                .reduce(min);
          }
          return total;
        }

        final outdoor = costOf(DijkstraService.findShortestPath(
          startNodeId: start,
          endNodeId: end,
          nodes: g.outdoorNodes,
          edges: g.outdoorEdges,
        )?.nodeIds);
        final indoor = costOf(DijkstraService.findIndoorPath(
          startNodeId: start,
          endNodeId: end,
          nodes: g.indoorNodes,
          edges: g.indoorEdges,
        )?.nodeIds);
        final ar = shortestArPath(
          nodes: g.arNodes,
          edges: g.arEdges,
          fromId: start,
          targetIds: {end},
        );

        expect(indoor, outdoor);
        expect(ar?.meters ?? double.infinity, outdoor);
        expect(swept?.dist[end] ?? double.infinity, outdoor);
      }
    }
  });
}
