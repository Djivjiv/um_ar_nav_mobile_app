import '../../data/models/floor_plan_model.dart';
import '../../data/models/indoor_node_model.dart';

/// Pure helpers for indoor routing — kept free of widgets so they can be
/// unit-tested.

// ───────────────────────── stairs / elevator labels ─────────────────────────

/// True when a node [label] is the given vertical [transport]
/// (`'stairs'` or `'elevator'`). Case-insensitive "contains" match, so
/// `Elevator`, `elevator_2` and `Main Elevator` all count; `stairs` also
/// accepts `stair` / `Staircase`.
bool labelMatchesTransport(String? label, String transport) {
  final l = (label ?? '').toLowerCase();
  return transport == 'elevator' ? l.contains('elevator') : l.contains('stair');
}

// ───────────────────────── room / facility links ─────────────────────────

/// The `indoor_nodes.linked_table` value for a destination `type`
/// (`'room'` → `'rooms'`, `'facility'` → `'facilities'`), else null.
String? linkedTableForType(String? type) {
  switch (type) {
    case 'room':
      return 'rooms';
    case 'facility':
      return 'facilities';
    default:
      return null;
  }
}

/// Whether a node linked to [linkedRoomId] in [linkedTable] is the
/// room / facility [targetId] of [targetType].
///
/// Room ids and facility ids come from different tables and can collide, so
/// when the node says which table it links to, that table must match. Nodes
/// with no `linked_table` (older data) still match on id alone.
bool linkMatches({
  required int? linkedRoomId,
  required String? linkedTable,
  required String? targetId,
  required String? targetType,
}) {
  if (linkedRoomId == null || targetId == null) return false;
  if (linkedRoomId.toString() != targetId) return false;
  final table = linkedTable?.trim().toLowerCase();
  final expected = linkedTableForType(targetType);
  if (table == null || table.isEmpty || expected == null) return true;
  return table == expected;
}

/// Destination `type` + `id` for an indoor-node search result, from the
/// node's `linked_table` / `linked_room_id`:
/// - `'rooms'` → room, `'facilities'` → facility (id = the linked row);
/// - linked with no `linked_table` (older data, which only linked rooms)
///   → room;
/// - not linked → facility with no id (a generic indoor location — routing
///   then targets the node itself via `indoor_node_id`).
({String type, String? id}) indoorNodeDestination(IndoorNodeModel n) {
  final table = n.linkedTable?.trim().toLowerCase();
  final linkedId = n.linkedRoomId?.toString();
  if (linkedId != null) {
    if (table == 'facilities') return (type: 'facility', id: linkedId);
    return (type: 'room', id: linkedId);
  }
  return (type: 'facility', id: null);
}

/// False when [n] is linked to a room / facility whose id is in the matching
/// inactive set — so search hides it. Unlinked nodes always pass.
bool isLinkedPlaceActive(
  IndoorNodeModel n, {
  Set<int> inactiveRoomIds = const {},
  Set<int> inactiveFacilityIds = const {},
}) {
  final dest = indoorNodeDestination(n);
  final id = int.tryParse(dest.id ?? '');
  if (id == null) return true;
  final inactive =
      dest.type == 'facility' ? inactiveFacilityIds : inactiveRoomIds;
  return !inactive.contains(id);
}

bool nodeLinksTo(IndoorNodeModel n, String? targetId, String? targetType) =>
    linkMatches(
      linkedRoomId: n.linkedRoomId,
      linkedTable: n.linkedTable,
      targetId: targetId,
      targetType: targetType,
    );

// ───────────────────────── stair groups ─────────────────────────

/// The staircase / elevator chosen for a two-floor trip: the same
/// [group] on both floors, with its node on each floor.
class StairGroupChoice {
  final String group;
  final IndoorNodeModel startFloorNode;
  final IndoorNodeModel destFloorNode;

  /// Start → transport (start floor) + transport → room (destination floor).
  final double totalCost;

  const StairGroupChoice({
    required this.group,
    required this.startFloorNode,
    required this.destFloorNode,
    required this.totalCost,
  });
}

String? _groupKey(IndoorNodeModel n) {
  final g = n.stairGroup?.trim();
  return (g == null || g.isEmpty) ? null : g.toLowerCase();
}

