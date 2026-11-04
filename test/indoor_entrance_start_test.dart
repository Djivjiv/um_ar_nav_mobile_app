import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:um_ar_mobile_app/core/constants/visitor_text.dart';
import 'package:um_ar_mobile_app/core/utils/indoor_entrance.dart';
import 'package:um_ar_mobile_app/core/utils/indoor_route_helpers.dart';
import 'package:um_ar_mobile_app/core/utils/navigation_phase_manager.dart';
import 'package:um_ar_mobile_app/core/utils/server_clock.dart';
import 'package:um_ar_mobile_app/data/models/floor_plan_model.dart';
import 'package:um_ar_mobile_app/data/models/indoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/indoor_node_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_edge_model.dart';
import 'package:um_ar_mobile_app/data/models/outdoor_node_model.dart';
import 'package:um_ar_mobile_app/data/models/user_profile_model.dart';
import 'package:um_ar_mobile_app/data/models/visitor_session_model.dart';
import 'package:um_ar_mobile_app/data/repositories/feedback_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/floor_plan_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/indoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';
import 'package:um_ar_mobile_app/domain/services/dijkstra_service.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/outdoor_nav_cubit.dart';
import 'package:um_ar_mobile_app/presentation/routes/app_router.dart';
import 'package:um_ar_mobile_app/presentation/screens/map/map_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/navigation/multi_phase_nav_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/navigation/turn_by_turn_screen.dart';
import 'package:um_ar_mobile_app/presentation/widgets/feedback_comment_card.dart';
import 'package:um_ar_mobile_app/presentation/widgets/visitor_indoor_steps.dart';

import 'support/feedback_fakes.dart';
import 'support/visitor_fakes.dart';

const buildingId = 1;

FloorPlanModel floor(int number) =>
    FloorPlanModel(id: number * 10, buildingId: buildingId, floorNumber: number);

IndoorNodeModel indoor(
  String id,
  int floorNumber, {
  double x = 0,
  double y = 0,
  String? label,
  String? outdoorNodeId,
  String? entranceLabel,
  String? stairGroup,
  int? linkedRoomId,
  bool isEntrance = false,
  bool isNavigable = true,
}) =>
    IndoorNodeModel(
      id: id,
      floorPlanId: '${floorNumber * 10}',
      buildingId: buildingId,
      x: x,
      y: y,
      label: label,
      outdoorNodeId: outdoorNodeId,
      entranceLabel: entranceLabel,
      stairGroup: stairGroup,
      linkedRoomId: linkedRoomId,
      linkedTable: linkedRoomId == null ? null : 'rooms',
      isEntrance: isEntrance,
      isNavigable: isNavigable,
      floor: floorNumber,
    );

OutdoorNodeModel outdoor(
  String id,
  double lat, {
  String? indoorNodeId,
  String? label,
  int? building = buildingId,
  bool isEntrance = true,
}) =>
    OutdoorNodeModel(
      id: id,
      lat: lat,
      lng: 125.59,
      buildingId: building,
      isEntrance: isEntrance,
      entranceLabel: label,
      indoorNodeId: indoorNodeId,
    );

IndoorEdgeModel edge(String from, String to) =>
    IndoorEdgeModel(id: '$from-$to', fromNode: from, toNode: to);

/// Floor 1: West Door (a) and East Door (b) both reach a corridor, then the
/// room. West is 5 m from the corridor, East 10 m, so the first direction
/// shows which door the route really starts at. d_room is a room door, which
/// carries the same flags as a building entrance.
final westDoor = indoor('a', 1,
    x: 100, label: 'entrance', isEntrance: true, outdoorNodeId: 'out_a');
final eastDoor = indoor('b', 1,
    x: 400, label: 'entrance', isEntrance: true, outdoorNodeId: 'out_b');
final corridor = indoor('c', 1, x: 200, label: 'pathway');
final room = indoor('r', 1, x: 200, y: 100, linkedRoomId: 7);
final roomDoor = indoor('d_room', 1, x: 200, y: 300, label: 'entrance', isEntrance: true);
final floor1Nodes = [roomDoor, westDoor, eastDoor, corridor, room];
final floor1Edges = [edge('a', 'c'), edge('b', 'c'), edge('c', 'r')];

final westOut = outdoor('out_a', 7.0600, indoorNodeId: 'a', label: 'West Door');
final eastOut = outdoor('out_b', 7.0700, indoorNodeId: 'b', label: 'East Door');

class FakeOutdoorRepo implements OutdoorNavigationRepository {
  @override
  final List<OutdoorNodeModel> nodes;
  FakeOutdoorRepo(this.nodes);

