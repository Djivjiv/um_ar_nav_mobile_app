import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:um_ar_mobile_app/core/utils/navigation_preference.dart';
import 'package:um_ar_mobile_app/data/models/building_model.dart';
import 'package:um_ar_mobile_app/data/models/facility_model.dart';
import 'package:um_ar_mobile_app/data/models/floor_plan_model.dart';
import 'package:um_ar_mobile_app/data/models/indoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/indoor_node_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_node_model.dart';
import 'package:um_ar_mobile_app/data/models/room_model.dart';
import 'package:um_ar_mobile_app/data/repositories/building_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/facility_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/floor_plan_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/indoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/room_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:um_ar_mobile_app/presentation/bloc/building/building_cubit.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/indoor_nav_cubit.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/outdoor_nav_cubit.dart';
import 'package:um_ar_mobile_app/presentation/bloc/search/search_cubit.dart';
import 'package:um_ar_mobile_app/presentation/routes/app_router.dart';
import 'package:um_ar_mobile_app/presentation/screens/floor_plan/floor_plan_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/map/map_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/places/building_detail_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/places/places_screen.dart';
import 'package:um_ar_mobile_app/presentation/widgets/building_bottom_sheet.dart';
import 'package:um_ar_mobile_app/presentation/widgets/dev_coordinate_panel.dart';

import 'support/feedback_fakes.dart';
import 'support/visitor_fakes.dart';

const buildingId = 3;
const hall = BuildingModel(
    id: buildingId, name: 'Annex Hall', lat: 7.06, lng: 125.59, floorCount: 2);

