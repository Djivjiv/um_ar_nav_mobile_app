import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges Flutter to a Unity AR player embedded as its own Android
/// Activity — exported from Unity as an Android Library (.aar), NOT via
/// `flutter_unity_widget` (see `unity-ar-blocked` project memory for why
/// that package doesn't work on this project's Android toolchain).
///
/// Talks to native code purely through a [MethodChannel] (Flutter → Unity)
/// and an [EventChannel] (Unity → Flutter). The native side lives at
/// `android/app/src/main/kotlin/.../UnityBridge.kt`.
///
/// The Unity `.aar` itself isn't in this repo yet, so [isAvailable] returns
/// `false` and every start call resolves to `false` with an `error` event —
/// gracefully, not by crashing. Once the `.aar` is added under
/// `android/unityLibrary` and wired into `android/app/build.gradle`, this
/// class needs no changes at all.
class UnityBridgeService {
  UnityBridgeService._();
  static final UnityBridgeService instance = UnityBridgeService._();

  static const MethodChannel _methodChannel =
      MethodChannel('com.um.arnav/unity');
  static const EventChannel _eventChannel =
      EventChannel('com.um.arnav/unity_events');

  Stream<Map<String, dynamic>>? _events;

  /// Broadcast stream of events the native/Unity side sends back, each a
  /// `{'event': 'arrived' | 'qr_scanned' | 'error', ...payload}` map.
  Stream<Map<String, dynamic>> get events =>
      _events ??= _eventChannel.receiveBroadcastStream().map(_asEventMap);

  Map<String, dynamic> _asEventMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{
      'event': 'error',
      'message': 'Malformed Unity event: $raw',
    };
  }

  /// Whether a real Unity player is available on the native side right now.
  /// A cheap local check (class-presence reflection) — no Unity boot, no
  /// activity launch — so it's safe to call before deciding whether to show
  /// Unity AR or go straight to the 2D/camera fallback.
  Future<bool> isAvailable() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isUnityAvailable') ??
          false;
    } on PlatformException catch (e) {
      debugPrint('🎮 [UnityBridge] isAvailable failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Starts outdoor GPS-arrow AR guidance. `routeData` is the JSON-shaped
  /// map from `ARStartMessage.toJson()`.
  Future<bool> startOutdoorNavigation(Map<String, dynamic> routeData) =>
      _invoke('startOutdoorNavigation', routeData);

  /// Starts indoor node-based AR arrow guidance. `indoorData` is the
  /// JSON-shaped map from `ARIndoorMessage.toJson()`.
  Future<bool> startIndoorNavigation(Map<String, dynamic> indoorData) =>
      _invoke('startIndoorNavigation', indoorData);

  /// Stops/dismisses the current Unity navigation session, if any.
  Future<bool> stopNavigation() => _invoke('stopNavigation', null);

  Future<bool> _invoke(String method, Map<String, dynamic>? args) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(method, args);
      return result ?? true;
    } on PlatformException catch (e) {
      debugPrint('🎮 [UnityBridge] $method failed: ${e.message}');
      return false;
    } on MissingPluginException {
      debugPrint('🎮 [UnityBridge] $method: no native Unity bridge registered');
      return false;
    }
  }
}
