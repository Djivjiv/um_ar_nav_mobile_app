import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:um_ar_mobile_app/data/models/building_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_node_model.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/repository_exception.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/outdoor_nav_cubit.dart';

/// a — b — c(entrance of building 1), `d` connected to nothing, and `oneWay`
/// which can only be walked out of, towards a.
class FakeRepo implements OutdoorNavigationRepository {
  FakeRepo({this.failLoad = false, this.emptyGraph = false});

  bool failLoad;
  final bool emptyGraph;
  bool _loaded = false;

  static const allNodes = [
    OutdoorNodeModel(id: 'a', lat: 7.0660, lng: 125.5940, name: 'Gate'),
    OutdoorNodeModel(id: 'b', lat: 7.0665, lng: 125.5945),
    OutdoorNodeModel(
        id: 'c', lat: 7.0670, lng: 125.5950, buildingId: 1, isEntrance: true),
    OutdoorNodeModel(id: 'd', lat: 7.0700, lng: 125.6000),
    OutdoorNodeModel(id: 'oneWay', lat: 7.0655, lng: 125.5935),
    // About 1.5 km from c: long enough for the walking time to show the speed.
    OutdoorNodeModel(id: 'far', lat: 7.0805, lng: 125.5950),
  ];
  static const allEdges = [
    OutdoorEdgeModel(id: 'ab', fromNode: 'a', toNode: 'b', weight: 70),
    OutdoorEdgeModel(id: 'bc', fromNode: 'b', toNode: 'c', weight: 70),
    OutdoorEdgeModel(id: 'cf', fromNode: 'c', toNode: 'far', weight: 1500),
    OutdoorEdgeModel(
        id: 'oa', fromNode: 'oneWay', toNode: 'a', weight: 70, isTwoWay: false),
  ];

  @override
  List<OutdoorNodeModel> get nodes =>
      _loaded && !emptyGraph ? allNodes : const [];
  @override
  List<OutdoorEdgeModel> get edges =>
      _loaded && !emptyGraph ? allEdges : const [];
  @override
  bool get isLoaded => _loaded;

