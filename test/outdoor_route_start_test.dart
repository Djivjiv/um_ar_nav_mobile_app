import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:um_ar_mobile_app/data/models/building_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_node_model.dart';
import 'package:um_ar_mobile_app/data/repositories/building_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/repository_exception.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/outdoor_nav_cubit.dart';
import 'package:um_ar_mobile_app/presentation/widgets/route_start_picker.dart';

/// A small campus graph: `first` is listed first but is NOT the right start
/// for anything below (the old code started there when it had no origin).
///
///   first(far west) — d(entrance of building 2) — a — b — c(entrance of 1)
class FakeOutdoorRepo implements OutdoorNavigationRepository {
  FakeOutdoorRepo({this.failLoads = 0});

  int failLoads;
  int loadCalls = 0;
  bool _loaded = false;

  static const _nodes = [
    OutdoorNodeModel(id: 'first', lat: 7.0650, lng: 125.5900),
    OutdoorNodeModel(
        id: 'd', lat: 7.0655, lng: 125.5935, buildingId: 2, isEntrance: true),
    OutdoorNodeModel(id: 'a', lat: 7.0660, lng: 125.5940),
    OutdoorNodeModel(id: 'b', lat: 7.0665, lng: 125.5945),
    OutdoorNodeModel(
        id: 'c', lat: 7.0670, lng: 125.5950, buildingId: 1, isEntrance: true),
  ];
  static const _edges = [
    OutdoorEdgeModel(id: 'e0', fromNode: 'first', toNode: 'd', weight: 400),
    OutdoorEdgeModel(id: 'e1', fromNode: 'd', toNode: 'a', weight: 80),
    OutdoorEdgeModel(id: 'e2', fromNode: 'a', toNode: 'b', weight: 80),
    OutdoorEdgeModel(id: 'e3', fromNode: 'b', toNode: 'c', weight: 80),
  ];

  @override
  List<OutdoorNodeModel> get nodes => _loaded ? _nodes : const [];
  @override
  List<OutdoorEdgeModel> get edges => _loaded ? _edges : const [];
  @override
  bool get isLoaded => _loaded;

