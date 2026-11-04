import 'package:latlong2/latlong.dart';

import '../../core/utils/json_utils.dart';

/// One row of `outdoor_ar_nodes` — a point of the AR path network (managed
/// in the admin app's "Outdoor AR" screen, independent of `outdoor_nodes`).
class OutdoorArNodeModel {
  final String id;
  final String? label;
  final double lat;
  final double lng;

  /// `path`, `building` or `junction`.
  final String nodeType;

  /// Set on nodes at a building entrance — the AR route ends there.
  final int? buildingId;
  final bool isActive;

  const OutdoorArNodeModel({
    required this.id,
    required this.lat,
    required this.lng,
    this.label,
    this.nodeType = 'path',
    this.buildingId,
    this.isActive = true,
  });

  LatLng get point => LatLng(lat, lng);

  factory OutdoorArNodeModel.fromMap(Map<String, dynamic> m) {
    return OutdoorArNodeModel(
      id: J.strOr(m['id']),
      label: J.str(m['label']),
      lat: J.dblOr(m['lat']),
      lng: J.dblOr(m['lng']),
      nodeType: J.strOr(m['node_type'], 'path'),
      buildingId: J.intN(m['building_id']),
      // Null / missing counts as active.
      isActive: J.boolOr(m['is_active'], true),
    );
  }
}

/// One row of `outdoor_ar_edges`. Undirected — walkable both ways.
class OutdoorArEdgeModel {
  final String id;
  final String fromNode;
  final String toNode;

  /// Length in metres; null or non-positive means "use the straight-line
  /// distance between the nodes".
  final double? weightM;
  final bool isActive;

  const OutdoorArEdgeModel({
    required this.id,
    required this.fromNode,
    required this.toNode,
    this.weightM,
    this.isActive = true,
  });

  factory OutdoorArEdgeModel.fromMap(Map<String, dynamic> m) {
    return OutdoorArEdgeModel(
      id: J.strOr(m['id']),
      fromNode: J.strOr(m['from_node']),
      toNode: J.strOr(m['to_node']),
      weightM: J.dbl(m['weight_m']),
      isActive: J.boolOr(m['is_active'], true),
    );
  }
}
