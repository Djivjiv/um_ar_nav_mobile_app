import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/core/utils/indoor_route_helpers.dart';
import 'package:um_ar_mobile_app/data/models/indoor_node_model.dart';

IndoorNodeModel node(
  String id, {
  String? label,
  String? group,
  bool navigable = true,
  int? linkedRoomId,
  String? linkedTable,
  int? floor,
}) =>
    IndoorNodeModel(
      id: id,
      label: label,
      stairGroup: group,
      isNavigable: navigable,
      linkedRoomId: linkedRoomId,
      linkedTable: linkedTable,
      floor: floor,
    );

void main() {
  group('transport label matching', () {
    test('elevator is a case-insensitive contains match', () {
      for (final l in ['elevator', 'Elevator', 'ELEVATOR', 'Main Elevator', 'elevator_2']) {
        expect(labelMatchesTransport(l, 'elevator'), isTrue, reason: l);
      }
      expect(labelMatchesTransport('stairs', 'elevator'), isFalse);
      expect(labelMatchesTransport(null, 'elevator'), isFalse);
    });

    test('stairs accepts stairs / stair / Staircase in any case', () {
      for (final l in ['stairs', 'Stairs', 'stair', 'Staircase A']) {
        expect(labelMatchesTransport(l, 'stairs'), isTrue, reason: l);
      }
      expect(labelMatchesTransport('elevator', 'stairs'), isFalse);
    });
  });

  group('stair group selection', () {
    // Start floor: groups A and B (+ C only here). Dest floor: A, B, D.
    final startFloor = [
      node('s_a', label: 'stairs', group: 'BE_STAIRS_A'),
      node('s_b', label: 'Stairs', group: 'BE_STAIRS_B'),
      node('s_c', label: 'stairs', group: 'BE_STAIRS_C'),
      node('s_e', label: 'elevator', group: 'BE_LIFT_1'),
    ];
    final destFloor = [
      node('d_a', label: 'stairs', group: 'be_stairs_a '), // case/space differ
      node('d_b', label: 'stairs', group: 'BE_STAIRS_B'),
      node('d_d', label: 'stairs', group: 'BE_STAIRS_D'),
      node('d_e', label: 'Elevator', group: 'BE_LIFT_1'),
    ];

    test('uses the SAME group on both floors, minimising the total route', () {
      // A is closest on the start floor, but B wins on the total.
      final toTransport = {'s_a': 5.0, 's_b': 20.0, 's_c': 1.0};
      final fromTransport = {'d_a': 100.0, 'd_b': 10.0, 'd_d': 1.0};
      final choice = chooseStairGroup(
        startFloorNodes: startFloor,
        destFloorNodes: destFloor,
        transport: 'stairs',
        costToTransport: (n) => toTransport[n.id] ?? double.infinity,
        costFromTransport: (n) => fromTransport[n.id] ?? double.infinity,
      )!;
      expect(choice.group, 'BE_STAIRS_B');
      expect(choice.startFloorNode.id, 's_b');
      expect(choice.destFloorNode.id, 'd_b');
      expect(choice.totalCost, 30);
    });

    test('never picks a group that exists on only one floor', () {
      // C is cheapest on the start floor and D on the dest floor, but
      // neither is on both floors.
      final choice = chooseStairGroup(
        startFloorNodes: startFloor,
        destFloorNodes: destFloor,
        transport: 'stairs',
        costToTransport: (n) => n.id == 's_c' ? 0 : 50,
        costFromTransport: (n) => n.id == 'd_d' ? 0 : 50,
      )!;
      expect(['BE_STAIRS_A', 'BE_STAIRS_B'], contains(choice.group));
      expect(choice.startFloorNode.id, isNot('s_c'));
      expect(choice.destFloorNode.id, isNot('d_d'));
    });

    test('elevator trips only consider elevator groups', () {
      final choice = chooseStairGroup(
        startFloorNodes: startFloor,
        destFloorNodes: destFloor,
        transport: 'elevator',
        costToTransport: (_) => 1,
        costFromTransport: (_) => 1,
      )!;
      expect(choice.group, 'BE_LIFT_1');
      expect(choice.destFloorNode.id, 'd_e');
    });

    test('returns null when no group is common to both floors', () {
      expect(
        chooseStairGroup(
          startFloorNodes: [node('s', label: 'stairs', group: 'X')],
          destFloorNodes: [node('d', label: 'stairs', group: 'Y')],
          transport: 'stairs',
          costToTransport: (_) => 1,
          costFromTransport: (_) => 1,
        ),
        isNull,
      );
    });

    test('returns null when common groups are unreachable', () {
      expect(
        chooseStairGroup(
          startFloorNodes: startFloor,
          destFloorNodes: destFloor,
          transport: 'stairs',
          costToTransport: (_) => double.infinity,
          costFromTransport: (_) => 1,
        ),
        isNull,
      );
    });

    test('ignores stairs nodes without a group and non-navigable nodes', () {
      expect(
        chooseStairGroup(
          startFloorNodes: [
            node('s1', label: 'stairs'),
            node('s2', label: 'stairs', group: 'G', navigable: false),
          ],
          destFloorNodes: [node('d1', label: 'stairs', group: 'G')],
          transport: 'stairs',
          costToTransport: (_) => 1,
          costFromTransport: (_) => 1,
        ),
        isNull,
      );
    });
  });

  group('linked_table matching', () {
    test('a facility id does not match a node linked to the same room id', () {
      final roomNode = node('n', linkedRoomId: 5, linkedTable: 'rooms');
      expect(nodeLinksTo(roomNode, '5', 'room'), isTrue);
      expect(nodeLinksTo(roomNode, '5', 'facility'), isFalse);

      final facilityNode =
          node('f', linkedRoomId: 5, linkedTable: 'facilities');
      expect(nodeLinksTo(facilityNode, '5', 'facility'), isTrue);
      expect(nodeLinksTo(facilityNode, '5', 'room'), isFalse);
    });

    test('older nodes without linked_table still match on id', () {
      expect(nodeLinksTo(node('n', linkedRoomId: 7), '7', 'facility'), isTrue);
    });

    test('different ids never match', () {
      expect(
          nodeLinksTo(node('n', linkedRoomId: 7, linkedTable: 'rooms'), '8',
              'room'),
          isFalse);
      expect(nodeLinksTo(node('n'), '7', 'room'), isFalse);
    });
  });

  group('indoor search result destination', () {
    test('uses linked_table for the type and the linked row id', () {
      expect(
        indoorNodeDestination(
            node('n', linkedRoomId: 12, linkedTable: 'facilities')),
        (type: 'facility', id: '12'),
      );
      expect(
        indoorNodeDestination(node('n', linkedRoomId: 3, linkedTable: 'rooms')),
        (type: 'room', id: '3'),
      );
    });

    test('older linked rows without a table are rooms', () {
      expect(indoorNodeDestination(node('n', linkedRoomId: 3)),
          (type: 'room', id: '3'));
    });

    test('unlinked nodes have no id (never the node uuid)', () {
      expect(indoorNodeDestination(node('uuid-1')),
          (type: 'facility', id: null));
    });

    test('node floor is parsed from indoor_nodes.floor', () {
      final n = IndoorNodeModel.fromMap({
        'id': 'n1',
        'floor': 3,
        'stair_group': 'BE_STAIRS_A',
        'linked_table': 'facilities',
        'linked_room_id': 9,
      });
      expect(n.floor, 3);
      expect(n.stairGroup, 'BE_STAIRS_A');
      expect(indoorNodeDestination(n), (type: 'facility', id: '9'));
    });
  });

  group('Next / Previous at the floor-change boundary', () {
    test('Previous on the destination floor goes back ONE step', () {
      expect(
        indoorPreviousAction(step: 2, twoFloors: true, onStartFloor: false),
        IndoorStepAction.stepBack,
      );
      expect(
        indoorPreviousAction(step: 1, twoFloors: true, onStartFloor: false),
        IndoorStepAction.stepBack,
      );
    });

    test('Previous on the first destination-floor step returns to the start '
        'floor', () {
      expect(
        indoorPreviousAction(step: 0, twoFloors: true, onStartFloor: false),
        IndoorStepAction.toStartFloorLastStep,
      );
    });

    test('Previous at the very first step does nothing', () {
      expect(
        indoorPreviousAction(step: 0, twoFloors: true, onStartFloor: true),
        IndoorStepAction.none,
      );
      expect(
        indoorPreviousAction(step: 0, twoFloors: false, onStartFloor: false),
        IndoorStepAction.none,
      );
    });

    test('Next on the start floor steps forward, then changes floor', () {
      expect(
        indoorNextAction(
            step: 1, stepCount: 4, twoFloors: true, onStartFloor: true),
        IndoorStepAction.stepForward,
      );
      expect(
        indoorNextAction(
            step: 3, stepCount: 4, twoFloors: true, onStartFloor: true),
        IndoorStepAction.toDestinationFloor,
      );
    });

    test('Next on the last destination-floor step arrives', () {
      expect(
        indoorNextAction(
            step: 2, stepCount: 3, twoFloors: true, onStartFloor: false),
        IndoorStepAction.arrive,
      );
      expect(
        indoorNextAction(
            step: 4, stepCount: 5, twoFloors: false, onStartFloor: false),
        IndoorStepAction.arrive,
      );
    });

    test('Next then Previous across the boundary are inverse moves', () {
      // Next at the last start-floor step → destination floor.
      expect(
          indoorNextAction(
              step: 3, stepCount: 4, twoFloors: true, onStartFloor: true),
          IndoorStepAction.toDestinationFloor);
      // Previous from destination step 0 → back to the start floor's LAST
      // step (the screen sets step = stepCount - 1), not its first.
      expect(
          indoorPreviousAction(step: 0, twoFloors: true, onStartFloor: false),
          IndoorStepAction.toStartFloorLastStep);
    });
  });
}
