import 'package:latlong2/latlong.dart';

import '../../core/utils/json_utils.dart';

/// One row of `building_floors`.
class FloorPlanModel {
  final int id;
  final int buildingId;
  final int floorNumber;
  final String? floorName;
  final String? imageUrl;

  final double? nwLat, nwLng, neLat, neLng, swLat, swLng, seLat, seLng;
  final double? centerLat, centerLng;
  final double rotationAngle;
  final double scaleFactor;
  final bool isGeoreferenced;
  final bool isActive;

  const FloorPlanModel({
    required this.id,
    required this.buildingId,
    required this.floorNumber,
    this.floorName,
    this.imageUrl,
    this.nwLat,
    this.nwLng,
    this.neLat,
    this.neLng,
    this.swLat,
    this.swLng,
    this.seLat,
    this.seLng,
    this.centerLat,
    this.centerLng,
    this.rotationAngle = 0,
    this.scaleFactor = 1,
    this.isGeoreferenced = false,
    this.isActive = true,
  });

  String get tabLabel {
    if (floorName != null && floorName!.trim().isNotEmpty) return floorName!;
    if (floorNumber <= 1) return 'Ground Floor';
    return '${floorNumber}F';
  }

  LatLng? get center =>
      (centerLat != null && centerLng != null)
          ? LatLng(centerLat!, centerLng!)
          : null;

  /// The four georeferenced corners, if present, as NW, NE, SE, SW.
  List<LatLng>? get corners {
    if ([nwLat, nwLng, neLat, neLng, seLat, seLng, swLat, swLng]
        .any((e) => e == null)) {
      return null;
    }
    return [
      LatLng(nwLat!, nwLng!),
      LatLng(neLat!, neLng!),
      LatLng(seLat!, seLng!),
      LatLng(swLat!, swLng!),
    ];
  }

  factory FloorPlanModel.fromMap(Map<String, dynamic> m) {
    return FloorPlanModel(
      id: J.intOr(m['id']),
      buildingId: J.intOr(m['building_id']),
      floorNumber: J.intOr(m['floor_number'], 1),
      floorName: J.str(m['floor_name']),
      imageUrl: J.str(m['image_url']),
      nwLat: J.dbl(m['nw_lat']),
      nwLng: J.dbl(m['nw_lng']),
      neLat: J.dbl(m['ne_lat']),
      neLng: J.dbl(m['ne_lng']),
      swLat: J.dbl(m['sw_lat']),
      swLng: J.dbl(m['sw_lng']),
      seLat: J.dbl(m['se_lat']),
      seLng: J.dbl(m['se_lng']),
      centerLat: J.dbl(m['center_lat']),
      centerLng: J.dbl(m['center_lng']),
      rotationAngle: J.dblOr(m['rotation_angle']),
      scaleFactor: J.dblOr(m['scale_factor'], 1),
      isGeoreferenced: J.boolOr(m['is_georeferenced']),
      isActive: J.boolOr(m['is_active'], true),
    );
  }
}
