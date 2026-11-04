import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:um_ar_mobile_app/data/models/building_model.dart';
import 'package:um_ar_mobile_app/data/models/facility_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_node_model.dart';
import 'package:um_ar_mobile_app/data/models/room_model.dart';
import 'package:um_ar_mobile_app/data/repositories/building_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/facility_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_ar_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/room_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/outdoor_nav_cubit.dart';
import 'package:um_ar_mobile_app/presentation/screens/ar/ar_navigation_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/ar/ar_screen.dart';
import 'package:um_ar_mobile_app/presentation/widgets/ar_info_card.dart';

const buildingId = 5;
const hallLat = 7.0670;
const hallLng = 125.5950;

const hall = BuildingModel(
  id: buildingId,
  name: 'Annex Hall',
  lat: hallLat,
  lng: hallLng,
  description: ['The building'],
);

const room = RoomModel(
  id: 7,
  buildingId: buildingId,
  roomName: 'Room 301',
  description: 'The room',
);

const facility = FacilityModel(
  id: 9,
  buildingId: buildingId,
  roomName: 'Clinic',
  description: ['The clinic'],
);

class FakeOutdoor implements OutdoorNavigationRepository {
  @override
  final List<OutdoorNodeModel> nodes = const [
    OutdoorNodeModel(id: 'a', lat: 7.0640, lng: hallLng),
    OutdoorNodeModel(id: 'b', lat: 7.0655, lng: hallLng),
  ];
  @override
  final List<OutdoorEdgeModel> edges = const [
    OutdoorEdgeModel(id: 'ab', fromNode: 'a', toNode: 'b'),
  ];
  @override
  bool get isLoaded => true;
  @override
  Future<void> loadGraph({bool forceRefresh = false}) async {}
  @override
  OutdoorNodeModel? nearestNode(double lat, double lng) => nodes.first;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAr implements OutdoorArRepository {
  @override
  Future<ArNetwork> getNetwork({bool forceRefresh = false}) async =>
      const ArNetwork(nodes: [], edges: []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
  Future<List<RoomModel>> getRoomsForBuilding(int buildingId) async =>
      const [room];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFacilities implements FacilityRepository {
  @override
  Future<List<FacilityModel>> getFacilitiesForBuilding(int buildingId) async =>
      const [facility];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fixes beside the building, too far from the route's end to arrive. The
/// first can beat the destination lookup, as on a phone; the next ones settle.
class FakeGps extends GeolocatorPlatform {
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      Stream.periodic(
        const Duration(milliseconds: 200),
        (_) => Position(
          latitude: hallLat,
          longitude: hallLng,
          timestamp: DateTime.utc(2026, 11, 1),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const compass = EventChannel('hemanthraj/flutter_compass');
  const accelerometer =
      EventChannel('dev.fluttercommunity.plus/sensors/accelerometer');
  const unity = MethodChannel('com.um.arnav/unity');
  final realGps = GeolocatorPlatform.instance;

  setUp(() {
    GeolocatorPlatform.instance = FakeGps();
    messenger.setMockMethodCallHandler(unity, (_) async => false);
    for (final channel in [compass, accelerometer]) {
      messenger.setMockStreamHandler(
          channel, MockStreamHandler.inline(onListen: (_, _) {}));
    }
  });
  tearDown(() {
    GeolocatorPlatform.instance = realGps;
    messenger.setMockMethodCallHandler(unity, null);
    for (final channel in [compass, accelerometer]) {
      messenger.setMockStreamHandler(channel, null);
    }
  });

  OutdoorNavCubit cubit() => OutdoorNavCubit(FakeOutdoor());

  Future<void> routeTo(OutdoorNavCubit nav, String? type, String? id) =>
      nav.findRouteBetween(
        fromNodeId: 'a',
        toNodeId: 'b',
        fromName: 'Gate',
        toName: 'Destination',
        toType: type,
        toId: id,
        toBuildingId: buildingId,
      );

  /// Opens AR from the real AR tab, as a user would.
  Future<void> openFromTab(WidgetTester tester, OutdoorNavCubit nav) async {
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<OutdoorArRepository>.value(value: FakeAr()),
        RepositoryProvider<BuildingRepository>.value(value: FakeBuildings()),
        RepositoryProvider<RoomRepository>.value(value: FakeRooms()),
        RepositoryProvider<FacilityRepository>.value(value: FakeFacilities()),
      ],
      child: BlocProvider<OutdoorNavCubit>.value(
        value: nav,
        child: const MaterialApp(home: ArScreen()),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byType(ElevatedButton));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  ARNavigationScreen arScreen(WidgetTester tester) =>
      tester.widget<ARNavigationScreen>(find.byType(ARNavigationScreen));

  String? cardTitle(WidgetTester tester) =>
      tester.widget<ArInfoCard>(find.byType(ArInfoCard)).info.title;

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  group('the route remembers the place picked', () {
    test('a room', () async {
      final nav = cubit();
      await routeTo(nav, 'room', '7');

      expect(nav.state.to?.placeType, 'room');
      expect(nav.state.to?.placeId, '7');
      expect(nav.state.to?.placeBuildingId, buildingId);
    });

    test('a re-route keeps it', () async {
      final nav = cubit();
      await routeTo(nav, 'facility', '9');

      await nav.rerouteFrom(hall.location);

      expect(nav.state.to?.placeType, 'facility');
      expect(nav.state.to?.placeId, '9');
      expect(nav.state.to?.placeBuildingId, buildingId);
    });

    test('clearing the route forgets it', () async {
      final nav = cubit();
      await routeTo(nav, 'room', '7');

      nav.clearRoute();

      expect(nav.state.to, isNull);
    });

    test('the Map tab hands it over', () {
      final map =
          File('lib/presentation/screens/map/map_screen.dart').readAsStringSync();

      expect(map, contains("toType: to['type']?.toString()"));
      expect(map, contains("toId: to['id']?.toString()"));
      expect(map, contains('toBuildingId: toBuildingId'));
    });
  });

  group('AR opened from the AR tab', () {
    testWidgets('a room trip shows the room card', (tester) async {
      final nav = cubit();
      await routeTo(nav, 'room', '7');

      await openFromTab(tester, nav);

      expect(arScreen(tester).destinationType, 'room');
      expect(arScreen(tester).destinationId, '7');
      expect(arScreen(tester).destinationBuildingId, buildingId);
      expect(cardTitle(tester), 'Room 301');

      await close(tester);
    });

    testWidgets('a facility trip shows the facility card', (tester) async {
      final nav = cubit();
      await routeTo(nav, 'facility', '9');

      await openFromTab(tester, nav);

      expect(cardTitle(tester), 'Clinic');

      await close(tester);
    });

    testWidgets('a building trip still shows the building card',
        (tester) async {
      final nav = cubit();
      await routeTo(nav, 'building', '$buildingId');

      await openFromTab(tester, nav);

      expect(cardTitle(tester), 'Annex Hall');

      await close(tester);
    });

    testWidgets('a route to a building from its detail screen has no place',
        (tester) async {
      final nav = cubit();
      await nav.findRouteBetween(fromNodeId: 'a', toNodeId: 'b');

      await openFromTab(tester, nav);

      expect(arScreen(tester).destinationType, isNull);
      expect(arScreen(tester).destinationId, isNull);

      await close(tester);
    });

    testWidgets('with no route, the compass gets no place', (tester) async {
      final nav = cubit();

      await openFromTab(tester, nav);

      expect(arScreen(tester).destinationType, isNull);
      expect(arScreen(tester).destinationId, isNull);

      await close(tester);
    });
  });
}
