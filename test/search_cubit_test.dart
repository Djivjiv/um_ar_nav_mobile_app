import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/data/models/building_model.dart';
import 'package:um_ar_mobile_app/data/models/indoor_node_model.dart';
import 'package:um_ar_mobile_app/data/models/room_model.dart';
import 'package:um_ar_mobile_app/data/repositories/building_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/facility_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/indoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/repository_exception.dart';
import 'package:um_ar_mobile_app/data/repositories/room_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/search/search_cubit.dart';

class FakeBuildings implements BuildingRepository {
  List<BuildingModel> list = const [];
  Object? error;
  int calls = 0;

  @override
  Future<List<BuildingModel>> getBuildings({bool forceRefresh = false}) async {
    calls++;
    if (error != null) throw error!;
    return list;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Room search whose answer for each query is released by the test.
class FakeRooms implements RoomRepository {
  final Map<String, Completer<List<RoomModel>>> pending = {};
  Object? inactiveError;

  @override
  Future<List<RoomModel>> searchRooms(String query) =>
      (pending[query] ??= Completer()).future;

  @override
  Future<Set<int>> inactiveRoomIds() async {
    if (inactiveError != null) throw inactiveError!;
    return {7};
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeFacilities implements FacilityRepository {
  @override
  Future<Set<int>> inactiveFacilityIds() async => const {};
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeIndoor implements IndoorNavigationRepository {
  Object? error;
  List<IndoorNodeModel> nodes = const [
    IndoorNodeModel(id: 'open', linkedRoomId: 1, linkedTable: 'rooms'),
    IndoorNodeModel(id: 'closed', linkedRoomId: 7, linkedTable: 'rooms'),
  ];

  @override
  Future<List<IndoorNodeModel>> searchNodes(String query) async {
    if (error != null) throw error!;
    return nodes;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

RoomModel room(int id, String name) =>
    RoomModel(id: id, buildingId: 1, roomName: name);

/// Lets timers (zero debounce) and microtasks run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeBuildings buildings;
  late FakeRooms rooms;
  late FakeIndoor indoor;
  late SearchCubit cubit;

  setUp(() {
    buildings = FakeBuildings();
    rooms = FakeRooms();
    indoor = FakeIndoor();
    cubit = SearchCubit(
        buildings, rooms, indoor, FakeFacilities(), Duration.zero);
  });

  tearDown(() => cubit.close());

  /// Runs [query] with the room search answering [hits].
  Future<void> search(String query, [List<RoomModel> hits = const []]) async {
    cubit.queryChanged(query);
    await settle();
    if (rooms.pending[query]?.isCompleted ?? false) {
      rooms.pending.remove(query);
      cubit.queryChanged(query);
      await settle();
    }
    rooms.pending[query]?.complete(hits);
    await settle();
  }

  group('matching', () {
    const library = BuildingModel(
        id: 1,
        name: 'Library',
        shortName: 'ULC',
        displayName: 'Main Library',
        lat: 7,
        lng: 125);
    const gym = BuildingModel(id: 2, name: 'Gym', lat: 7, lng: 125);

    setUp(() => buildings.list = const [library, gym]);

    test('finds a building by name in any case', () async {
      await search('lIbRa');
      expect(cubit.state.buildings, [library]);
    });

    test('finds a building by short name', () async {
      await search('ulc');
      expect(cubit.state.buildings, [library]);
    });

    test('finds a building by display name', () async {
      await search('main');
      expect(cubit.state.buildings, [library]);
    });

    test('spaces around the query do not count', () async {
      cubit.queryChanged('  gym ');
      await settle();
      rooms.pending['gym']!.complete(const []);
      await settle();
      expect(cubit.state.query, 'gym');
      expect(cubit.state.buildings, [gym]);
    });

    test('a search with no hit is an empty result, not an error', () async {
      indoor.nodes = const [];
      await search('zzz');
      expect(cubit.state.status, SearchStatus.loaded);
      expect(cubit.state.isEmpty, isTrue);
    });

    test('long lists are cut to 8 buildings, 10 rooms, 10 nodes', () async {
      buildings.list = [
        for (var i = 0; i < 12; i++)
          BuildingModel(id: i, name: 'Hall $i', lat: 7, lng: 125),
      ];
      indoor.nodes = [
        for (var i = 0; i < 12; i++) IndoorNodeModel(id: 'n$i'),
      ];
      await search('hall', [for (var i = 0; i < 12; i++) room(i, 'Hall $i')]);

      expect(cubit.state.buildings, hasLength(8));
      expect(cubit.state.rooms, hasLength(10));
      expect(cubit.state.indoorNodes, hasLength(10));
    });
  });

  group('typing', () {
    test('an empty query goes back to the start, without searching',
        () async {
      await search('lib');
      final calls = buildings.calls;

      cubit.queryChanged('   ');
      await settle();

      expect(cubit.state.status, SearchStatus.initial);
      expect(buildings.calls, calls);
    });

    test('shows loading while it waits', () async {
      cubit.queryChanged('lib');
      expect(cubit.state.status, SearchStatus.loading);
      expect(cubit.state.query, 'lib');
    });

    test('only the last of quick keystrokes runs', () async {
      final slow = SearchCubit(buildings, rooms, indoor, FakeFacilities(),
          const Duration(milliseconds: 40));
      addTearDown(slow.close);

      slow.queryChanged('l');
      slow.queryChanged('li');
      slow.queryChanged('lib');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(buildings.calls, 1);
      expect(rooms.pending.keys, ['lib']);
    });
  });

  group('picked place', () {
    test('is handed over and then cleared', () {
      cubit.pickPlace(const {'id': '1'});
      expect(cubit.state.pickedPlace, {'id': '1'});

      cubit.consumePickedPlace();
      expect(cubit.state.pickedPlace, isNull);
    });
  });

  group('a failed search', () {
    test('is an error, not an empty result', () async {
      buildings.error = RepositoryException('no connection');

      await search('lib');

      expect(cubit.state.status, SearchStatus.error);
      expect(cubit.state.query, 'lib');
    });

    test('failing indoor search is an error too', () async {
      indoor.error = RepositoryException('no connection');

      await search('lib');

      expect(cubit.state.status, SearchStatus.error);
    });

    test('Retry runs the same search again and can succeed', () async {
      buildings.error = RepositoryException('no connection');
      await search('lib');
      expect(cubit.state.status, SearchStatus.error);

      buildings.error = null;
      rooms.pending.clear();
      cubit.retry();
      expect(cubit.state.status, SearchStatus.loading);
      await settle();
      rooms.pending['lib']!.complete([room(2, 'Library')]);
      await settle();

      expect(cubit.state.status, SearchStatus.loaded);
      expect(cubit.state.rooms.map((r) => r.roomName), ['Library']);
    });

    test('a failure of an older search does not replace a newer one',
        () async {
      cubit.queryChanged('old');
      await settle();
      cubit.queryChanged('new');
      await settle();
      rooms.pending['new']!.complete([room(2, 'New')]);
      await settle();

      rooms.pending['old']!.completeError(StateError('late failure'));
      await settle();

      expect(cubit.state.status, SearchStatus.loaded);
      expect(cubit.state.query, 'new');
    });
  });

  test('an older query finishing last does not overwrite newer results (item 5)',
      () async {
    cubit.queryChanged('lib');
    await settle(); // "lib" is now waiting on the server
    cubit.queryChanged('library');
    await settle();

    rooms.pending['library']!.complete([room(2, 'Library')]);
    await settle();
    expect(cubit.state.query, 'library');
    expect(cubit.state.rooms.map((r) => r.roomName), ['Library']);

    // The slow, older search answers last — it must be ignored.
    rooms.pending['lib']!.complete([room(9, 'Old result')]);
    await settle();
    expect(cubit.state.query, 'library');
    expect(cubit.state.rooms.map((r) => r.roomName), ['Library']);
  });

  test('clear() discards a search still in flight', () async {
    cubit.queryChanged('lib');
    await settle();
    cubit.clear();
    rooms.pending['lib']!.complete([room(9, 'Late')]);
    await settle();
    expect(cubit.state.status, SearchStatus.initial);
    expect(cubit.state.rooms, isEmpty);
  });

  test('inactive linked rooms are hidden from indoor results', () async {
    cubit.queryChanged('x');
    await settle();
    rooms.pending['x']!.complete(const []);
    await settle();
    expect(cubit.state.indoorNodes.map((n) => n.id), ['open']);
    expect(cubit.state.notice, isNull);
  });

  test('when closed places cannot be checked, a notice is shown (item 4)',
      () async {
    rooms.inactiveError =
        RepositoryException(RoomRepository.inactiveIdsErrorMessage);
    cubit.queryChanged('x');
    await settle();
    rooms.pending['x']!.complete(const []);
    await settle();
    expect(cubit.state.status, SearchStatus.loaded);
    expect(cubit.state.notice, SearchCubit.closedCheckNotice);
    // Nothing could be filtered, and the user is told so.
    expect(cubit.state.indoorNodes.map((n) => n.id), ['open', 'closed']);
  });
}
