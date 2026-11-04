import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../config/campus_bounds.dart';

enum GeofenceResult {
  insideCampus,
  outsideCampus,
  permissionDenied,
  locationUnavailable,
}

class GeofenceService {
  GeofenceService._();

  /// True once this app run has confirmed the user is physically on campus.
  /// Reset on sign-out and on a cold start. Lets `MainScreen` gate `/map`
  /// without re-doing a GPS fix on every tab switch, and closes the window
  /// where the go_router redirect races an in-session sign-in straight to the
  /// map before the async geofence check finishes.
  static bool campusVerified = false;

  /// Main entry point — call on app launch (after the auth check).
  static Future<GeofenceResult> checkUserLocation() async {
    debugPrint('🔍 GEOFENCE CHECK STARTED');
    debugPrint('   Skip geofence: ${AppConfig.skipGeofenceCheck}');

    if (AppConfig.skipGeofenceCheck) {
      debugPrint('⚠️ SKIPPED — dev mode');
      return GeofenceResult.insideCampus;
    }

    // 1. Location service.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint('   Location service enabled: $serviceEnabled');
    if (!serviceEnabled) {
      debugPrint('❌ Location service disabled');
      return GeofenceResult.locationUnavailable;
    }

    // 2. Permission.
    var permission = await Geolocator.checkPermission();
    debugPrint('   Current permission: $permission');
    if (permission == LocationPermission.denied) {
      debugPrint('   Requesting permission...');
      permission = await Geolocator.requestPermission();
      debugPrint('   Permission after request: $permission');
    }
    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ Permission denied forever');
      return GeofenceResult.permissionDenied;
    }
    if (permission == LocationPermission.denied) {
      debugPrint('❌ Permission denied');
      return GeofenceResult.permissionDenied;
    }

    // 3. GPS position.
    debugPrint('   Getting GPS position...');
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      debugPrint('📍 GPS Position:');
      debugPrint('   Accuracy: ${position.accuracy}m');

      debugPrint('   Campus bounds:');
      debugPrint('   MinLat: $campusMinLat  MaxLat: $campusMaxLat');
      debugPrint('   MinLng: $campusMinLng  MaxLng: $campusMaxLng');

      final inBounds = position.latitude >= campusMinLat &&
          position.latitude <= campusMaxLat &&
          position.longitude >= campusMinLng &&
          position.longitude <= campusMaxLng;
      debugPrint('   In bounding box: $inBounds');

      final inside = isInsideCampus(position.latitude, position.longitude);
      debugPrint('   Inside campus polygon: $inside');
      debugPrint(inside ? '✅ INSIDE CAMPUS' : '❌ OUTSIDE CAMPUS');

      return inside
          ? GeofenceResult.insideCampus
          : GeofenceResult.outsideCampus;
    } on TimeoutException {
      debugPrint('❌ GPS timeout');
      return GeofenceResult.locationUnavailable;
    } catch (e) {
      debugPrint('❌ GPS error: $e');
      return GeofenceResult.locationUnavailable;
    }
  }

  /// One GPS fix → polygon test.
  /// `true` = inside campus, `false` = outside, `null` = no fix / no
  /// permission (caller decides — usually lenient for a signed-in user).
  static Future<bool?> currentlyInsideCampus({
    Duration timeLimit = const Duration(seconds: 15),
  }) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      debugPrint('📍 GPS fix '
          '(±${pos.accuracy.toStringAsFixed(0)}m)');
      final inside = isInsideCampus(pos.latitude, pos.longitude);
      debugPrint(inside ? '✅ Inside campus' : '❌ Outside campus');
      return inside;
    } catch (e) {
      debugPrint('❌ GPS error: $e');
      return null;
    }
  }

  /// Post-auth campus gate used everywhere that leads into the map (splash,
  /// login, role selection, visitor) — so an in-session sign-in can't bypass
  /// it. Routes to `/outside-campus` and returns false when the user is
  /// verified OUTSIDE; returns true when inside OR when the fix failed (the
  /// user already has a valid session — don't lock them out over bad GPS).
  static Future<bool> gate(BuildContext context) async {
    if (AppConfig.skipGeofenceCheck) return true;
    final inside = await currentlyInsideCampus();
    if (!context.mounted) return false;
    if (inside == false) {
      campusVerified = false;
      context.go('/outside-campus');
      return false;
    }
    if (inside == true) campusVerified = true;
    return true;
  }

  /// True when (lat, lng) is within the campus polygon.
  static bool isInsideCampus(double lat, double lng) {
    // Fast bounding-box rejection.
    if (lat < campusMinLat ||
        lat > campusMaxLat ||
        lng < campusMinLng ||
        lng > campusMaxLng) {
      return false;
    }
    return _isPointInPolygon(LatLng(lat, lng), campusPolygon);
  }

  /// Ray-casting (even-odd rule) point-in-polygon test.
  static bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    var intersections = 0;
    final n = polygon.length;

    for (var i = 0; i < n; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % n];

      final straddles = (a.latitude <= point.latitude &&
              point.latitude < b.latitude) ||
          (b.latitude <= point.latitude && point.latitude < a.latitude);
      if (!straddles) continue;

      final lngAtLat = (b.longitude - a.longitude) *
              (point.latitude - a.latitude) /
              (b.latitude - a.latitude) +
          a.longitude;

      if (point.longitude < lngAtLat) {
        intersections++;
      }
    }

    return intersections.isOdd;
  }

  /// Opens the OS location settings screen.
  static Future<void> openSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Opens this app's settings screen (for permanently denied permission).
  static Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }
}

/// For the screens that lead into the map.
mixin CampusGate<T extends StatefulWidget> on State<T> {
  bool _gating = false;

  /// Signed in, but still verifies the user is on campus before the map.
  Future<void> gateToMap() async {
    if (_gating) return;
    _gating = true;
    final inside = await GeofenceService.gate(context);
    if (inside && mounted) context.go('/map');
    _gating = false;
  }
}
