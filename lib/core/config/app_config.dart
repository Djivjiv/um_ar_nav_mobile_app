class AppConfig {
  AppConfig._();

  // ╔══════════════════════════════════╗
  // ║  DEVELOPMENT FLAG                ║
  // ║  true  = skip geofence (testing) ║
  // ║  false = enforce geofence (prod) ║
  // ╚══════════════════════════════════╝
  // This is the ONLY switch — the geofence is enforced in debug builds too
  // unless this is set to true.
  static const bool _forceSkipGeofence = true;

  static bool get skipGeofenceCheck => _forceSkipGeofence;

  // Session durations.
  static const int userSessionHours = 8;
  static const int visitorSessionHours = 2;

  static const String appVersion = '1.0.0';
  static const String appName = 'UM-AR Nav';
  static const String campusName = 'University of Mindanao Matina Campus';
}
