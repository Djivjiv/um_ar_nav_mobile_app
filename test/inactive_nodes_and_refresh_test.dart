import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/core/utils/indoor_route_helpers.dart';
import 'package:um_ar_mobile_app/data/local/offline_cache.dart';
import 'package:um_ar_mobile_app/data/models/indoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/indoor_node_model.dart';
import 'package:um_ar_mobile_app/data/repositories/facility_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/indoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/repository_exception.dart';
import 'package:um_ar_mobile_app/data/repositories/room_repository.dart';
import 'package:um_ar_mobile_app/domain/services/dijkstra_service.dart';

/// Nothing listens here, so every request fails and saved copies are used.
final unreachable = SupabaseClient('http://127.0.0.1:9', 'test-key');

OfflineCache offlineCache() => OfflineCache(
      connectivity: ConnectivityService(probe: () async => false),
      networkTimeout: const Duration(seconds: 3),
    );

void main() {
  group('IndoorNodeModel.isActive (item 3)', () {
    test('only an explicit false makes a node inactive', () {
      bool active(Map<String, dynamic> m) =>
          IndoorNodeModel.fromMap({'id': 'n', ...m}).isActive;
      expect(active({}), isTrue, reason: 'column missing');
      expect(active({'is_active': null}), isTrue);
      expect(active({'is_active': true}), isTrue);
      expect(active({'is_active': 'maybe'}), isTrue);
      expect(active({'is_active': false}), isFalse);
      expect(active({'is_active': 'f'}), isFalse);
    });

    test('activeNodesFromRows drops inactive rows', () {
      final nodes = IndoorNavigationRepository.activeNodesFromRows([
        {'id': 'a'},
        {'id': 'b', 'is_active': false},
        {'id': 'c', 'is_active': null},
        'not a row',
      ]);
      expect(nodes.map((n) => n.id), ['a', 'c']);
    });
  });

  group('inactive nodes are left out of indoor routing (item 3)', () {
    // s ── m(inactive) ── t   and a longer detour   s ── n2 ── t
    const nodes = [
      IndoorNodeModel(id: 's', x: 0, y: 0),
      IndoorNodeModel(id: 'm', x: 10, y: 0, isActive: false),
      IndoorNodeModel(id: 't', x: 20, y: 0),
      IndoorNodeModel(id: 'n2', x: 10, y: 30),
    ];
    const edges = [
      IndoorEdgeModel(id: '1', fromNode: 's', toNode: 'm', weight: 10),
      IndoorEdgeModel(id: '2', fromNode: 'm', toNode: 't', weight: 10),
      IndoorEdgeModel(id: '3', fromNode: 's', toNode: 'n2', weight: 32),
      IndoorEdgeModel(id: '4', fromNode: 'n2', toNode: 't', weight: 32),
    ];

    test('Dijkstra detours around an inactive node', () {
      final r = DijkstraService.findIndoorPath(
          startNodeId: 's', endNodeId: 't', nodes: nodes, edges: edges);
      expect(r?.nodeIds, ['s', 'n2', 't']);
    });

    test('an inactive destination has no route', () {
      final r = DijkstraService.findIndoorPath(
          startNodeId: 's', endNodeId: 'm', nodes: nodes, edges: edges);
      expect(r, isNull);
    });

    test('an inactive staircase is never chosen', () {
      const start = [
        IndoorNodeModel(
            id: 'a1', label: 'Stairs', stairGroup: 'A', isActive: false),
        IndoorNodeModel(id: 'b1', label: 'Stairs', stairGroup: 'B'),
      ];
      const dest = [
        IndoorNodeModel(id: 'a2', label: 'Stairs', stairGroup: 'A'),
        IndoorNodeModel(id: 'b2', label: 'Stairs', stairGroup: 'B'),
      ];
      final choice = chooseStairGroup(
        startFloorNodes: start,
        destFloorNodes: dest,
        transport: 'stairs',
        // A would be far cheaper — if it were open.
        costToTransport: (n) => n.stairGroup == 'A' ? 1 : 100,
        costFromTransport: (n) => n.stairGroup == 'A' ? 1 : 100,
      );
      expect(choice?.group, 'B');
    });
  });

  group('IndoorNavigationRepository filters saved copies (item 3)', () {
    late OfflineCache cache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      cache = offlineCache();
      await cache.save(IndoorNavigationRepository.nodesCacheKey('6'), [
        {'id': 'lab1', 'floor_plan_id': 6, 'room_name': 'Lab 1'},
        {
          'id': 'lab2',
          'floor_plan_id': 6,
          'room_name': 'Lab 2',
          'is_active': false
        },
        {'id': 'lab3', 'floor_plan_id': 6, 'room_name': 'Lab 3'},
      ]);
    });

    test('floor nodes (routing + floor plan)', () async {
      final repo = IndoorNavigationRepository(unreachable, cache);
      expect((await repo.getNodesForFloor('6')).map((n) => n.id),
          ['lab1', 'lab3']);
    });

    test('indoor search', () async {
      final repo = IndoorNavigationRepository(unreachable, cache);
      expect((await repo.searchNodes('lab')).map((n) => n.id),
          ['lab1', 'lab3']);
    });
  });

  group('inactive room / facility ids refresh every 10 minutes (item 4)', () {
    late OfflineCache cache;
    late DateTime now;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      cache = offlineCache();
      now = DateTime(2026, 10, 30, 9);
    });

    Future<void> saveRooms(Set<int> inactive) => cache.save(
          RoomRepository.allCacheKey,
          [
            for (var id = 1; id <= 4; id++)
              {'id': id, 'roomname': 'R$id', 'is_active': !inactive.contains(id)},
          ],
        );

    test('reused for 10 minutes, then reloaded', () async {
      await saveRooms({2});
      final repo = RoomRepository(unreachable, cache, () => now);
      expect(await repo.inactiveRoomIds(), {2});

      await saveRooms({3}); // the admin closes room 3
      now = now.add(const Duration(minutes: 9));
      expect(await repo.inactiveRoomIds(), {2}, reason: 'still fresh');

      now = now.add(const Duration(minutes: 2));
      expect(await repo.inactiveRoomIds(), {3}, reason: 'expired → reloaded');
    });

    test('a failed reload keeps the last known list', () async {
      await saveRooms({2});
      final repo = RoomRepository(unreachable, cache, () => now);
      expect(await repo.inactiveRoomIds(), {2});

      await cache.remove(RoomRepository.allCacheKey); // nothing to fall back to
      now = now.add(const Duration(minutes: 11));
      expect(await repo.inactiveRoomIds(), {2});
    });

    test('with no list at all it throws instead of returning {}', () async {
      final rooms = RoomRepository(unreachable, cache, () => now);
      await expectLater(
          rooms.inactiveRoomIds(),
          throwsA(isA<RepositoryException>().having((e) => e.message,
              'message', RoomRepository.inactiveIdsErrorMessage)));

      final facilities = FacilityRepository(unreachable, cache, () => now);
      await expectLater(
          facilities.inactiveFacilityIds(),
          throwsA(isA<RepositoryException>().having((e) => e.message,
              'message', FacilityRepository.inactiveIdsErrorMessage)));
    });

    test('facilities refresh the same way', () async {
      Future<void> save(int closed) => cache.save(FacilityRepository.allCacheKey, [
            {'id': 1, 'roomname': 'Clinic', 'is_active': closed != 1},
            {'id': 2, 'roomname': 'Cashier', 'is_active': closed != 2},
          ]);
      await save(1);
      final repo = FacilityRepository(unreachable, cache, () => now);
      expect(await repo.inactiveFacilityIds(), {1});
      await save(2);
      now = now.add(const Duration(minutes: 10));
      expect(await repo.inactiveFacilityIds(), {2});
    });
  });
}
