import 'package:latlong2/latlong.dart';

import '../config/campus_bounds.dart';
import '../../data/models/floor_plan_model.dart';
import '../../data/models/indoor_node_model.dart';
import '../../data/models/outdoor_node_model.dart';
import 'text_utils.dart';

/// Pure helpers that decide where an indoor route starts — kept free of
/// widgets so they can be unit-tested.


const String noEntranceDataMessage =
    "Indoor directions aren't available for this building yet.";
const String noEntranceLinkedMessage =
    "This building's entrances aren't linked to the indoor map yet.";
const String entranceNotLinkedLabel = 'Not linked to the indoor map yet';

String entranceNotLinkedMessage(String entranceName) =>
    "$entranceName isn't linked to the indoor map yet, so indoor directions "
    "can't start there.";

/// One floor of a building and its nodes.
typedef FloorNodes = ({FloorPlanModel plan, List<IndoorNodeModel> nodes});

/// A building entrance: the outdoor node and, when the admin app paired it,
/// the indoor node it leads into plus that node's own floor.
class BuildingEntrance {
  final String name;
  final OutdoorNodeModel? outdoorNode;
  final IndoorNodeModel? indoorNode;
  final FloorPlanModel? plan;

  const BuildingEntrance({
    required this.name,
    this.outdoorNode,
    this.indoorNode,
    this.plan,
  });

  bool get isLinked => indoorNode != null && plan != null;

  LatLng? get point => outdoorNode?.point ?? indoorNode?.latLng;
}

/// The entrances of [buildingId], linked ones first, from the
/// `outdoor_nodes.indoor_node_id` / `indoor_nodes.outdoor_node_id` pairing.
///
/// `indoor_nodes.is_entrance` alone is not used: it also marks room doors.
/// A link to a node that is not on one of [floors], or that can't be walked
/// to (inactive, not navigable), counts as not linked. A place with no indoor
/// nodes at all (a gate, a building with no rooms) has no entrances.
List<BuildingEntrance> buildingEntrances({
  required int buildingId,
  required List<OutdoorNodeModel> outdoorNodes,
  required List<FloorNodes> floors,
}) {
  if (floors.every((f) => f.nodes.isEmpty)) return const [];

  final byIndoorId = <String, ({IndoorNodeModel node, FloorPlanModel plan})>{};
  final byOutdoorId = <String, ({IndoorNodeModel node, FloorPlanModel plan})>{};
  for (final f in floors) {
    for (final n in f.nodes) {
      if (!n.isNavigable || !n.isActive) continue;
      final hit = (node: n, plan: f.plan);
      byIndoorId[n.id] = hit;
      final outdoorId = cleanText(n.outdoorNodeId);
      if (outdoorId != null) byOutdoorId[outdoorId] = hit;
    }
  }

  String nameFor(OutdoorNodeModel? o, IndoorNodeModel? n) =>
      cleanText(o?.entranceLabel) ??
      cleanText(n?.entranceLabel) ??
      cleanText(o?.name) ??
      cleanText(n?.name) ??
      'Entrance';

  final entrances = <BuildingEntrance>[];
  final seen = <String>{};
  for (final o in outdoorNodes) {
    if (o.buildingId != buildingId) continue;
    if (!o.isEntrance && cleanText(o.indoorNodeId) == null) continue;
    seen.add(o.id);
    final hit = byIndoorId[o.indoorNodeId] ?? byOutdoorId[o.id];
    entrances.add(BuildingEntrance(
      name: nameFor(o, hit?.node),
      outdoorNode: o,
      indoorNode: hit?.node,
      plan: hit?.plan,
    ));
  }

  // Paired only from the indoor side (the outdoor row has no building or
  // link). An outdoor node that is gone or inactive is not an entrance.
  for (final e in byOutdoorId.entries) {
    if (seen.contains(e.key)) continue;
    for (final o in outdoorNodes) {
      if (o.id != e.key) continue;
      entrances.add(BuildingEntrance(
        name: nameFor(o, e.value.node),
        outdoorNode: o,
        indoorNode: e.value.node,
        plan: e.value.plan,
      ));
      break;
    }
  }

  return [
    ...entrances.where((e) => e.isLinked),
    ...entrances.where((e) => !e.isLinked),
  ];
}

enum IndoorStartKind {
  /// Start at the entrance the outdoor route ended at.
  arrived,

  /// No outdoor route: start at the entrance nearest the user's GPS position.
  nearest,

  /// Nothing says which entrance — the user has to pick.
  choose,

  /// The entrance that applies has no indoor node, or none of them has one.
  /// Never replaced by another entrance without the user picking it.
  notLinked,

  /// The building has no entrance data.
  noData,
}

class IndoorStartDecision {
  final IndoorStartKind kind;

  /// The entrance for [IndoorStartKind.arrived] and [IndoorStartKind.nearest].
  /// For [IndoorStartKind.notLinked], the one that isn't linked, or null when
  /// none of the building's entrances is.
  final BuildingEntrance? entrance;

  const IndoorStartDecision(this.kind, [this.entrance]);

  bool get canStart =>
      kind == IndoorStartKind.arrived || kind == IndoorStartKind.nearest;
}

/// Picks the indoor start: the entrance of [arrivedOutdoorNodeId] (the last
/// node of the outdoor route), else the entrance nearest [locate]'s fix, else
/// the user's choice. [locate] is only called when it is needed.
Future<IndoorStartDecision> decideIndoorStart({
  required List<BuildingEntrance> entrances,
  required String? arrivedOutdoorNodeId,
  required Future<LatLng?> Function() locate,
}) async {
  IndoorStartDecision of(IndoorStartKind kind, BuildingEntrance e) =>
      IndoorStartDecision(e.isLinked ? kind : IndoorStartKind.notLinked, e);

  for (final e in entrances) {
    if (arrivedOutdoorNodeId != null &&
        e.outdoorNode?.id == arrivedOutdoorNodeId) {
      return of(IndoorStartKind.arrived, e);
    }
  }

  if (entrances.isEmpty) {
    return const IndoorStartDecision(IndoorStartKind.noData);
  }
  if (!entrances.any((e) => e.isLinked)) {
    return const IndoorStartDecision(IndoorStartKind.notLinked);
  }

  final here = await locate();
  if (here != null) {
    const distance = Distance();
    BuildingEntrance? nearest;
    var nearestMeters = double.infinity;
    for (final e in entrances) {
      final p = e.point;
      if (p == null) continue;
      final d = distance.as(LengthUnit.Meter, here, p);
      if (d < nearestMeters) {
        nearestMeters = d;
        nearest = e;
      }
    }
    if (nearest != null && nearestMeters <= maxOnCampusGpsMeters) {
      return of(IndoorStartKind.nearest, nearest);
    }
  }

  return const IndoorStartDecision(IndoorStartKind.choose);
}
