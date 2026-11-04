import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Session-time management for signed-in users:
/// `user_profiles.session_start` + 8h. Visitors are in
/// `VisitorSessionRepository`.
///
/// The server copy is checked first. The time is also kept on the device, so
/// without a connection the app keeps working until the same deadline instead
/// of signing the user out. (It is written from the device clock.)
class SessionService {
  SessionService._();

  @visibleForTesting
  static SupabaseClient? testClient;

  static SupabaseClient get _supabase =>
      testClient ?? Supabase.instance.client;

  static const String loginTimeKey = 'login_time';

  // ─────────────────────────────────
  // AUTHENTICATED USER — 8 hour check
  // ─────────────────────────────────

  /// Call after a successful sign-in.
  static Future<void> saveUserSessionStart(String userId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    // Device copy first — it is what offline launches check.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(loginTimeKey, nowIso);
    } catch (e) {
      debugPrint('❌ Save local session error: $e');
    }
    try {
      await _supabase.from('user_profiles').update({
        'session_start': nowIso,
        'last_seen': nowIso,
      }).eq('id', userId);
      debugPrint('✅ User session start saved');
    } catch (e) {
      debugPrint('❌ Save session error: $e');
    }
  }

  /// `session_start` from the server, or the device copy when the server
  /// has none or can't be reached.
  static Future<DateTime?> _userSessionStart(String userId) async {
    DateTime? serverStart;
    try {
      final response = await _supabase
          .from('user_profiles')
          .select('session_start')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      serverStart = response == null
          ? null
          : DateTime.tryParse((response['session_start'] ?? '').toString());
    } catch (e) {
      debugPrint('⚠️ Session check offline — using the device copy ($e)');
    }
    return serverStart?.toUtc() ?? await _localLoginTime();
  }

  /// Call on every app launch. Returns true while the 8h window is open.
  static Future<bool> isUserSessionValid(String userId) async {
    try {
      final sessionStart = await _userSessionStart(userId);
      if (sessionStart == null) {
        debugPrint('❌ No session start found');
        return false;
      }

      final hoursSince = DateTime.now().toUtc().difference(sessionStart).inHours;
      debugPrint('⏱ Hours since login: $hoursSince '
          '(limit ${AppConfig.userSessionHours})');

      if (hoursSince >= AppConfig.userSessionHours) {
        debugPrint('❌ User session expired');
        await _clearUserSession(userId);
        return false;
      }

      debugPrint('✅ User session valid — '
          '${AppConfig.userSessionHours - hoursSince}h remaining');
      return true;
    } catch (e) {
      debugPrint('❌ Session check error: $e');
      return false;
    }
  }

  static Future<void> _clearUserSession(String userId) async {
    try {
      await _supabase
          .from('user_profiles')
          .update({'session_start': null}).eq('id', userId);
    } catch (e) {
      debugPrint('❌ Clear session error: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(loginTimeKey);
    } catch (_) {}
  }

  /// Whole hours remaining on the authenticated session (0 if expired).
  static Future<int> getUserRemainingHours(String userId) async {
    try {
      final sessionStart = await _userSessionStart(userId);
      if (sessionStart == null) return 0;
      final hoursSince =
          DateTime.now().toUtc().difference(sessionStart).inHours;
      final remaining = AppConfig.userSessionHours - hoursSince;
      return remaining > 0 ? remaining : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<DateTime?> _localLoginTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(loginTimeKey);
      return str == null ? null : DateTime.tryParse(str)?.toUtc();
    } catch (_) {
      return null;
    }
  }
}
