/// Tunable values for the outdoor location-based AR overlay
/// (`ARNavigationScreen`). Kept in one place so they can be adjusted after
/// on-campus testing without hunting through the screen code.
class ArNavConfig {
  ArNavConfig._();

  // ── Camera overlay ──

  /// Horizontal field of view of the camera preview, in degrees. Used to
  /// place AR markers horizontally; targets outside it get an edge arrow.
  static const double cameraHorizontalFovDeg = 60;

  // ── Route following ──

  /// How far ahead of the snapped position (along the route) the target
  /// waypoint sits. The arrow and main marker point at that target.
  static const double lookAheadMeters = 12;

  /// Distance from the route beyond which the user is "off the route".
  static const double offRouteMeters = 25;

  /// The user is back on the route once closer than
  /// `offRouteMeters - offRouteHysteresisMeters` (prevents banner flicker).
  static const double offRouteHysteresisMeters = 5;

  /// GPS fixes less accurate than this don't count towards off-route
  /// detection or the navigation error count.
  static const double offRouteMaxAccuracyMeters = 30;

  /// Fill-in spacing for the fallback path (the outdoor route's own points),
  /// used when the AR path network has no path for the trip.
  static const double fallbackPointSpacingMeters = 6;

  /// The AR network route starts at the AR node nearest the outdoor route's
  /// start — but only if one is this close; otherwise the fallback is used.
  static const double arNetworkMaxStartDistanceMeters = 40;

  /// Snapping prefers the part of the route near the previous snap
  /// (`[prev - back, prev + ahead]` metres along the route) so it does not
  /// jump onto another stretch of the route that passes close by…
  static const double snapSearchBackMeters = 10;
  static const double snapSearchAheadMeters = 50;

  /// …unless the global nearest segment is closer by more than this.
  static const double snapContinuityMeters = 8;

  // ── Smoothing ──

  /// Number of recent GPS fixes averaged into the smoothed position.
  static const int gpsSmoothingWindow = 5;

  /// Requested GPS update interval / distance filter. A 5-fix window at
  /// ~1 s per fix lags roughly 2–3 s (≈3 m at walking pace).
  static const Duration gpsInterval = Duration(seconds: 1);
  static const int gpsDistanceFilterMeters = 0;

  /// Low-pass factor for the compass heading, 0–1. Higher = more
  /// responsive, lower = steadier.
  static const double headingSmoothingAlpha = 0.2;

  // ── Arrival / display ──

  /// Used when `buildings.ar_arrival_radius_m` is missing or not positive.
  static const double defaultArrivalRadiusMeters = 8;

  /// Used when `buildings.ar_emoji` is missing.
  static const String defaultEmoji = '📍';
}