  @override
  Future<void> loadGraph({bool forceRefresh = false}) async {
    if (failLoad) throw RepositoryException('Could not load the campus map.');
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

const building = BuildingModel(id: 1, name: 'Library', lat: 7.0671, lng: 125.5951);

/// Right next to node `b`.
const nearB = LatLng(7.06651, 125.59451);

void main() {
  group('route found', () {
    test('the route, its steps, distance and walking time', () async {
      final cubit = OutdoorNavCubit(FakeRepo());

      await cubit.findRouteBetween(
          fromNodeId: 'a', toNodeId: 'c', fromName: 'Gate', toName: 'Library');

      final s = cubit.state;
      expect(s.status, OutdoorNavStatus.routeReady);
      expect(s.hasRoute, isTrue);
      expect(s.pathNodeIds, ['a', 'b', 'c']);
      expect(s.path, hasLength(3));
      expect(s.waypointCount, 3);
      expect(s.distanceMeters, greaterThan(0));
      expect(s.walkMinutes, (s.distanceMeters / 1.33 / 60).ceil());
      expect(s.instructions, isNotEmpty);
      expect(s.currentStep, 0);
      expect(s.from?.label, 'Gate');
      expect(s.to?.label, 'Library');
      expect(s.error, isNull);
    });

    test('walking time is at 1.33 m/s, rounded up', () async {
      final cubit = OutdoorNavCubit(FakeRepo());

      await cubit.findRouteBetween(fromNodeId: 'a', toNodeId: 'far');

      final meters = cubit.state.distanceMeters;
      expect(meters, greaterThan(1000));
      expect(cubit.state.walkMinutes, (meters / 1.33 / 60).ceil());
    });

    test('the place picked in the planner stays on the route', () async {
      final cubit = OutdoorNavCubit(FakeRepo());

      await cubit.findRouteBetween(
          fromNodeId: 'a',
          toNodeId: 'c',
          toType: 'room',
          toId: '7',
          toBuildingId: 1);

      expect(cubit.state.to?.placeType, 'room');
      expect(cubit.state.to?.placeId, '7');
      expect(cubit.state.to?.placeBuildingId, 1);
    });

    test('a route to a building ends at its entrance', () async {
      final cubit = OutdoorNavCubit(FakeRepo());

      await cubit.routeToBuilding(building, fromNodeId: 'a');

      expect(cubit.state.pathNodeIds.last, 'c');
      expect(cubit.state.to?.isBuilding, isTrue);
    });

    test('clearRoute forgets the route but keeps the graph', () async {
      final repo = FakeRepo();
      final cubit = OutdoorNavCubit(repo);
      await cubit.findRouteBetween(fromNodeId: 'a', toNodeId: 'c');

      cubit.clearRoute();

      expect(cubit.state.hasRoute, isFalse);
      expect(cubit.state.status, OutdoorNavStatus.graphReady);
      expect(cubit.state.to, isNull);
      expect(repo.isLoaded, isTrue);
    });

    test('steps stop at both ends of the list', () async {
      final cubit = OutdoorNavCubit(FakeRepo());
      await cubit.findRouteBetween(fromNodeId: 'a', toNodeId: 'c');
      final last = cubit.state.instructions.length - 1;

      cubit.previousStep();
      expect(cubit.state.currentStep, 0);

      for (var i = 0; i < last + 3; i++) {
        cubit.nextStep();
      }
      expect(cubit.state.currentStep, last);

      cubit.goToStep(last + 1);
      expect(cubit.state.currentStep, last);
    });
  });

  group('no route', () {
    test('points on separate parts of the network say so', () async {
      final cubit = OutdoorNavCubit(FakeRepo());

      await cubit.findRouteBetween(fromNodeId: 'a', toNodeId: 'd');

      expect(cubit.state.status, OutdoorNavStatus.error);
      expect(cubit.state.hasRoute, isFalse);
      expect(cubit.state.error,
          'These two points are not connected on the campus path network.');
    });

    test('a one-way path is not walked backwards', () async {
      final cubit = OutdoorNavCubit(FakeRepo());

      await cubit.findRouteBetween(fromNodeId: 'a', toNodeId: 'oneWay');
      expect(cubit.state.hasRoute, isFalse);

      await cubit.findRouteBetween(fromNodeId: 'oneWay', toNodeId: 'a');
      expect(cubit.state.hasRoute, isTrue);
    });

    test('the same start and end is an error, not an empty route', () async {
      final cubit = OutdoorNavCubit(FakeRepo());

      await cubit.findRouteBetween(fromNodeId: 'a', toNodeId: 'a');

      expect(cubit.state.status, OutdoorNavStatus.error);
      expect(cubit.state.error, 'Start and destination are the same point.');
    });

    test('an empty graph says the map data is missing', () async {
      final cubit = OutdoorNavCubit(FakeRepo(emptyGraph: true));

      await cubit.findRouteBetween(fromNodeId: 'a', toNodeId: 'c');

      expect(cubit.state.error, 'Campus map data is not available yet.');
    });

    test('a failed graph load shows its message', () async {
      final cubit = OutdoorNavCubit(FakeRepo(failLoad: true));

      expect(await cubit.ensureGraph(), isFalse);

      expect(cubit.state.status, OutdoorNavStatus.error);
      expect(cubit.state.error, 'Could not load the campus map.');
    });

    test('a start that is not on the network is refused', () async {
      final cubit = OutdoorNavCubit(FakeRepo());
      cubit.setFrom(const NavEndpoint(label: 'Somewhere'));
      cubit.setTo(const NavEndpoint(label: 'Library', buildingId: 1));

      await cubit.findRoute();

      expect(cubit.state.error, 'Starting point is not on the path network.');
    });

    test('a missing endpoint is refused', () async {
      final cubit = OutdoorNavCubit(FakeRepo());

      await cubit.findRoute();

      expect(cubit.state.error, 'Choose both a start and a destination.');
    });
  });

  group('reroute', () {
    test('starts from the node nearest the user, to the same place', () async {
      final cubit = OutdoorNavCubit(FakeRepo());
      await cubit.findRouteBetween(
          fromNodeId: 'a',
          toNodeId: 'c',
          toName: 'Clinic',
          toType: 'facility',
          toId: '9',
          toBuildingId: 1);

      expect(await cubit.rerouteFrom(nearB), isTrue);

      final s = cubit.state;
      expect(s.pathNodeIds, ['b', 'c']);
      expect(s.from?.label, 'Current location');
      expect(s.to?.label, 'Clinic');
      expect(s.to?.placeType, 'facility');
      expect(s.to?.placeId, '9');
      expect(s.to?.placeBuildingId, 1);
    });

    test('a building destination is kept too', () async {
      final cubit = OutdoorNavCubit(FakeRepo());
      await cubit.routeToBuilding(building, fromNodeId: 'a');

      expect(await cubit.rerouteFrom(nearB), isTrue);

      expect(cubit.state.pathNodeIds, ['b', 'c']);
      expect(cubit.state.to?.buildingId, 1);
      expect(cubit.state.from?.nodeId, 'b');
    });

    test('nowhere to go: nothing to reroute', () async {
      final cubit = OutdoorNavCubit(FakeRepo());
      await cubit.ensureGraph();

      expect(await cubit.rerouteFrom(nearB), isFalse);
    });

    test('an empty graph: reports failure', () async {
      final cubit = OutdoorNavCubit(FakeRepo(emptyGraph: true));
      cubit.setTo(const NavEndpoint(label: 'Library', nodeId: 'c'));

      expect(await cubit.rerouteFrom(nearB), isFalse);
    });

    test('a destination cut off from the user: reports failure', () async {
      final cubit = OutdoorNavCubit(FakeRepo());
      cubit.setTo(const NavEndpoint(label: 'Far', nodeId: 'd'));

      expect(await cubit.rerouteFrom(nearB), isFalse);
      expect(cubit.state.hasRoute, isFalse);
      expect(cubit.state.error, isNotNull);
    });

    test('rerouting at the destination reports failure', () async {
      final cubit = OutdoorNavCubit(FakeRepo());
      await cubit.findRouteBetween(fromNodeId: 'a', toNodeId: 'c');

      // Right on c: start and end are the same node.
      expect(await cubit.rerouteFrom(FakeRepo.allNodes[2].point), isFalse);
    });
  });
}