  @override
  List<OutdoorEdgeModel> get edges => const [];
  @override
  bool get isLoaded => true;
  @override
  Future<void> loadGraph({bool forceRefresh = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFloorRepo implements FloorPlanRepository {
  final List<FloorPlanModel> floors;
  FakeFloorRepo(this.floors);

  @override
  Future<List<FloorPlanModel>> getFloorsForBuilding(int buildingId) async =>
      floors;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeIndoorRepo implements IndoorNavigationRepository {
  final List<IndoorNodeModel> nodes;
  final List<IndoorEdgeModel> edges;
  FakeIndoorRepo(this.nodes, this.edges);

  @override
  Future<List<IndoorNodeModel>> getNodesForFloor(String floorPlanId) async =>
      nodes.where((n) => n.floorPlanId == floorPlanId).toList();

  @override
  Future<List<IndoorEdgeModel>> getEdgesForFloor(String floorPlanId) async {
    final ids = nodes
        .where((n) => n.floorPlanId == floorPlanId)
        .map((n) => n.id)
        .toSet();
    return edges.where((e) => ids.contains(e.fromNode)).toList();
  }

  @override
  void clearCache() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A trip that has finished its outdoor leg (or never had one) and is at the
/// stairs / elevator phase. `outdoorPath` stays empty so no GPS stream starts.
NavigationRoute arrivalRoute({String? arrivedAt, int destFloor = 1}) =>
    NavigationRoute(
      from: const {'type': 'building', 'id': '2', 'name': 'Gym'},
      to: {
        'type': 'room',
        'id': '7',
        'building_id': buildingId,
        'name': 'Room 7',
        'floor': destFloor,
      },
      phases: const [
        NavigationPhase.outdoorNavigation,
        NavigationPhase.elevatorOrStairs,
        NavigationPhase.indoorNavigation,
        NavigationPhase.arrived,
      ],
      currentPhaseIndex: 1,
      arrivalOutdoorNodeId: arrivedAt,
      destBuildingId: '$buildingId',
      destBuildingName: 'Main',
      destRoomName: 'Room 7',
      destFloor: destFloor,
    );

Future<void> pumpTrip(
  WidgetTester tester, {
  required NavigationRoute route,
  List<OutdoorNodeModel>? outdoorNodes,
  List<IndoorNodeModel>? indoorNodes,
  List<IndoorEdgeModel>? indoorEdges,
  List<FloorPlanModel>? floors,
  LatLng? here,
  bool settle = true,
  AuthCubit? auth,
  FeedbackWorld? feedback,
}) async {
  final screen = MultiPhaseNavScreen(
    navigationRoute: route,
    locate: () async => here,
  );
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<FloorPlanRepository>.value(
            value: FakeFloorRepo(floors ?? [floor(1)])),
        RepositoryProvider<IndoorNavigationRepository>.value(
          value: FakeIndoorRepo(
              indoorNodes ?? floor1Nodes, indoorEdges ?? floor1Edges),
        ),
        if (feedback != null) ...[
          RepositoryProvider<SurveyRepository>.value(value: feedback.survey),
          RepositoryProvider<FeedbackRepository>.value(
              value: feedback.feedback),
        ],
      ],
      child: BlocProvider(
        create: (_) => OutdoorNavCubit(
            FakeOutdoorRepo(outdoorNodes ?? [westOut, eastOut])),
        child: MaterialApp(
          home: auth == null
              ? screen
              : BlocProvider.value(value: auth, child: screen),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final nearEast = const LatLng(7.0699, 125.59);

/// About 1.5 km from both doors, like testing off campus.
final farAway = const LatLng(7.0850, 125.59);
final _noLinkMessage = "isn't linked to the indoor map";

const noDataMessage =
    "Indoor directions aren't available for this building yet.";

/// A floor 1 plan holding [nodes].
List<FloorNodes> floor1With(List<IndoorNodeModel> nodes) =>
    [(plan: floor(1), nodes: nodes)];

/// A trip from the building itself to a room inside it: no outdoor leg, and
/// the origin is not a room.
NavigationRoute ownBuildingRoute({int destFloor = 1, String roomId = '7'}) =>
    NavigationRoute(
      from: const {'type': 'building', 'id': '$buildingId', 'name': 'Main'},
      to: {
        'type': 'room',
        'id': roomId,
        'building_id': buildingId,
        'name': 'Room $roomId',
        'floor': destFloor,
      },
      phases: NavigationRoute.determinePhases(
        from: const {'type': 'building', 'id': '$buildingId'},
        to: {'type': 'room', 'id': roomId, 'building_id': buildingId},
      ),
      destBuildingId: '$buildingId',
      destBuildingName: 'Main',
      destRoomName: 'Room $roomId',
      destFloor: destFloor,
    );

void main() {
  group('decideIndoorStart', () {
    final entrances = buildingEntrances(
      buildingId: buildingId,
      outdoorNodes: [westOut, eastOut],
      floors: floor1With(floor1Nodes),
    );

    Future<IndoorStartDecision> decide(
      List<BuildingEntrance> entrances, {
      String? arrivedAt,
      LatLng? here,
    }) =>
        decideIndoorStart(
          entrances: entrances,
          arrivedOutdoorNodeId: arrivedAt,
          locate: () async => here,
        );

    test('the arrival entrance wins, even with GPS nearer another one',
        () async {
      final d = await decide(entrances, arrivedAt: 'out_a', here: nearEast);
      expect(d.kind, IndoorStartKind.arrived);
      expect(d.entrance!.indoorNode!.id, 'a');
    });

    test('GPS is not asked for when the arrival entrance is known', () async {
      var located = false;
      await decideIndoorStart(
        entrances: entrances,
        arrivedOutdoorNodeId: 'out_a',
        locate: () async {
          located = true;
          return nearEast;
        },
      );
      expect(located, isFalse);
    });

    test('a real route to the second entrance starts at the second', () async {
      final path = DijkstraService.findPathToBuilding(
        startNodeId: 'gate',
        buildingId: buildingId,
        nodes: [
          westOut,
          eastOut,
          outdoor('gate', 7.0800, building: null, isEntrance: false),
        ],
        edges: const [
          OutdoorEdgeModel(id: 'e1', fromNode: 'gate', toNode: 'out_b', weight: 10),
          OutdoorEdgeModel(id: 'e2', fromNode: 'gate', toNode: 'out_a', weight: 90),
        ],
      )!;
      final d = await decide(entrances, arrivedAt: path.nodeIds.last);
      expect(d.kind, IndoorStartKind.arrived);
      expect(d.entrance!.indoorNode!.id, 'b');
    });

    test('with no route, the entrance nearest the GPS position', () async {
      final d = await decide(entrances, here: nearEast);
      expect(d.kind, IndoorStartKind.nearest);
      expect(d.entrance!.outdoorNode!.id, 'out_b');
    });

    test('GPS still counts about 100 m from the entrance', () async {
      final d = await decide(entrances, here: const LatLng(7.0691, 125.59));
      expect(d.kind, IndoorStartKind.nearest);
      expect(d.entrance!.outdoorNode!.id, 'out_b');
    });

    test('GPS beyond 150 m from every entrance is ignored', () async {
      for (final here in [const LatLng(7.0718, 125.59), farAway]) {
        final d = await decide(entrances, here: here);
        expect(d.kind, IndoorStartKind.choose);
        expect(d.entrance, isNull);
      }
    });

    test('a route that ended elsewhere is not an arrival', () async {
      final d = await decide(entrances, arrivedAt: 'some_other_building_door');
      expect(d.kind, IndoorStartKind.choose);
    });

    test('nothing known → the user chooses', () async {
      expect((await decide(entrances)).kind, IndoorStartKind.choose);
    });

    test('no entrances → no data, whatever else is known', () async {
      final d = await decide(const [], arrivedAt: 'out_a', here: nearEast);
      expect(d.kind, IndoorStartKind.noData);
    });

    test('entrances with no link at all → not linked, not no data', () async {
      final unlinked = buildingEntrances(
        buildingId: buildingId,
        outdoorNodes: [outdoor('o', 7.06, label: 'Side Door')],
        floors: floor1With(floor1Nodes),
      );
      final d = await decide(unlinked, here: nearEast);
      expect(d.kind, IndoorStartKind.notLinked);
      expect(d.entrance, isNull);
    });

    test('arriving at an entrance with no link names that entrance', () async {
      final unlinked = buildingEntrances(
        buildingId: buildingId,
        outdoorNodes: [outdoor('o', 7.06, label: 'Side Door')],
        floors: floor1With(floor1Nodes),
      );
      final d = await decide(unlinked, arrivedAt: 'o');
      expect(d.kind, IndoorStartKind.notLinked);
      expect(d.entrance!.name, 'Side Door');
    });
  });

  group('buildingEntrances', () {
    List<BuildingEntrance> build(List<OutdoorNodeModel> outdoorNodes) =>
        buildingEntrances(
          buildingId: buildingId,
          outdoorNodes: outdoorNodes,
          floors: floor1With(floor1Nodes),
        );

    test('room doors are not building entrances', () {
      final ids = build([westOut, eastOut]).map((e) => e.indoorNode!.id);
      expect(ids, ['a', 'b']);
    });

    test('other buildings are left out', () {
      expect(build([outdoor('x', 7.06, building: 2, indoorNodeId: 'a')]), isEmpty);
    });

    test('the reverse link alone is enough', () {
      final e = build([outdoor('out_a', 7.06, label: 'West Door')]).single;
      expect(e.indoorNode!.id, 'a');
    });

    test('the reverse link counts even on an outdoor row with no building', () {
      final e = build([
        outdoor('out_a', 7.06, label: 'West Door', building: null, isEntrance: false),
      ]).single;
      expect(e.indoorNode!.id, 'a');
    });

    test('a link to a gone or non-navigable node is not a link', () {
      final blocked = indoor('blocked', 1, isNavigable: false);
      final entrances = buildingEntrances(
        buildingId: buildingId,
        outdoorNodes: [
          outdoor('o1', 7.06, indoorNodeId: 'deleted'),
          outdoor('o2', 7.07, indoorNodeId: 'blocked'),
        ],
        floors: floor1With([...floor1Nodes, blocked]),
      );
      expect(entrances.map((e) => e.isLinked), [false, false]);
    });

    test('no indoor nodes (gate, building with no rooms) → no entrances', () {
      for (final floors in <List<FloorNodes>>[const [], floor1With(const [])]) {
        expect(
          buildingEntrances(
            buildingId: buildingId,
            outdoorNodes: [westOut],
            floors: floors,
          ),
          isEmpty,
        );
      }
    });

    test('a name never falls back to a raw id', () {
      final e = build([outdoor('out_a', 7.06, indoorNodeId: 'a')]).single;
      expect(e.name, 'Entrance');
    });
  });

  test('determinePhases: building → its own room has no outdoor leg', () {
    final phases = NavigationRoute.determinePhases(
      from: {'type': 'building', 'id': '1'},
      to: {'type': 'room', 'id': '7', 'building_id': 1},
    );
    expect(phases, [
      NavigationPhase.elevatorOrStairs,
      NavigationPhase.indoorNavigation,
      NavigationPhase.arrived,
    ]);
  });

  test('determinePhases: a room in another building keeps its outdoor leg', () {
    final phases = NavigationRoute.determinePhases(
      from: {'type': 'building', 'id': '2'},
      to: {'type': 'room', 'id': '7', 'building_id': 1},
    );
    expect(phases, [
      NavigationPhase.outdoorNavigation,
      NavigationPhase.elevatorOrStairs,
      NavigationPhase.indoorNavigation,
      NavigationPhase.arrived,
    ]);
  });

  test('stairs still match from an entrance on a non-lowest floor', () {
    final floors = [floor(1), floor(2), floor(3)];
    final plans =
        pickIndoorFloorPlans(floors: floors, originFloor: 2, destFloor: 1);
    expect(plans.start!.floorNumber, 2);
    expect(plans.dest!.floorNumber, 1);

    final choice = chooseStairGroup(
      startFloorNodes: [indoor('s2', 2, label: 'stairs', stairGroup: 'A')],
      destFloorNodes: [indoor('s1', 1, label: 'stairs', stairGroup: 'A')],
      transport: 'stairs',
      costToTransport: (_) => 1,
      costFromTransport: (_) => 1,
    );
    expect(choice!.startFloorNode.id, 's2');
    expect(choice.destFloorNode.id, 's1');
  });

  group('MultiPhaseNavScreen', () {
    testWidgets('two entrances: arriving at the second starts at the second',
        (tester) async {
      await pumpTrip(tester, route: arrivalRoute(arrivedAt: 'out_b'));

      expect(find.text('Start from: East Door'), findsOneWidget);
      expect(find.text('Go straight for 10m'), findsWidgets);
      expect(find.text('Go straight for 5m'), findsNothing);
    });

    testWidgets('arriving at the first starts at the first', (tester) async {
      await pumpTrip(tester, route: arrivalRoute(arrivedAt: 'out_a'));

      expect(find.text('Start from: West Door'), findsOneWidget);
      expect(find.text('Go straight for 5m'), findsWidgets);
    });

    testWidgets('no outdoor route: the entrance nearest the GPS position',
        (tester) async {
      await pumpTrip(tester, route: arrivalRoute(), here: nearEast);

      expect(find.text('Start from: East Door'), findsOneWidget);
      expect(find.text('Go straight for 10m'), findsWidgets);
    });

    testWidgets('GPS beyond 150 m is ignored and the chooser is shown',
        (tester) async {
      await pumpTrip(tester, route: arrivalRoute(), here: farAway);

      expect(find.text('Choose your entrance'), findsOneWidget);
      expect(find.textContaining('Start from'), findsNothing);
      expect(find.textContaining('Go straight'), findsNothing);
    });

    testWidgets('nothing known: the chooser, and no route until a pick',
        (tester) async {
      await pumpTrip(tester, route: arrivalRoute());

      expect(find.text('Choose your entrance'), findsOneWidget);
      expect(find.text('West Door'), findsOneWidget);
      expect(find.text('East Door'), findsOneWidget);
      expect(find.textContaining('Go straight'), findsNothing);

      await tester.tap(find.text('East Door'));
      await tester.pumpAndSettle();
      expect(find.text('Start from: East Door'), findsOneWidget);
      expect(find.text('Go straight for 10m'), findsWidgets);
    });

    testWidgets('the Start from control changes the entrance', (tester) async {
      await pumpTrip(tester, route: arrivalRoute(arrivedAt: 'out_a'));

      await tester.tap(find.text('Start from: West Door'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your entrance'), findsOneWidget);

      await tester.tap(find.text('East Door'));
      await tester.pumpAndSettle();
      expect(find.text('Start from: East Door'), findsOneWidget);
      expect(find.text('Go straight for 10m'), findsWidgets);
      expect(find.text('Go straight for 5m'), findsNothing);
    });

    group('an entrance on a non-lowest floor', () {
      final floors = [floor(1), floor(2), floor(3)];
      final upperDoor = indoor('u', 2,
          x: 100, label: 'entrance', isEntrance: true, outdoorNodeId: 'out_u');
      final upperOut =
          outdoor('out_u', 7.0650, indoorNodeId: 'u', label: 'Hill Door');
      final upperCorridor = indoor('uc', 2, x: 200);
      final stairs2 =
          indoor('s2', 2, x: 200, y: 100, label: 'stairs', stairGroup: 'A');
      final stairs3 = indoor('s3', 3, x: 200, label: 'stairs', stairGroup: 'A');
      final corridor3 = indoor('c3', 3, x: 300);
      final room3 = indoor('r3', 3, x: 300, y: 100, linkedRoomId: 7);

      final nodes = [
        ...floor1Nodes,
        upperDoor,
        upperCorridor,
        stairs2,
        stairs3,
        corridor3,
        room3,
        indoor('r2', 2, x: 200, y: 100, linkedRoomId: 8),
      ];
      final edges = [
        ...floor1Edges,
        edge('u', 'uc'),
        edge('uc', 's2'),
        edge('uc', 'r2'),
        edge('s3', 'c3'),
        edge('c3', 'r3'),
      ];

      testWidgets('starts on its floor and takes the stairs from there',
          (tester) async {
        await pumpTrip(
          tester,
          route: arrivalRoute(arrivedAt: 'out_u', destFloor: 3),
          outdoorNodes: [westOut, upperOut],
          indoorNodes: nodes,
          indoorEdges: edges,
          floors: floors,
        );

        expect(find.text('How would you like to go to Floor 3?'), findsOneWidget);
        await tester.tap(find.text('Take Stairs'));
        await tester.pumpAndSettle();

        expect(find.text('Start from: Hill Door'), findsOneWidget);
        expect(find.text('Floor 2 — find the stairs'), findsOneWidget);
        expect(find.textContaining('No connected stairs'), findsNothing);
      });

      final indoorMap = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_RouteFloorView');

      Future<void> tripToFloor3(WidgetTester tester, AuthCubit auth) async {
        await pumpTrip(
          tester,
          route: arrivalRoute(arrivedAt: 'out_u', destFloor: 3),
          outdoorNodes: [westOut, upperOut],
          indoorNodes: nodes,
          indoorEdges: edges,
          floors: floors,
          auth: auth,
        );
        await tester.tap(find.text('Take Stairs'));
        await tester.pumpAndSettle();
      }

      Future<void> nextUntil(WidgetTester tester, String label) async {
        for (var i = 0; i < 10 && find.text(label).evaluate().isEmpty; i++) {
          await tester.tap(find.text('Next ►'));
          await tester.pumpAndSettle();
        }
      }

      VisitorSessionModel visitorSession() => VisitorSessionModel(
            id: 's',
            deviceCode: 'c',
            startedAt: DateTime.utc(2026, 11, 1, 9),
            expiresAt: DateTime.utc(2026, 11, 1, 11),
            clock: ServerClock.fromJson({
              'server': DateTime.utc(2026, 11, 1, 10).toIso8601String(),
              'phone': DateTime.utc(2026, 11, 1, 10).toIso8601String(),
            }, source: FakeClockSource())!,
          );

      testWidgets('a visitor gets numbered text steps, not the indoor map',
          (tester) async {
        await tripToFloor3(
            tester, SeededAuthCubit(state: AuthVisitor(visitorSession())));

        expect(indoorMap, findsNothing);
        expect(find.byType(VisitorIndoorSteps), findsOneWidget);
        expect(find.text(VisitorText.indoorMessage), findsOneWidget);
        // Same route steps as the 2D screen, then the floor change.
        expect(find.textContaining('Go straight for'), findsWidgets);
        expect(find.text('Take the stairs to Floor 3'), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        // The entrance control stays.
        expect(find.text('Start from: Hill Door'), findsOneWidget);
      });

      testWidgets('a visitor carries on counting on the next floor, to arrival',
          (tester) async {
        await tripToFloor3(
            tester, SeededAuthCubit(state: AuthVisitor(visitorSession())));
        final firstFloor = tester
            .widget<VisitorIndoorSteps>(find.byType(VisitorIndoorSteps))
            .steps
            .length;

        await nextUntil(tester, 'Go to Floor 3 ►');
        await tester.tap(find.text('Go to Floor 3 ►'));
        await tester.pumpAndSettle();

        final steps = tester
            .widget<VisitorIndoorSteps>(find.byType(VisitorIndoorSteps));
        expect(steps.firstNumber, firstFloor + 1);
        expect(steps.steps.last, 'You have arrived at Room 7');
        expect(indoorMap, findsNothing);
      });

      testWidgets('a verified user still sees the 2D map, and no message',
          (tester) async {
        await tripToFloor3(
          tester,
          SeededAuthCubit(
            state: const AuthAuthenticated(UserProfileModel(
                id: 'u1', role: 'student', isVerified: true)),
          ),
        );

        expect(indoorMap, findsOneWidget);
        expect(find.byType(VisitorIndoorSteps), findsNothing);
        expect(find.text(VisitorText.indoorMessage), findsNothing);
      });

      late FeedbackWorld world;
      setUp(() async {
        await FeedbackWorld.resetPhone();
        world = FeedbackWorld();
      });

      testWidgets('the arrival screen asks for the SUS once, then a comment',
          (tester) async {
        Future<void> arrive() async {
          final route = arrivalRoute(arrivedAt: 'out_u', destFloor: 2);
          route.to['id'] = '8';
          await pumpTrip(
            tester,
            route: route,
            outdoorNodes: [westOut, upperOut],
            indoorNodes: nodes,
            indoorEdges: edges,
            floors: floors,
            auth: SeededAuthCubit(state: visitorState()),
            feedback: world,
          );
          await nextUntil(tester, 'Arrived! 🎉');
          await tester.tap(find.text('Arrived! 🎉'));
          await tester.pumpAndSettle();
          expect(find.text('You Have Arrived!'), findsOneWidget);
        }

        await arrive();
        expect(find.text('Rate Your Experience'), findsOneWidget);
        expect(find.byType(FeedbackCommentCard), findsNothing);

        await world.submitSus();
        await tester.pumpWidget(const SizedBox());
        await arrive();

        expect(find.text('Rate Your Experience'), findsNothing);
        expect(find.byType(FeedbackCommentCard), findsOneWidget);
      });

      testWidgets('the turn-by-turn arrival asks once, then offers a comment',
          (tester) async {
        Future<void> arrive() async {
          await tester.pumpWidget(MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SurveyRepository>.value(value: world.survey),
              RepositoryProvider<FeedbackRepository>.value(
                  value: world.feedback),
            ],
            child: BlocProvider(
              create: (_) =>
                  OutdoorNavCubit(FakeOutdoorRepo([westOut, eastOut])),
              child: BlocProvider<AuthCubit>.value(
                value: SeededAuthCubit(state: visitorState()),
                child: MaterialApp(
                  home: TurnByTurnScreen(
                    tripId: 'trip-1',
                    args: TurnByTurnArgs(
                      path: const [LatLng(7.065, 125.59), LatLng(7.066, 125.59)],
                      nodes: const [],
                      destinationName: 'Library',
                    ),
                  ),
                ),
              ),
            ),
          ));
          await tester.pump(const Duration(seconds: 2));
          for (var i = 0;
              i < 5 && find.text('You have arrived!').evaluate().isEmpty;
              i++) {
            await tester.tap(find.text('Next'));
            await tester.pump(const Duration(seconds: 2));
          }
          // The panel is up; let its check finish.
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();
          expect(find.text('You have arrived!'), findsOneWidget);
        }

        await arrive();
        expect(find.text('Rate your experience'), findsOneWidget);
        expect(find.byType(FeedbackCommentCard), findsNothing);

        await world.submitSus();
        await tester.pumpWidget(const SizedBox());
        await arrive();

        expect(find.text('Rate your experience'), findsNothing);
        expect(find.byType(FeedbackCommentCard), findsOneWidget);

        // The map's tile requests leave timers behind.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 1));
      });

      testWidgets('a room on the same upper floor needs no stairs',
          (tester) async {
        final route = arrivalRoute(arrivedAt: 'out_u', destFloor: 2);
        route.to['id'] = '8';
        await pumpTrip(
          tester,
          route: route,
          outdoorNodes: [westOut, upperOut],
          indoorNodes: nodes,
          indoorEdges: edges,
          floors: floors,
        );

        expect(find.text('Take Stairs'), findsNothing);
        expect(find.text('Start from: Hill Door'), findsOneWidget);
        expect(find.textContaining('Go straight'), findsWidgets);
      });

      testWidgets('changing to a lower entrance asks for stairs or elevator',
          (tester) async {
        final route = arrivalRoute(arrivedAt: 'out_u', destFloor: 2);
        route.to['id'] = '8';
        await pumpTrip(
          tester,
          route: route,
          outdoorNodes: [westOut, upperOut],
          indoorNodes: nodes,
          indoorEdges: edges,
          floors: floors,
        );

        await tester.tap(find.text('Start from: Hill Door'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('West Door'));
        await tester.pumpAndSettle();
        expect(find.text('Take Stairs'), findsOneWidget);
      });

      testWidgets('building to its own room, entrance on the room floor',
          (tester) async {
        await pumpTrip(
          tester,
          route: ownBuildingRoute(destFloor: 2, roomId: '8'),
          outdoorNodes: [westOut, upperOut],
          indoorNodes: nodes,
          indoorEdges: edges,
          floors: floors,
          here: const LatLng(7.0651, 125.59),
        );

        expect(find.text('Take Stairs'), findsNothing);
        expect(find.text('Start from: Hill Door'), findsOneWidget);
        expect(find.textContaining('Go straight'), findsWidgets);
      });

      testWidgets('building to its own room, entrance on another floor',
          (tester) async {
        await pumpTrip(
          tester,
          route: ownBuildingRoute(destFloor: 3),
          outdoorNodes: [westOut, upperOut],
          indoorNodes: nodes,
          indoorEdges: edges,
          floors: floors,
          here: const LatLng(7.0651, 125.59),
        );

        expect(find.text('How would you like to go to Floor 3?'), findsOneWidget);
        expect(find.text('Start from: Hill Door'), findsOneWidget);
        await tester.tap(find.text('Take Stairs'));
        await tester.pumpAndSettle();
        expect(find.text('Floor 2 — find the stairs'), findsOneWidget);
      });
    });

    group('building to its own room', () {
      testWidgets('asks for the entrance before anything else', (tester) async {
        await pumpTrip(tester, route: ownBuildingRoute());

        expect(find.text('Choose your entrance'), findsOneWidget);
        expect(find.text('Take Stairs'), findsNothing);

        await tester.tap(find.text('West Door'));
        await tester.pumpAndSettle();
        expect(find.text('Take Stairs'), findsNothing);
        expect(find.text('Start from: West Door'), findsOneWidget);
        expect(find.text('Go straight for 5m'), findsWidgets);
      });

      testWidgets('far-away GPS shows the chooser', (tester) async {
        await pumpTrip(tester, route: ownBuildingRoute(), here: farAway);
        expect(find.text('Choose your entrance'), findsOneWidget);
      });

      testWidgets('plans are compared, not floor numbers', (tester) async {
        final ground = indoor('g', 0, x: 100, outdoorNodeId: 'o');
        await pumpTrip(
          tester,
          route: ownBuildingRoute(),
          outdoorNodes: [outdoor('o', 7.0699, indoorNodeId: 'g', label: 'Front')],
          indoorNodes: [
            ground,
            indoor('m', 0, x: 200),
            indoor('t', 0, x: 200, y: 100, linkedRoomId: 7),
          ],
          indoorEdges: [edge('g', 'm'), edge('m', 't')],
          floors: [floor(0)],
          here: nearEast,
        );

        expect(find.text('Take Stairs'), findsNothing);
        expect(find.text('Go straight for 5m'), findsWidgets);
      });
    });

    group('a trip with an outdoor leg', () {
      OutdoorNavState routeReady(List<String> nodeIds) => OutdoorNavState(
            status: OutdoorNavStatus.routeReady,
            path: const [LatLng(7.08, 125.59), LatLng(7.07, 125.59)],
            pathNodeIds: nodeIds,
          );

      test('the map hands over the last node of the route', () {
        final route = outdoorTripRoute(
          from: const {'type': 'building', 'id': '2', 'name': 'Gym'},
          to: const {'type': 'room', 'id': '7', 'building_id': buildingId},
          navState: routeReady(['gate', 'junction', 'out_b']),
        );
        expect(route.arrivalOutdoorNodeId, 'out_b');
      });

      test('a state with no route hands over nothing', () {
        final route = outdoorTripRoute(
          from: const {'type': 'building', 'id': '2'},
          to: const {'type': 'room', 'id': '7', 'building_id': buildingId},
          navState: const OutdoorNavState.idle(),
        );
        expect(route.arrivalOutdoorNodeId, isNull);
      });

      testWidgets('from the outdoor leg to the indoor leg at its last node',
          (tester) async {
        final route = outdoorTripRoute(
          from: const {'type': 'building', 'id': '2', 'name': 'Gym'},
          to: const {
            'type': 'room',
            'id': '7',
            'building_id': buildingId,
            'name': 'Room 7',
            'floor': 1,
          },
          navState: routeReady(['gate', 'out_b']),
          destBuildingId: '$buildingId',
        );
        await pumpTrip(tester,
            route: route, here: const LatLng(7.0601, 125.59), settle: false);

        // The walk ended at the East Door, though GPS is at the West Door.
        tester
            .widget<TurnByTurnScreen>(find.byType(TurnByTurnScreen))
            .onArrivedAtBuilding!();
        await tester.pumpAndSettle();

        expect(find.text('Start from: East Door'), findsOneWidget);
        expect(find.text('Go straight for 10m'), findsWidgets);
      });
    });

    testWidgets('a floor numbered 0 is not a second floor from "floor 1"',
        (tester) async {
      final ground = indoor('g', 0, x: 100, label: 'entrance', outdoorNodeId: 'o');
      final mid = indoor('m', 0, x: 200);
      final target = indoor('t', 0, x: 200, y: 100, linkedRoomId: 7);
      await pumpTrip(
        tester,
        route: arrivalRoute(arrivedAt: 'o'),
        outdoorNodes: [outdoor('o', 7.06, indoorNodeId: 'g', label: 'Front')],
        indoorNodes: [ground, mid, target],
        indoorEdges: [edge('g', 'm'), edge('m', 't')],
        floors: [floor(0)],
      );
      expect(find.text('Take Stairs'), findsNothing);
      expect(find.text('Go straight for 5m'), findsWidgets);
    });

    testWidgets('a missing indoor link says so, and no other entrance is used',
        (tester) async {
      await pumpTrip(
        tester,
        route: arrivalRoute(arrivedAt: 'out_b'),
        outdoorNodes: [
          westOut,
          outdoor('out_b', 7.07, label: 'Side Door'),
        ],
        indoorNodes: [westDoor, corridor, room],
        indoorEdges: [edge('a', 'c'), edge('c', 'r')],
      );

      expect(find.textContaining('Side Door $_noLinkMessage'), findsOneWidget);
      expect(find.textContaining('Start from'), findsNothing);
      expect(find.textContaining('Go straight'), findsNothing);

      // It stays visible but can't be picked; the linked one can.
      await tester.tap(find.text('Side Door'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Start from'), findsNothing);
      await tester.tap(find.text('West Door'));
      await tester.pumpAndSettle();
      expect(find.text('Start from: West Door'), findsOneWidget);
    });

    testWidgets('the nearest entrance having no link also says so',
        (tester) async {
      await pumpTrip(
        tester,
        route: arrivalRoute(),
        outdoorNodes: [
          westOut,
          outdoor('out_b', 7.07, label: 'Side Door'),
        ],
        indoorNodes: [westDoor, corridor, room],
        indoorEdges: [edge('a', 'c'), edge('c', 'r')],
        here: nearEast,
      );
      expect(find.textContaining('Side Door $_noLinkMessage'), findsOneWidget);
      expect(find.textContaining('Start from'), findsNothing);
    });

    testWidgets('no entrance linked at all offers a way out', (tester) async {
      await pumpTrip(
        tester,
        route: arrivalRoute(),
        outdoorNodes: [outdoor('o', 7.06, label: 'Side Door')],
      );
      expect(find.textContaining("aren't linked to the indoor map"),
          findsOneWidget);
      expect(find.text(noDataMessage), findsNothing);
      expect(find.text('Return to Map'), findsOneWidget);
    });

    testWidgets('a building with no entrance data shows a friendly message',
        (tester) async {
      await pumpTrip(
        tester,
        route: arrivalRoute(arrivedAt: 'gate_node'),
        outdoorNodes: const [],
        indoorNodes: const [],
        indoorEdges: const [],
        floors: const [],
      );

      expect(tester.takeException(), isNull);
      expect(find.text(noDataMessage), findsOneWidget);
      expect(find.text('Return to Map'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('rooms but no entrances: friendly message, no default node',
        (tester) async {
      await pumpTrip(tester, route: arrivalRoute(), outdoorNodes: const []);

      expect(find.text(noDataMessage), findsOneWidget);
      expect(find.textContaining('Go straight'), findsNothing);
    });

    testWidgets('a room → room trip still starts in the origin room',
        (tester) async {
      final start = indoor('s', 1, x: 0, linkedRoomId: 5);
      await pumpTrip(
        tester,
        route: NavigationRoute(
          from: const {'type': 'room', 'id': '5', 'building_id': buildingId},
          to: const {'type': 'room', 'id': '7', 'building_id': buildingId},
          phases: const [
            NavigationPhase.indoorNavigation,
            NavigationPhase.arrived,
          ],
          originFloor: 1,
          destBuildingId: '$buildingId',
          destFloor: 1,
        ),
        indoorNodes: [...floor1Nodes, start],
        indoorEdges: [...floor1Edges, edge('s', 'c')],
      );

      expect(find.textContaining('Start from'), findsNothing);
      expect(find.text('Go straight for 10m'), findsWidgets);
    });

    testWidgets('an origin room with no node asks instead of guessing',
        (tester) async {
      await pumpTrip(
        tester,
        route: NavigationRoute(
          from: const {'type': 'room', 'id': '99', 'building_id': buildingId},
          to: const {'type': 'room', 'id': '7', 'building_id': buildingId},
          phases: const [
            NavigationPhase.indoorNavigation,
            NavigationPhase.arrived,
          ],
          originFloor: 1,
          destBuildingId: '$buildingId',
          destFloor: 1,
        ),
      );

      expect(find.text('Choose your entrance'), findsOneWidget);
      expect(find.textContaining('Go straight'), findsNothing);
    });

    testWidgets('a same-named room in the destination building is not the start',
        (tester) async {
      final route = arrivalRoute(arrivedAt: 'out_b');
      final twin = NavigationRoute(
        from: const {'type': 'room', 'id': '7', 'name': 'Room 7'},
        to: route.to,
        phases: route.phases,
        currentPhaseIndex: 1,
        arrivalOutdoorNodeId: 'out_b',
        originRoomName: 'Room 7',
        destBuildingId: route.destBuildingId,
        destFloor: 1,
      );
      await pumpTrip(tester, route: twin);

      expect(find.text('Start from: East Door'), findsOneWidget);
      expect(find.text('Go straight for 10m'), findsWidgets);
    });
  });
}