/// Picks one [transport] stair group that has a node on BOTH floors,
/// minimising the total route: [costToTransport] (start-floor graph
/// distance from the trip start to that node) + [costFromTransport]
/// (destination-floor graph distance from that node to the room).
///
/// Returns null when no group is common to both floors, or none of the
/// common groups is reachable on both legs — the caller must show an error
/// rather than fall back to an arbitrary node.
StairGroupChoice? chooseStairGroup({
  required List<IndoorNodeModel> startFloorNodes,
  required List<IndoorNodeModel> destFloorNodes,
  required String transport,
  required double Function(IndoorNodeModel startFloorNode) costToTransport,
  required double Function(IndoorNodeModel destFloorNode) costFromTransport,
}) {
  Map<String, List<IndoorNodeModel>> byGroup(List<IndoorNodeModel> nodes) {
    final out = <String, List<IndoorNodeModel>>{};
    for (final n in nodes) {
      final key = _groupKey(n);
      if (key == null || !n.isNavigable || !n.isActive) continue;
      if (!labelMatchesTransport(n.label, transport)) continue;
      out.putIfAbsent(key, () => []).add(n);
    }
    return out;
  }

  final startGroups = byGroup(startFloorNodes);
  final destGroups = byGroup(destFloorNodes);

  StairGroupChoice? best;
  for (final key in startGroups.keys) {
    final destCandidates = destGroups[key];
    if (destCandidates == null) continue;

    IndoorNodeModel? s;
    var sCost = double.infinity;
    for (final n in startGroups[key]!) {
      final c = costToTransport(n);
      if (c < sCost) {
        sCost = c;
        s = n;
      }
    }
    IndoorNodeModel? d;
    var dCost = double.infinity;
    for (final n in destCandidates) {
      final c = costFromTransport(n);
      if (c < dCost) {
        dCost = c;
        d = n;
      }
    }
    if (s == null || d == null) continue;
    final total = sCost + dCost;
    if (!total.isFinite) continue;
    if (best == null || total < best.totalCost) {
      best = StairGroupChoice(
        group: s.stairGroup!.trim(),
        startFloorNode: s,
        destFloorNode: d,
        totalCost: total,
      );
    }
  }
  return best;
}

// ───────────────────────── floor plans ─────────────────────────

/// The start and destination floor plans for an indoor trip, or an [error]
/// explaining why indoor directions are unavailable.
typedef IndoorFloorPlans = ({
  FloorPlanModel? start,
  FloorPlanModel? dest,
  String? error,
});

/// Picks the start plan ([startPlan] — the entrance's own floor — else
/// [originFloor], else the lowest floor) and the destination plan
/// ([destFloor]).
///
/// A destination floor with no floor plan is an error — never a silent
/// reroute to another floor. The one exception is the ground floor
/// (`destFloor <= 1`), which maps to the lowest plan because buildings
/// number their ground floor 0 or 1.
IndoorFloorPlans pickIndoorFloorPlans({
  required List<FloorPlanModel> floors,
  required int originFloor,
  required int destFloor,
  FloorPlanModel? startPlan,
}) {
  if (floors.isEmpty) {
    return (
      start: null,
      dest: null,
      error: 'No floor plan is available for this building.',
    );
  }
  FloorPlanModel? planFor(int floor) {
    for (final f in floors) {
      if (f.floorNumber == floor) return f;
    }
    return null;
  }

  final lowest =
      floors.reduce((a, b) => a.floorNumber <= b.floorNumber ? a : b);
  final start = startPlan ?? planFor(originFloor) ?? lowest;
  final dest = planFor(destFloor) ?? (destFloor <= 1 ? lowest : null);
  if (dest == null) {
    return (
      start: start,
      dest: null,
      error: 'Floor $destFloor of this building has no floor plan yet, '
          'so indoor directions to this room are not available.',
    );
  }
  return (start: start, dest: dest, error: null);
}

// ───────────────────────── Next / Previous ─────────────────────────

enum IndoorStepAction {
  none,
  stepForward,
  stepBack,

  /// Last step on the start floor of a two-floor trip → destination floor.
  toDestinationFloor,

  /// First step on the destination floor → back to the LAST step of the
  /// start floor.
  toStartFloorLastStep,
  arrive,
}

/// What "Next" does at [step] of [stepCount] steps.
IndoorStepAction indoorNextAction({
  required int step,
  required int stepCount,
  required bool twoFloors,
  required bool onStartFloor,
}) {
  if (stepCount > 0 && step < stepCount - 1) return IndoorStepAction.stepForward;
  return (twoFloors && onStartFloor)
      ? IndoorStepAction.toDestinationFloor
      : IndoorStepAction.arrive;
}

/// What "Previous" does at [step]: one step back, or — only from the first
/// destination-floor step — back to the start floor's last step.
IndoorStepAction indoorPreviousAction({
  required int step,
  required bool twoFloors,
  required bool onStartFloor,
}) {
  if (step > 0) return IndoorStepAction.stepBack;
  if (twoFloors && !onStartFloor) return IndoorStepAction.toStartFloorLastStep;
  return IndoorStepAction.none;
}
