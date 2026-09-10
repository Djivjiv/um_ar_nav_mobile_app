import 'package:latlong2/latlong.dart';

import '../../core/utils/json_utils.dart';

class OutdoorNodeModel {
  final String id;
  final String? name;
  final String? type;
  final double lat;
  final double lng;
  final int? buildingId;
  final bool isActive;
  final bool isEntrance;
  final String? entranceLabel;
  final String? indoorNodeId;

  const OutdoorNodeModel({
    required this.id,
    this.name,
    this.type,
    required this.lat,
    required this.lng,
    this.buildingId,
    this.isActive = true,
    this.isEntrance = false,
    this.entranceLabel,
    this.indoorNodeId,
  });

  LatLng get point => LatLng(lat, lng);

  String get displayName => name ?? entranceLabel ?? id;

  factory OutdoorNodeModel.fromMap(Map<String, dynamic> m) {
    return OutdoorNodeModel(
      id: J.strOr(m['id']),
      name: J.str(m['name']),
      type: J.str(m['type']),
      lat: J.dblOr(m['lat']),
      lng: J.dblOr(m['lng']),
      buildingId: J.intN(m['building_id']),
      isActive: J.boolOr(m['is_active'], true),
      isEntrance: J.boolOr(m['is_entrance']),
      entranceLabel: J.str(m['entrance_label']),
      indoorNodeId: J.str(m['indoor_node_id']),
    );
  }
}
