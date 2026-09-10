import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Stable per-install identifier used for visitor sessions.
class DeviceUtils {
  DeviceUtils._();

  static const _key = 'device_id';

  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_key);

    if (deviceId == null) {
      final random = Random();
      deviceId = 'device-'
          '${DateTime.now().millisecondsSinceEpoch}-'
          '${random.nextInt(999999)}';
      await prefs.setString(_key, deviceId);
    }

    return deviceId;
  }
}
