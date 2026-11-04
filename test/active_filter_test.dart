import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/core/utils/indoor_route_helpers.dart';
import 'package:um_ar_mobile_app/core/utils/json_utils.dart';
import 'package:um_ar_mobile_app/data/local/offline_cache.dart';
import 'package:um_ar_mobile_app/data/models/indoor_node_model.dart';
import 'package:um_ar_mobile_app/data/repositories/facility_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/room_repository.dart';

/// Rows covering every shape `is_active` can take.
final _rows = <Map<String, dynamic>>[
  {'id': 1, 'roomname': 'Library', 'building_id': 5, 'is_active': true},
  {'id': 2, 'roomname': 'Old Lab', 'building_id': 5, 'is_active': false},
  {'id': 3, 'roomname': 'Clinic', 'building_id': 5, 'is_active': null},
  {'id': 4, 'roomname': 'Cashier', 'building_id': 5}, // column missing
  {'id': 5, 'roomname': 'Closed Office', 'building_id': 5, 'is_active': 'false'},
  {'id': 6, 'roomname': 'Gym', 'building_id': 6, 'is_active': 'f'},
];

List<int> ids(Iterable<Map<String, dynamic>> rows) =>
    [for (final r in rows) r['id'] as int];

void main() {
  group('J.isActiveRow / activeRows', () {
    test('only an explicit false hides a row', () {
      expect(ids(J.activeRows(_rows)), [1, 3, 4]);
    });

    test('inactiveIds lists exactly the hidden rows', () {
      expect(J.inactiveIds(_rows), {2, 5, 6});
    });

    test('unreadable values count as active', () {
      expect(J.isActiveRow({'is_active': 'maybe'}), isTrue);
      expect(J.isActiveRow(const {}), isTrue);
      expect(J.isActiveRow({'is_active': 0}), isFalse);
    });
  });

  test('per-building facilities drop inactive ones, details still attach',
      () {
    final models = FacilityRepository.facilitiesFromCacheEntry({
      'facilities': _rows,
      'details': [
        {'id': 9, 'facility_id': 3, 'office_hours': '8-5'},
      ],
    });
    expect(models.map((f) => f.id), [1, 3, 4]);
    expect(models.firstWhere((f) => f.id == 3).details, isNotNull);
  });

  group('indoor nodes linked to inactive places are hidden from search', () {
    IndoorNodeModel node(int? linked, String? table) => IndoorNodeModel(
          id: 'n$linked$table',
          linkedRoomId: linked,
          linkedTable: table,
        );

    test('facility and room links', () {
      expect(
          isLinkedPlaceActive(node(2, 'facilities'),
              inactiveFacilityIds: {2}),
          isFalse);
      expect(isLinkedPlaceActive(node(2, 'rooms'), inactiveFacilityIds: {2}),
          isTrue, reason: 'room 2 is not facility 2');
      expect(isLinkedPlaceActive(node(7, 'rooms'), inactiveRoomIds: {7}),
          isFalse);
      // Older nodes without linked_table link rooms.
      expect(isLinkedPlaceActive(node(7, null), inactiveRoomIds: {7}),
          isFalse);
    });

    test('unlinked nodes and unknown sets always show', () {
      expect(isLinkedPlaceActive(node(null, null), inactiveRoomIds: {1}),
          isTrue);
      expect(isLinkedPlaceActive(node(2, 'facilities')), isTrue);
    });
  });

  group('offline copies are filtered too', () {
    late OfflineCache cache;
    // Nothing listens here, so every request fails and the saved copy is
    // used — including copies saved before is_active existed.
    final unreachable = SupabaseClient('http://127.0.0.1:9', 'test-key');

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      cache = OfflineCache(
        connectivity: ConnectivityService(probe: () async => false),
        networkTimeout: const Duration(seconds: 3),
      );
      await cache.save(FacilityRepository.allCacheKey, _rows);
      await cache.save(FacilityRepository.buildingCacheKey(5), {
        'facilities': _rows.where((r) => r['building_id'] == 5).toList(),
        'details': const [],
      });
      await cache.save(RoomRepository.allCacheKey, _rows);
      await cache.save(RoomRepository.buildingCacheKey(5),
          _rows.where((r) => r['building_id'] == 5).toList());
    });

    test('facilities: Places / map list and per-building list', () async {
      final repo = FacilityRepository(unreachable, cache);
      expect(ids(await repo.getAllFacilityRows()), [4, 3, 1]); // by name
      expect(await repo.inactiveFacilityIds(), {2, 5, 6});
      expect((await repo.getFacilitiesForBuilding(5)).map((f) => f.id),
          [1, 3, 4]);
    });

    test('rooms: map list, per-building list and search', () async {
      final repo = RoomRepository(unreachable, cache);
      expect(ids(await repo.getAllRoomRows()), [4, 3, 1]);
      expect(await repo.inactiveRoomIds(), {2, 5, 6});
      expect((await repo.getRoomsForBuilding(5)).map((r) => r.id), [1, 3, 4]);
      // "l" matches Library, Old Lab, Clinic and Closed Office — only
      // Library and Clinic are active.
      expect((await repo.searchRooms('l')).map((r) => r.id), [1, 3]);
      expect(await repo.searchRooms('Old Lab'), isEmpty);
    });
  });
}