  @override
  Future<void> loadGraph({bool forceRefresh = false}) async {
    loadCalls++;
    if (failLoads > 0) {
      failLoads--;
      throw RepositoryException('Could not load the campus map.');
    }
    _loaded = true;
  }

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

class FakeBuildingRepo implements BuildingRepository {
  @override
  Future<List<BuildingModel>> getBuildings({bool forceRefresh = false}) async =>
      const [destination, startBuilding];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const destination =
    BuildingModel(id: 1, name: 'Bldg One', lat: 7.0671, lng: 125.5951);
const startBuilding =
    BuildingModel(id: 2, name: 'Bldg Two', lat: 7.0654, lng: 125.5934);

/// Right next to node `a`.
const nearA = LatLng(7.06601, 125.59401);

void main() {
  group('routeToBuilding never guesses a start (item 1)', () {
    test('no origin → clear error, no route, not the first node', () async {
      final cubit = OutdoorNavCubit(FakeOutdoorRepo());
      await cubit.routeToBuilding(destination);
      expect(cubit.state.status, OutdoorNavStatus.error);
      expect(cubit.state.error, OutdoorNavCubit.noStartPointMessage);
      expect(cubit.state.hasRoute, isFalse);
      expect(cubit.state.from?.nodeId, isNot('first'));
    });

    test('a GPS point starts at the nearest node', () async {
      final cubit = OutdoorNavCubit(FakeOutdoorRepo());
      await cubit.routeToBuilding(destination, fromPoint: nearA);
      expect(cubit.state.status, OutdoorNavStatus.routeReady);
      expect(cubit.state.pathNodeIds, ['a', 'b', 'c']);
    });

    test('an unknown start node id is an error, not the first node',
        () async {
      final cubit = OutdoorNavCubit(FakeOutdoorRepo());
      await cubit.routeToBuilding(destination, fromNodeId: 'nope');
      expect(cubit.state.status, OutdoorNavStatus.error);
      expect(cubit.state.hasRoute, isFalse);
    });

    test('nearestNodeIdWithin rejects a fix far from every node', () async {
      final cubit = OutdoorNavCubit(FakeOutdoorRepo());
      await cubit.ensureGraph();
      expect(cubit.nearestNodeIdWithin(nearA, 150), 'a');
      // Manila — hundreds of km away.
      expect(cubit.nearestNodeIdWithin(const LatLng(14.6, 121.0), 150),
          isNull);
    });

    test('startNodeForBuilding uses the building entrance', () async {
      final cubit = OutdoorNavCubit(FakeOutdoorRepo());
      await cubit.ensureGraph();
      expect(
          cubit.startNodeForBuilding(startBuilding,
              towards: destination.location),
          'd');
    });
  });

  group('Retry works after an error (item 2)', () {
    test('a failed graph load is retried on the next call', () async {
      final repo = FakeOutdoorRepo(failLoads: 1);
      final cubit = OutdoorNavCubit(repo);

      await cubit.routeToBuilding(destination, fromPoint: nearA);
      expect(cubit.state.status, OutdoorNavStatus.error);

      await cubit.routeToBuilding(destination, fromPoint: nearA);
      expect(repo.loadCalls, 2);
      expect(cubit.state.status, OutdoorNavStatus.routeReady);
    });

    test('a previous route error does not block the next attempt', () async {
      final cubit = OutdoorNavCubit(FakeOutdoorRepo());
      await cubit.routeToBuilding(destination); // no start → error
      expect(cubit.state.status, OutdoorNavStatus.error);

      await cubit.routeToBuilding(destination, fromPoint: nearA);
      expect(cubit.state.status, OutdoorNavStatus.routeReady);
    });

    test('findRoute also runs after an error', () async {
      final cubit = OutdoorNavCubit(FakeOutdoorRepo());
      await cubit.routeToBuilding(destination); // error
      cubit.setFrom(const NavEndpoint(label: 'A', nodeId: 'a'));
      cubit.setTo(const NavEndpoint(label: 'One', buildingId: 1));
      await cubit.findRoute();
      expect(cubit.state.status, OutdoorNavStatus.routeReady);
    });
  });

  group('startRouteToBuilding — GPS, else ask (building-detail Navigate)', () {
    late OutdoorNavCubit cubit;
    bool? started;

    Future<void> pumpButton(WidgetTester tester, LocateUser locate) async {
      started = null;
      await tester.pumpWidget(
        RepositoryProvider<BuildingRepository>.value(
          value: FakeBuildingRepo(),
          child: BlocProvider.value(
            value: cubit,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () async => started = await startRouteToBuilding(
                        ctx, destination,
                        locate: locate),
                    child: const Text('Navigate Here'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Navigate Here'));
      await tester.pumpAndSettle();
    }

    setUp(() => cubit = OutdoorNavCubit(FakeOutdoorRepo()));

    testWidgets('uses the GPS fix when it is on campus', (tester) async {
      await pumpButton(tester, () async => nearA);
      expect(find.text('Where are you starting from?'), findsNothing);
      expect(started, isTrue);
      expect(cubit.state.pathNodeIds.first, 'a');
      expect(cubit.state.from?.label, 'Your location');
    });

    testWidgets('no GPS → asks, then starts at the chosen building',
        (tester) async {
      await pumpButton(tester, () async => null);
      expect(find.text('Where are you starting from?'), findsOneWidget);
      expect(find.textContaining("couldn't get your location"),
          findsOneWidget);
      // The destination itself is not offered as a start.
      expect(find.widgetWithText(ListTile, 'Bldg One'), findsNothing);

      await tester.tap(find.text('Bldg Two'));
      await tester.pumpAndSettle();
      expect(started, isTrue);
      expect(cubit.state.status, OutdoorNavStatus.routeReady);
      expect(cubit.state.pathNodeIds, ['d', 'a', 'b', 'c']);
      expect(cubit.state.from?.label, 'Bldg Two');
    });

    testWidgets('GPS far off campus also asks', (tester) async {
      await pumpButton(tester, () async => const LatLng(14.6, 121.0));
      expect(find.textContaining("don't seem to be on campus"),
          findsOneWidget);
    });

    testWidgets('cancelling the picker requests no route', (tester) async {
      await pumpButton(tester, () async => null);
      await tester.tapAt(const Offset(5, 5)); // tap the scrim
      await tester.pumpAndSettle();
      expect(started, isFalse);
      expect(cubit.state.hasRoute, isFalse);
    });
  });
}
