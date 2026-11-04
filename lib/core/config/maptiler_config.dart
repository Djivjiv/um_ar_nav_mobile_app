import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

/// MapTiler tile sources and campus geography constants.
class MapTilerConfig {
  MapTilerConfig._();

  /// Passed at run/build time (see README): --dart-define=MAPTILER_KEY=...
  /// Without it the app shows `SetupRequiredScreen` instead of starting.
  static const String apiKey = String.fromEnvironment('MAPTILER_KEY');

  /// Base street map tiles.
  static const String baseTileUrl =
      'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$apiKey';

  /// University of Mindanao georeferenced overlay tiles.
  static const String umOverlayTileUrl =
      'https://api.maptiler.com/tiles/019fff21-f053-72a0-838d-683bbccd7aa7/{z}/{x}/{y}.webp?key=$apiKey';

  static const String userAgentPackageName = 'com.umindanao.umarnav';

  /// Center of the Matina campus.
  static const LatLng campusCenter = LatLng(7.0673125, 125.5951125);

  /// Tight bounds hugging the campus footprint.
  static final LatLngBounds campusBounds = LatLngBounds(
    const LatLng(7.071134, 125.591317),
    const LatLng(7.063491, 125.598908),
  );

  /// Loose bounds used to constrain the camera without trapping the user.
  static final LatLngBounds cameraBounds = LatLngBounds(
    const LatLng(7.040, 125.560),
    const LatLng(7.100, 125.630),
  );

  static const double minZoom = 14.5;
  static const double maxZoom = 18;

  /// Tiles are saved on the phone from this zoom up (`CampusTileCache`), so
  /// below it an offline map has nothing to show.
  static const double offlineMinZoom = 16;

  static double minZoomFor({required bool online}) =>
      online ? minZoom : offlineMinZoom;

  /// Zoom threshold at/above which building text labels appear.
  static const double buildingLabelZoom = 17.0;
}
