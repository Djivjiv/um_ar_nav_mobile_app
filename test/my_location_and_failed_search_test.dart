import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/data/local/offline_cache.dart';
import 'package:um_ar_mobile_app/data/models/building_model.dart';
import 'package:um_ar_mobile_app/data/models/facility_model.dart';
import 'package:um_ar_mobile_app/data/models/floor_plan_model.dart';
import 'package:um_ar_mobile_app/data/models/indoor_node_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_node_model.dart';
import 'package:um_ar_mobile_app/data/models/room_model.dart';
import 'package:um_ar_mobile_app/data/repositories/building_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/facility_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/floor_plan_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/indoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/repository_exception.dart';
import 'package:um_ar_mobile_app/data/repositories/room_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:um_ar_mobile_app/presentation/bloc/building/building_cubit.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/indoor_nav_cubit.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/outdoor_nav_cubit.dart';
import 'package:um_ar_mobile_app/presentation/bloc/search/search_cubit.dart';
import 'package:um_ar_mobile_app/presentation/routes/app_router.dart';
import 'package:um_ar_mobile_app/presentation/screens/main/main_screen.dart';
import 'package:um_ar_mobile_app/presentation/widgets/route_start_picker.dart';

import 'support/feedback_fakes.dart';
import 'support/visitor_fakes.dart';

const hallId = 3;
const hall = BuildingModel(id: hallId, name: 'Annex Hall', lat: 7.0671, lng: 125.5951);

/// gate — mid — entrance (of the hall).
const gate = OutdoorNodeModel(id: 'gate', lat: 7.0660, lng: 125.5940);
const mid = OutdoorNodeModel(id: 'mid', lat: 7.0665, lng: 125.5945);
const entrance = OutdoorNodeModel(
    id: 'entrance',
    lat: 7.0670,
    lng: 125.5950,
    buildingId: hallId,
    isEntrance: true);

