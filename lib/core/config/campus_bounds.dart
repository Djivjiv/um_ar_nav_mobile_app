import 'package:latlong2/latlong.dart';

/// A GPS fix further than this from every path node or entrance is not on
/// campus (e.g. testing at home with the geofence off), so it says nothing
/// about where a route starts.
const double maxOnCampusGpsMeters = 150;

// University of Mindanao Matina Campus — complete boundary polygon.
// Source: geojson.io traced from satellite map.
const List<LatLng> campusPolygon = [
  LatLng(7.067523, 125.5915322),
  LatLng(7.0705229, 125.5942998),
  LatLng(7.07039, 125.5949247),
  LatLng(7.069561, 125.5953137),
  LatLng(7.0689851, 125.5957346),
  LatLng(7.0669727, 125.5973671),
  LatLng(7.0667828, 125.5967932),
  LatLng(7.0664664, 125.5967485),
  LatLng(7.0656376, 125.5981195),
  LatLng(7.0649098, 125.5985531),
  LatLng(7.0647194, 125.598604),
  LatLng(7.0646688, 125.5982979),
  LatLng(7.0649346, 125.5981959),
  LatLng(7.0644346, 125.5960277),
  LatLng(7.0652826, 125.5958173),
  LatLng(7.0650928, 125.5950712),
  LatLng(7.0642448, 125.5952944),
  LatLng(7.0638081, 125.5933941),
  LatLng(7.0675229, 125.5925396),
  LatLng(7.0672951, 125.5915958),
  LatLng(7.067523, 125.5915322),
];

// Bounding box for a fast pre-check before the full polygon test.
const double campusMinLat = 7.0638081;
const double campusMaxLat = 7.0705229;
const double campusMinLng = 125.5915322;
const double campusMaxLng = 125.5986040;
