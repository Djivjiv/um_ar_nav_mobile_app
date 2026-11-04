import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';

/// Passes [kBlockScreenCapture] to Android, which applies FLAG_SECURE
/// (`MainActivity.kt`).
class ScreenCapture {
  ScreenCapture._();

  /// The channel `MainActivity` already opens for the clock.
  static const MethodChannel _channel = MethodChannel('com.um.arnav/clock');

  static const String method = 'setBlockScreenCapture';

  /// Call before the first frame, so nothing is drawn unprotected. Never
  /// throws. It does nothing on iOS, which has no handler for it.
  static Future<void> apply({bool block = kBlockScreenCapture}) async {
    try {
      await _channel.invokeMethod<void>(method, block);
    } on MissingPluginException {
      // Android only.
    } catch (e) {
      debugPrint('Screen capture setting not applied: $e');
    }
  }
}