class FakeBuildings implements BuildingRepository {
  @override
  Future<List<BuildingModel>> getBuildings({bool forceRefresh = false}) async =>
      const [hall];
  @override
  Future<BuildingModel?> getBuildingById(int id) async => hall;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRooms implements RoomRepository {
  @override
  Future<List<RoomModel>> getRoomsForBuilding(int buildingId) async => const [];
  @override
  Future<List<Map<String, dynamic>>> getAllRoomRows() async => const [
        {
          'id': 7,
          'roomname': 'Room 301',
          'building_id': hallId,
          'floor': 3,
          'buildings': {'name': 'Annex Hall'},
        },
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFacilities implements FacilityRepository {
  @override
  Future<List<FacilityModel>> getFacilitiesForBuilding(int buildingId) async =>
      const [];
  @override
  Future<List<Map<String, dynamic>>> getAllFacilityRows() async => const [];
  @override
  Future<Set<int>> inactiveFacilityIds() async => const {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFloors implements FloorPlanRepository {
  @override
  Future<List<FloorPlanModel>> getFloorsForBuilding(int buildingId) async =>
      const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeIndoor implements IndoorNavigationRepository {
  @override
  Future<List<IndoorNodeModel>> searchNodes(String query) async => const [];
  @override
  Future<bool> buildingHasElevator(String buildingId) async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOutdoor implements OutdoorNavigationRepository {
  @override
  List<OutdoorNodeModel> get nodes => const [gate, mid, entrance];
  @override
  List<OutdoorEdgeModel> get edges => const [
        OutdoorEdgeModel(id: 'e1', fromNode: 'gate', toNode: 'mid', weight: 70),
        OutdoorEdgeModel(
            id: 'e2', fromNode: 'mid', toNode: 'entrance', weight: 70),
      ];
  @override
  bool get isLoaded => true;
  @override
  Future<void> loadGraph({bool forceRefresh = false}) async {}
  @override
  OutdoorNodeModel? nearestNode(double lat, double lng) {
    OutdoorNodeModel? best;
    var bestD = double.infinity;
    for (final n in nodes) {
      final d = (n.lat - lat) * (n.lat - lat) + (n.lng - lng) * (n.lng - lng);
      if (d < bestD) {
        bestD = d;
        best = n;
      }
    }
    return best;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The phone's GPS. [fix] null means no position can be had.
class FakeGps extends GeolocatorPlatform {
  LatLng? fix;
  Completer<void>? hold;

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    await hold?.future;
    final f = fix;
    if (f == null) throw TimeoutException('no fix');
    return Position(
      latitude: f.latitude,
      longitude: f.longitude,
      timestamp: DateTime.utc(2026, 11, 1),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

const startHint = 'Select starting point';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('"My location" as the start of Navigate', () {
    late FakeGps gps;
    late OutdoorNavCubit nav;

    const compass = EventChannel('hemanthraj/flutter_compass');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() async {
      await FeedbackWorld.resetPhone();
      gps = FakeGps();
      GeolocatorPlatform.instance = gps;
      messenger.setMockStreamHandler(
          compass, MockStreamHandler.inline(onListen: (_, _) {}));
    });
    tearDown(() => messenger.setMockStreamHandler(compass, null));

    /// The real Places tab and Map tab, in the real router.
    Future<void> pumpPlaces(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final buildings = FakeBuildings();
      final rooms = FakeRooms();
      final facilities = FakeFacilities();
      final indoor = FakeIndoor();
      nav = OutdoorNavCubit(FakeOutdoor());
      await tester.pumpWidget(MultiRepositoryProvider(
        providers: [
          RepositoryProvider<BuildingRepository>.value(value: buildings),
          RepositoryProvider<RoomRepository>.value(value: rooms),
          RepositoryProvider<FacilityRepository>.value(value: facilities),
          RepositoryProvider<FloorPlanRepository>.value(value: FakeFloors()),
          RepositoryProvider<IndoorNavigationRepository>.value(value: indoor),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(
                value: SeededAuthCubit(state: AuthAuthenticated(student(userA)))),
            BlocProvider(
                create: (_) => BuildingCubit(buildings, rooms, facilities)),
            BlocProvider.value(value: nav),
            BlocProvider(create: (_) => IndoorNavCubit(indoor)),
            BlocProvider(
                create: (_) =>
                    SearchCubit(buildings, rooms, indoor, facilities)),
          ],
          child: Builder(
            builder: (context) => MaterialApp.router(
              routerConfig:
                  AppRouter.build(context, initialLocation: '/places'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tearDownApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    }

    /// Places → Navigate on the hall → the planner → the start picker.
    Future<void> openStartPicker(WidgetTester tester) async {
      await pumpPlaces(tester);
      await tester.tap(find.text('Navigate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(startHint));
      await tester.pumpAndSettle();
    }

    Future<void> chooseMyLocation(WidgetTester tester) async {
      await tester.tap(find.text('My location'));
      await tester.pumpAndSettle();
    }

    /// The route line animates for ever, so this can't pump until settled.
    Future<void> pumpABit(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> findRoute(WidgetTester tester) async {
      await tester.tap(find.text('Find Route'));
      await pumpABit(tester);
    }

    testWidgets('routes from the path node nearest the user', (tester) async {
      gps.fix = mid.point;
      await openStartPicker(tester);
      await chooseMyLocation(tester);
      await findRoute(tester);

      expect(nav.state.hasRoute, isTrue);
      expect(nav.state.pathNodeIds, ['mid', 'entrance']);
      expect(nav.state.from?.label, 'My location');
      expect(nav.state.to?.label, 'Annex Hall');

      await tearDownApp(tester);
    });

    testWidgets('it is offered only as the start, not the destination',
        (tester) async {
      await pumpPlaces(tester);
      await tester.tap(find.text('Navigate'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annex Hall').last); // the "To" picker
      await tester.pumpAndSettle();

      expect(find.text('My location'), findsNothing);

      await tearDownApp(tester);
    });

    testWidgets('stays offered while searching and filtering',
        (tester) async {
      await openStartPicker(tester);

      await tester.enterText(find.byType(TextField), 'nothing like this');
      await tester.pump();
      await tester.tap(find.text('Rooms'));
      await tester.pumpAndSettle();

      expect(find.text('No results found'), findsOneWidget);
      expect(find.text('My location'), findsOneWidget);

      await tearDownApp(tester);
    });

    testWidgets('with no GPS fix the planner stays open and says why',
        (tester) async {
      gps.fix = null;
      await openStartPicker(tester);
      await chooseMyLocation(tester);
      await findRoute(tester);

      expect(find.text('$noLocationReason Choose a starting point.'),
          findsOneWidget);
      expect(find.text('Plan a Route'), findsOneWidget);
      expect(find.text(startHint), findsOneWidget);
      expect(nav.state.hasRoute, isFalse);

      await tearDownApp(tester);
    });

    testWidgets('off campus is refused, not snapped to a far node',
        (tester) async {
      gps.fix = const LatLng(14.6, 121.0); // Manila
      await openStartPicker(tester);
      await chooseMyLocation(tester);
      await findRoute(tester);

      expect(find.text('$offCampusReason Choose a starting point.'),
          findsOneWidget);
      expect(nav.state.hasRoute, isFalse);

      await tearDownApp(tester);
    });

    testWidgets('choosing again clears the message', (tester) async {
      gps.fix = null;
      await openStartPicker(tester);
      await chooseMyLocation(tester);
      await findRoute(tester);

      await tester.tap(find.text(startHint));
      await tester.pumpAndSettle();
      await chooseMyLocation(tester);

      expect(find.textContaining(noLocationReason), findsNothing);

      await tearDownApp(tester);
    });

    testWidgets('Find Route waits and cannot be tapped twice', (tester) async {
      gps.fix = mid.point;
      gps.hold = Completer();
      await openStartPicker(tester);
      await chooseMyLocation(tester);

      await tester.tap(find.text('Find Route'));
      await tester.pump();

      expect(find.text('Finding your location…'), findsOneWidget);
      expect(find.text('Find Route'), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(find.ancestor(
                of: find.text('Finding your location…'),
                matching: find.byWidgetPredicate((w) => w is ElevatedButton)))
            .onPressed,
        isNull,
      );

      gps.hold!.complete();
      await pumpABit(tester);
      expect(nav.state.hasRoute, isTrue);

      await tearDownApp(tester);
    });

    testWidgets('closing the planner while waiting asks for no route',
        (tester) async {
      gps.fix = mid.point;
      gps.hold = Completer();
      await openStartPicker(tester);
      await chooseMyLocation(tester);
      await tester.tap(find.text('Find Route'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      gps.hold!.complete();
      await pumpABit(tester);

      expect(nav.state.hasRoute, isFalse);

      await tearDownApp(tester);
    });

    testWidgets('swap is off, so it can never become the destination',
        (tester) async {
      gps.fix = mid.point;
      await openStartPicker(tester);
      await chooseMyLocation(tester);

      await tester.tap(find.byIcon(Icons.swap_vert));
      await tester.pumpAndSettle();
      await findRoute(tester);

      expect(nav.state.from?.label, 'My location');
      expect(nav.state.to?.label, 'Annex Hall');

      await tearDownApp(tester);
    });

    testWidgets('at the entrance of a room\'s building there is no outdoor leg',
        (tester) async {
      gps.fix = entrance.point;
      await pumpPlaces(tester);
      await tester.tap(find.text('Navigate'));
      await tester.pumpAndSettle();

      // Change the destination to a room in the same building.
      await tester.tap(find.text('Annex Hall').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Room 301'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(startHint));
      await tester.pumpAndSettle();
      await chooseMyLocation(tester);
      await findRoute(tester);

      expect(nav.state.hasRoute, isFalse, reason: 'no outdoor route');
      expect(find.text('Start and destination are at the same place.'),
          findsNothing);

      await tearDownApp(tester);
    });

    testWidgets('a room in the hall from elsewhere still walks there',
        (tester) async {
      gps.fix = gate.point;
      await pumpPlaces(tester);
      await tester.tap(find.text('Navigate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annex Hall').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Room 301'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(startHint));
      await tester.pumpAndSettle();
      await chooseMyLocation(tester);
      await findRoute(tester);

      expect(nav.state.pathNodeIds, ['gate', 'mid', 'entrance']);
      expect(nav.state.to?.placeType, 'room');

      await tearDownApp(tester);
    });

    test('a failed map load is reported as that, not as no GPS', () async {
      final cubit = OutdoorNavCubit(FailingGraph());
      addTearDown(cubit.close);

      final start = await locateStartNode(cubit, locate: () async => mid.point);

      expect(start.node, isNull);
      expect(start.problem, 'Could not load the campus map.');
    });
  });

  group('the search overlay', () {
    late bool failing;
    late List<BuildingModel> hits;
    late SearchCubit cubit;

    Future<void> pumpOverlay(WidgetTester tester) async {
      final buildings = SwitchableBuildings(() => failing, () => hits);
      cubit = SearchCubit(buildings, EmptyRooms(), FakeIndoor(),
          FakeFacilities(), Duration.zero);
      addTearDown(cubit.close);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSearch(
                  context: context, delegate: AppSearchDelegate(cubit)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'library');
      await tester.pump(); // the search starts after this frame
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
    }

    setUp(() {
      failing = true;
      hits = const [];
    });

    testWidgets('a failed search says so, with Retry', (tester) async {
      await pumpOverlay(tester);

      expect(find.text(SearchCubit.failedMessage), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No matches found'), findsNothing);
    });

    testWidgets('the message is the agreed wording', (tester) async {
      expect(SearchCubit.failedMessage,
          'Could not search. Check your connection.');
    });

    testWidgets('Retry searches again and shows the answer', (tester) async {
      await pumpOverlay(tester);

      failing = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(find.text(SearchCubit.failedMessage), findsNothing);
      expect(find.text('No matches found'), findsOneWidget);
    });

    testWidgets('old results are not left on screen after a failure',
        (tester) async {
      failing = false;
      hits = const [
        BuildingModel(id: 1, name: 'Library', lat: 7, lng: 125),
      ];
      await pumpOverlay(tester);
      expect(find.text('Library'), findsOneWidget);

      failing = true;
      cubit.retry();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsNothing);
      expect(find.text(SearchCubit.failedMessage), findsOneWidget);
    });

    testWidgets('a search that worked and found nothing says so',
        (tester) async {
      failing = false;
      await pumpOverlay(tester);

      expect(find.text('No matches found'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('offline, the search knows if it had anything to look through', () {
    late ConnectivityService connectivity;
    late OfflineCache cache;
    late SupabaseClient client;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      connectivity = ConnectivityService(probe: () async => false);
      cache = OfflineCache(
          connectivity: connectivity,
          networkTimeout: const Duration(milliseconds: 200));
      client = SupabaseClient('http://127.0.0.1:9', 'test-key');
    });

    test('rooms with no saved copy: the failure comes through', () async {
      final repo = RoomRepository(client, cache);

      await expectLater(repo.searchRooms('lab'), throwsA(anything));
    });

    test('rooms with a saved copy that has no match: an empty answer',
        () async {
      await cache.save(RoomRepository.allCacheKey, const <Object>[]);
      final repo = RoomRepository(client, cache);

      expect(await repo.searchRooms('lab'), isEmpty);
    });

    test('rooms with a saved copy: searched as before', () async {
      await cache.save(RoomRepository.allCacheKey, const [
        {'id': 1, 'roomname': 'Lab', 'building_id': 1, 'is_active': true},
      ]);
      final repo = RoomRepository(client, cache);

      expect((await repo.searchRooms('lab')).map((r) => r.id), [1]);
    });

    test('indoor nodes with no saved copy: the failure comes through',
        () async {
      final repo = IndoorNavigationRepository(client, cache);

      await expectLater(repo.searchNodes('lab'), throwsA(anything));
    });

    test('indoor nodes with a saved floor and no match: an empty answer',
        () async {
      await cache.save(
          IndoorNavigationRepository.nodesCacheKey('1'), const <Object>[]);
      final repo = IndoorNavigationRepository(client, cache);

      expect(await repo.searchNodes('lab'), isEmpty);
    });
  });
}

class FailingGraph extends FakeOutdoor {
  @override
  bool get isLoaded => false;
  @override
  Future<void> loadGraph({bool forceRefresh = false}) async =>
      throw RepositoryException('Could not load the campus map.');
}

class SwitchableBuildings extends FakeBuildings {
  SwitchableBuildings(this.failing, this.hits);
  final bool Function() failing;
  final List<BuildingModel> Function() hits;

  @override
  Future<List<BuildingModel>> getBuildings({bool forceRefresh = false}) async {
    if (failing()) throw const SocketException('No route to host');
    return hits();
  }
}

class EmptyRooms extends FakeRooms {
  @override
  Future<List<RoomModel>> searchRooms(String query) async => const [];
  @override
  Future<Set<int>> inactiveRoomIds() async => const {};
}
