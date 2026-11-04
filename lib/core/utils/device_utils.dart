import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'uuid.dart';

/// Stable per-install identifier, shared by visitor sessions, trips and SUS.
class DeviceUtils {
  DeviceUtils._();

  static const _deviceCodeKey = 'device_code';

  static Future<String>? _deviceCode;

  /// The evaluation data's `device_code`: a random UUID made once per install
  /// and kept on the device. It comes from no hardware id, name, email or
  /// location, so it says nothing about the person.
  static Future<String> getDeviceCode() => _deviceCode ??= _loadDeviceCode();

  static Future<String> _loadDeviceCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_deviceCodeKey);
      if (isUuid(saved)) return saved!;
      final code = uuidV4();
      await prefs.setString(_deviceCodeKey, code);
      return code;
    } catch (_) {
      _deviceCode = null; // try again next time
      rethrow;
    }
  }

  @visibleForTesting
  static void resetDeviceCode() => _deviceCode = null;
}