FloorPlanModel plan(int id, int number, {String? name, bool image = true}) =>
    FloorPlanModel(
      id: id,
      buildingId: buildingId,
      floorNumber: number,
      floorName: name,
      imageUrl: image ? 'https://plans.test/$id.png' : null,
    );

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
  Future<List<Map<String, dynamic>>> getAllRoomRows() async => const [];
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFloors implements FloorPlanRepository {
  List<FloorPlanModel> floors;
  bool failing = false;
  int loads = 0;

  /// When set, an answer waits for this.
  Completer<void>? hold;
  FakeFloors(this.floors);

  @override
  Future<List<FloorPlanModel>> getFloorsForBuilding(int buildingId) async {
    loads++;
    await hold?.future;
    if (failing) throw Exception('no connection');
    return floors;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeIndoor implements IndoorNavigationRepository {
  @override
  Future<List<IndoorNodeModel>> getNodesForFloor(String floorPlanId) async =>
      const [];
  @override
  Future<List<IndoorEdgeModel>> getEdgesForFloor(String floorPlanId) async =>
      const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOutdoor implements OutdoorNavigationRepository {
  @override
  List<OutdoorNodeModel> get nodes => const [];
  @override
  List<OutdoorEdgeModel> get edges => const [];
  @override
  bool get isLoaded => true;
  @override
  Future<void> loadGraph({bool forceRefresh = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// For the viewer, whose image spinner never lets pumpAndSettle finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens a sheet all the way, as its lower part is built on demand.
Future<void> expandSheet(WidgetTester tester) async {
  await tester.drag(
      find.byType(DraggableScrollableSheet).last, const Offset(0, -500));
  await tester.pumpAndSettle();
}

/// The app's real routes and guards, starting at [start].
Future<GoRouter> pumpApp(
  WidgetTester tester, {
  required AuthState auth,
  required FakeFloors floors,
  String start = '/places',
}) async {
  usePhone(tester);
  late GoRouter router;
  final buildings = FakeBuildings();
  final rooms = FakeRooms();
  final facilities = FakeFacilities();
  final indoor = FakeIndoor();
  await tester.pumpWidget(MultiRepositoryProvider(
    providers: [
      RepositoryProvider<BuildingRepository>.value(value: buildings),
      RepositoryProvider<RoomRepository>.value(value: rooms),
      RepositoryProvider<FacilityRepository>.value(value: facilities),
      RepositoryProvider<FloorPlanRepository>.value(value: floors),
      RepositoryProvider<IndoorNavigationRepository>.value(value: indoor),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: SeededAuthCubit(state: auth)),
        BlocProvider(
            create: (_) => BuildingCubit(buildings, rooms, facilities)),
        BlocProvider(create: (_) => OutdoorNavCubit(FakeOutdoor())),
        BlocProvider(create: (_) => IndoorNavCubit(indoor)),
        BlocProvider(
            create: (_) => SearchCubit(buildings, rooms, indoor, facilities)),
      ],
      child: Builder(builder: (context) {
        router = AppRouter.build(context, initialLocation: start);
        return MaterialApp.router(routerConfig: router);
      }),
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

String location(GoRouter router) => router.state.uri.toString();

Future<void> tearDownApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 1));
}

const floorPlansButton = 'Floor plans';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await FeedbackWorld.resetPhone();
    NavigationPreference.getAndClear();
  });

  final verified = AuthAuthenticated(student(userA));

  const compass = EventChannel('hemanthraj/flutter_compass');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // The map's debug-build panel listens to the compass.
  setUp(() => messenger.setMockStreamHandler(
      compass, MockStreamHandler.inline(onListen: (_, _) {})));
  tearDown(() => messenger.setMockStreamHandler(compass, null));

  group('Places link', () {
    testWidgets('tapping a building opens its detail, Back returns',
        (tester) async {
      final router =
          await pumpApp(tester, auth: verified, floors: FakeFloors([]));

      await tester.tap(find.text('Annex Hall'));
      await tester.pumpAndSettle();

      expect(find.byType(BuildingDetailScreen), findsOneWidget);
      expect(location(router), '/building/$buildingId');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(BuildingDetailScreen), findsNothing);
      expect(find.byType(PlacesScreen), findsOneWidget);
      expect(location(router), '/places');

      await tearDownApp(tester);
    });

    testWidgets('a visitor gets the same link', (tester) async {
      await pumpApp(tester, auth: visitorState(), floors: FakeFloors([]));

      await tester.tap(find.text('Annex Hall'));
      await tester.pumpAndSettle();

      expect(find.byType(BuildingDetailScreen), findsOneWidget);

      await tearDownApp(tester);
    });

    testWidgets('Navigate on the card still plans a route on the map',
        (tester) async {
      final router =
          await pumpApp(tester, auth: verified, floors: FakeFloors([]));

      await tester.tap(find.text('Navigate'));
      await tester.pumpAndSettle();

      expect(find.byType(BuildingDetailScreen), findsNothing);
      expect(location(router), '/map');
      expect(find.text('Plan a Route'), findsOneWidget);
      expect(find.text('Annex Hall'), findsOneWidget);

      await tearDownApp(tester);
    });
  });

  group('Floor plans button on the building detail screen', () {
    const detail = '/building/$buildingId';

    testWidgets('a verified user, one plan: goes straight to the viewer',
        (tester) async {
      final router = await pumpApp(tester,
          auth: verified, floors: FakeFloors([plan(10, 1)]), start: detail);

      await tester.tap(find.text(floorPlansButton));
      await settle(tester);

      expect(find.text('Choose a floor'), findsNothing);
      expect(location(router), '/floor-plan/10?buildingId=$buildingId');
      final viewer =
          tester.widget<FloorPlanScreen>(find.byType(FloorPlanScreen));
      expect(viewer.buildingId, buildingId);
      expect(viewer.initialFloorPlanId, '10');

      await tearDownApp(tester);
    });

    testWidgets('several floors: chooser first, then the floor picked',
        (tester) async {
      final router = await pumpApp(
        tester,
        auth: verified,
        floors:
            FakeFloors([plan(10, 1), plan(20, 2), plan(30, 3, name: 'Roof')]),
        start: detail,
      );

      await tester.tap(find.text(floorPlansButton));
      await tester.pumpAndSettle();

      expect(find.text('Choose a floor'), findsOneWidget);
      expect(find.text('Ground Floor'), findsOneWidget);
      expect(find.text('2F'), findsOneWidget);
      expect(find.text('Roof'), findsOneWidget);

      await tester.tap(find.text('2F'));
      await settle(tester);

      expect(location(router), '/floor-plan/20?buildingId=$buildingId');
      expect(
        tester
            .widget<FloorPlanScreen>(find.byType(FloorPlanScreen))
            .initialFloorPlanId,
        '20',
      );

      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.byType(BuildingDetailScreen), findsOneWidget);

      await tearDownApp(tester);
    });

    testWidgets('closing the chooser stays on the building', (tester) async {
      final router = await pumpApp(tester,
          auth: verified,
          floors: FakeFloors([plan(10, 1), plan(20, 2)]),
          start: detail);

      await tester.tap(find.text(floorPlansButton));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Choose a floor'), findsNothing);
      expect(location(router), detail);

      await tearDownApp(tester);
    });

    testWidgets('hidden for a visitor, who never loads the plans',
        (tester) async {
      final floors = FakeFloors([plan(10, 1), plan(20, 2)]);
      await pumpApp(tester,
          auth: visitorState(), floors: floors, start: detail);

      expect(find.byType(BuildingDetailScreen), findsOneWidget);
      expect(find.text(floorPlansButton), findsNothing);
      expect(floors.loads, 0);

      await tearDownApp(tester);
    });

    testWidgets('hidden when the building has no plan', (tester) async {
      await pumpApp(tester,
          auth: verified, floors: FakeFloors([]), start: detail);

      expect(find.text('Navigate Here'), findsOneWidget);
      expect(find.text(floorPlansButton), findsNothing);

      await tearDownApp(tester);
    });

    testWidgets('a floor with no image is not offered', (tester) async {
      final router = await pumpApp(
        tester,
        auth: verified,
        floors: FakeFloors([plan(10, 1, image: false), plan(20, 2)]),
        start: detail,
      );

      await tester.tap(find.text(floorPlansButton));
      await settle(tester);

      expect(location(router), '/floor-plan/20?buildingId=$buildingId');

      await tearDownApp(tester);
    });

    testWidgets('hidden when no floor has an image', (tester) async {
      await pumpApp(tester,
          auth: verified,
          floors: FakeFloors([plan(10, 1, image: false)]),
          start: detail);

      expect(find.text(floorPlansButton), findsNothing);

      await tearDownApp(tester);
    });

    testWidgets('hidden when the plans cannot be loaded', (tester) async {
      await pumpApp(tester,
          auth: verified,
          floors: FakeFloors([plan(10, 1)])..failing = true,
          start: detail);

      expect(find.text(floorPlansButton), findsNothing);
      expect(find.byType(BuildingDetailScreen), findsOneWidget);

      await tearDownApp(tester);
    });
  });

  group('the viewer route', () {
    testWidgets('stays blocked for a visitor with the exact URL',
        (tester) async {
      final router = await pumpApp(tester,
          auth: visitorState(),
          floors: FakeFloors([plan(10, 1)]),
          start: '/building/$buildingId');

      router.go('/floor-plan/10?buildingId=$buildingId');
      await tester.pumpAndSettle();

      expect(location(router), '/map');
      expect(find.byType(FloorPlanScreen), findsNothing);

      await tearDownApp(tester);
    });

    testWidgets('leaving before the plans load does not crash',
        (tester) async {
      final floors = FakeFloors([plan(10, 1)]);
      final router = await pumpApp(tester,
          auth: verified, floors: floors, start: '/building/$buildingId');
      final hold = floors.hold = Completer<void>();

      router.push('/floor-plan/10?buildingId=$buildingId');
      await tester.pump();
      router.pop();
      await settle(tester);
      expect(find.byType(FloorPlanScreen), findsNothing);

      hold.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);

      await tearDownApp(tester);
    });
  });

  group('the building sheet', () {
    Widget sheetHost(AuthState auth, FloorPlanRepository floors) {
      final buildings = FakeBuildings();
      final rooms = FakeRooms();
      final facilities = FakeFacilities();
      final router = GoRouter(
        initialLocation: '/host',
        routes: [
          GoRoute(
            path: '/host',
            builder: (context, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => BuildingBottomSheet.show(context, hall),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/floor-plan/:id',
            builder: (_, s) => Scaffold(
              appBar: AppBar(),
              body: Text('viewer ${s.uri}'),
            ),
          ),
        ],
      );
      return RepositoryProvider<FloorPlanRepository>.value(
        value: floors,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthCubit>.value(value: SeededAuthCubit(state: auth)),
            BlocProvider(
                create: (_) => BuildingCubit(buildings, rooms, facilities)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
    }

    Future<void> openSheet(
        WidgetTester tester, AuthState auth, FakeFloors floors) async {
      usePhone(tester);
      await tester.pumpWidget(sheetHost(auth, floors));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await expandSheet(tester);
    }

    testWidgets('offers the plans, and Back returns to the sheet',
        (tester) async {
      await openSheet(tester, verified, FakeFloors([plan(10, 1)]));

      await tester.tap(find.text(floorPlansButton));
      await tester.pumpAndSettle();

      expect(find.text('viewer /floor-plan/10?buildingId=$buildingId'),
          findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Navigate Here'), findsOneWidget);
    });

    testWidgets('shows the chooser for several floors', (tester) async {
      await openSheet(tester, verified, FakeFloors([plan(10, 1), plan(20, 2)]));

      await tester.tap(find.text(floorPlansButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2F'));
      await tester.pumpAndSettle();

      expect(find.text('viewer /floor-plan/20?buildingId=$buildingId'),
          findsOneWidget);
    });

    testWidgets('hides it from a visitor', (tester) async {
      final floors = FakeFloors([plan(10, 1)]);
      await openSheet(tester, visitorState(), floors);

      expect(find.text('Navigate Here'), findsOneWidget);
      expect(find.text(floorPlansButton), findsNothing);
      expect(floors.loads, 0);
    });

    testWidgets('hides it when there is no plan', (tester) async {
      await openSheet(tester, verified, FakeFloors([]));

      expect(find.text('Navigate Here'), findsOneWidget);
      expect(find.text(floorPlansButton), findsNothing);
    });
  });

  group('the real map screen', () {
    void search(WidgetTester tester) => tester
        .element(find.byType(MapScreen))
        .read<SearchCubit>()
        .pickPlace(<String, dynamic>{
      'type': 'building',
      'id': '$buildingId',
      'name': 'Annex Hall',
      'subtitle': 'Building',
      'lat': 7.06,
      'lng': 125.59,
      'icon': Icons.business,
      'color': Colors.red,
    });

    testWidgets('debug build: the coordinates panel is on the map',
        (tester) async {
      await pumpApp(tester,
          auth: verified, floors: FakeFloors([]), start: '/map');

      expect(find.byType(DevLiveCoordinatePanel), findsOneWidget);

      await tearDownApp(tester);
    });

    testWidgets('flag off: no coordinates panel', (tester) async {
      final buildings = FakeBuildings();
      final rooms = FakeRooms();
      final facilities = FakeFacilities();
      await tester.pumpWidget(MultiBlocProvider(
        providers: [
          BlocProvider(
              create: (_) => BuildingCubit(buildings, rooms, facilities)),
          BlocProvider(create: (_) => OutdoorNavCubit(FakeOutdoor())),
          BlocProvider(
              create: (_) =>
                  SearchCubit(buildings, rooms, FakeIndoor(), facilities)),
        ],
        child: const MaterialApp(home: MapScreen(devTools: false)),
      ));
      await tester.pump();

      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.byType(DevLiveCoordinatePanel), findsNothing);

      await tearDownApp(tester);
    });

    testWidgets('a building found by search offers plans too', (tester) async {
      final router = await pumpApp(tester,
          auth: verified, floors: FakeFloors([plan(10, 1)]), start: '/map');

      search(tester);
      await tester.pumpAndSettle();
      await expandSheet(tester);

      await tester.tap(find.text(floorPlansButton));
      await settle(tester);
      expect(location(router), '/floor-plan/10?buildingId=$buildingId');

      await tearDownApp(tester);
    });

    testWidgets('a visitor finding a building by search sees no button',
        (tester) async {
      final floors = FakeFloors([plan(10, 1)]);
      await pumpApp(tester,
          auth: visitorState(), floors: floors, start: '/map');

      search(tester);
      await tester.pumpAndSettle();
      await expandSheet(tester);

      expect(find.text('Navigate Here'), findsOneWidget);
      expect(find.text(floorPlansButton), findsNothing);
      expect(floors.loads, 0);

      await tearDownApp(tester);
    });
  });
}
