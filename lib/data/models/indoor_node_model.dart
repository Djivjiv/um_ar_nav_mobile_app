import 'package:flutter/painting.dart' show Offset;
import 'package:latlong2/latlong.dart';

import '../../core/utils/json_utils.dart';

class IndoorNodeModel {
  final String id;
  final String? floorPlanId;
  final int? buildingId;
  final String? name;
  final String? label;
  final double x;
  final double y;
  final double? lat;
  final double? lng;
  final bool isNavigable;
  final bool isEntrance;
  final String? entranceLabel;
  final String? outdoorNodeId;
  final String? roomName;
  final String? roomNumber;
  final String? nodeDescription;
  final String? operatingHours;
  final String? contact;
  final int? linkedRoomId;
  final String? linkedTable;

  const IndoorNodeModel({
    required this.id,
    this.floorPlanId,
    this.buildingId,
    this.name,
    this.label,
    this.x = 0,
    this.y = 0,
    this.lat,
    this.lng,
    this.isNavigable = true,
    this.isEntrance = false,
    this.entranceLabel,
    this.outdoorNodeId,
    this.roomName,
    this.roomNumber,
    this.nodeDescription,
    this.operatingHours,
    this.contact,
    this.linkedRoomId,
    this.linkedTable,
  });

  Offset get position => Offset(x, y);

  LatLng? get latLng =>
      (lat != null && lng != null) ? LatLng(lat!, lng!) : null;

  String get displayLabel {
    if (roomNumber?.trim().isNotEmpty == true) return roomNumber!;
    if (roomName?.trim().isNotEmpty == true) return roomName!;
    if (name?.trim().isNotEmpty == true) return name!;
    if (label?.trim().isNotEmpty == true) return label!;
    return id;
  }

  factory IndoorNodeModel.fromMap(Map<String, dynamic> m) {
    return IndoorNodeModel(
      id: J.strOr(m['id']),
      floorPlanId: J.str(m['floor_plan_id']),
      buildingId: J.intN(m['building_id']),
      name: J.str(m['name']),
      label: J.str(m['label']),
      x: J.dblOr(m['x']),
      y: J.dblOr(m['y']),
      lat: J.dbl(m['lat']),
      lng: J.dbl(m['lng']),
      isNavigable: J.boolOr(m['is_navigable'], true),
      isEntrance: J.boolOr(m['is_entrance']),
      entranceLabel: J.str(m['entrance_label']),
      outdoorNodeId: J.str(m['outdoor_node_id']),
      roomName: J.str(m['room_name']),
      roomNumber: J.str(m['room_number']),
      nodeDescription: J.str(m['node_description']),
      operatingHours: J.str(m['operating_hours']),
      contact: J.str(m['contact']),
      linkedRoomId: J.intN(m['linked_room_id']),
      linkedTable: J.str(m['linked_table']),
    );
  }
}
