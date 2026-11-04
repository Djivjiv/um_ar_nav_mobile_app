import 'package:latlong2/latlong.dart';

import '../../core/config/ar_nav_config.dart';
import '../../core/utils/json_utils.dart';

class BuildingModel {
  final int id;
  final String name;
  final String? shortName;
  final String? displayName;
  final double lat;
  final double lng;
  final int floorCount;
  final String? openingHours;
  final String? contact;
  final List<String> description;
  final List<String> imageUrls;
  final bool isActive;
  final bool isAccessible;

  // AR overlay presentation (`buildings.ar_emoji`, `ar_label`,
  // `ar_arrival_radius_m`).
  final String? arEmoji;
  final String? arLabel;
  final double arArrivalRadiusM;

  const BuildingModel({
    required this.id,
    required this.name,
    this.shortName,
    this.displayName,
    required this.lat,
    required this.lng,
    this.floorCount = 1,
    this.openingHours,
    this.contact,
    this.description = const [],
    this.imageUrls = const [],
    this.isActive = true,
    this.isAccessible = false,
    this.arEmoji,
    this.arLabel,
    this.arArrivalRadiusM = ArNavConfig.defaultArrivalRadiusMeters,
  });

  LatLng get location => LatLng(lat, lng);

  String get label => displayName ?? shortName ?? name;

  String? get firstImage => imageUrls.isNotEmpty ? imageUrls.first : null;

  factory BuildingModel.fromMap(Map<String, dynamic> m) {
    return BuildingModel(
      id: J.intOr(m['id']),
      name: J.strOr(m['name'], 'Unknown Building'),
      shortName: J.str(m['short_name']),
      displayName: J.str(m['display_name']),
      lat: J.dblOr(m['lat']),
      lng: J.dblOr(m['lng']),
      floorCount: J.intOr(m['floor_count'], 1),
      openingHours: J.str(m['opening_hours']),
      contact: J.str(m['contact']),
      description: J.strList(m['description']),
      imageUrls: J.strList(m['image_url']),
      isActive: J.boolOr(m['is_active'], true),
      isAccessible: J.boolOr(m['is_accessible']),
      arEmoji: _nonBlank(J.str(m['ar_emoji'])),
      arLabel: _nonBlank(J.str(m['ar_label'])),
      arArrivalRadiusM: _positiveOr(J.dbl(m['ar_arrival_radius_m']),
          ArNavConfig.defaultArrivalRadiusMeters),
    );
  }

  static String? _nonBlank(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  static double _positiveOr(double? v, double fallback) =>
      (v == null || v <= 0) ? fallback : v;
}
