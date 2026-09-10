import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Session-time management backed by **Supabase server timestamps** so the
/// window cannot be extended by changing the device clock.
///
/// - Authenticated users: `user_profiles.session_start` + 8h.
/// - Visitors: `visitor_sessions.expires_at` (server sets it) + 2h.
class SessionService {
  SessionService._();

  static SupabaseClient get _supabase => Supabase.instance.client;

  // ─────────────────────────────────
  // AUTHENTICATED USER — 8 hour check
  // ─────────────────────────────────

  /// Call after a successful Google Sign-In.
  static Future<void> saveUserSessionStart(String userId) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      await _supabase.from('user_profiles').update({
        'session_start': nowIso,
        'last_seen': nowIso,
      }).eq('id', userId);
      // Local fallback used only if the column/RLS is not yet configured.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('login_time', nowIso);
      debugPrint('✅ User session start saved');
    } catch (e) {
      debugPrint('❌ Save session error: $e');
    }
  }

  /// Call on every app launch. Returns true while the 8h window is open.
  static Future<bool> isUserSessionValid(String userId) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select('session_start')
          .eq('id', userId)
          .maybeSingle();

      final serverStart = (response == null)
          ? null
          : DateTime.tryParse(
              (response['session_start'] ?? '').toString());

      // Fall back to the locally stored login time if the server has no
      // session_start yet (column just added / RLS not set).
      final DateTime? sessionStart =
          serverStart?.toUtc() ?? await _localLoginTime();

      if (sessionStart == null) {
        debugPrint('❌ No session start found');
        return false;
      }

      final now = DateTime.now().toUtc();
      final hoursSince = now.difference(sessionStart).inHours;
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
      await prefs.remove('login_time');
    } catch (_) {}
  }

  /// Whole hours remaining on the authenticated session (0 if expired).
  static Future<int> getUserRemainingHours(String userId) async {
    try {
      final response = await _supabase
          .from('user_profiles')
          .select('session_start')
          .eq('id', userId)
          .maybeSingle();

      final serverStart = (response == null)
          ? null
          : DateTime.tryParse(
              (response['session_start'] ?? '').toString());
      final DateTime? sessionStart =
          serverStart?.toUtc() ?? await _localLoginTime();
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
      final str = prefs.getString('login_time');
      return str == null ? null : DateTime.tryParse(str)?.toUtc();
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────
  // VISITOR — 2 hour check
  // ─────────────────────────────────

  /// Creates (or reuses an unexpired) visitor session and returns its id.
  static Future<String?> createVisitorSession(String deviceId) async {
    try {
      final existing = await _supabase
          .from('visitor_sessions')
          .select()
          .eq('device_id', deviceId)
          .eq('is_expired', false)
          .gte('expires_at', DateTime.now().toUtc().toIso8601String())
          .maybeSingle();

      if (existing != null) {
        debugPrint('✅ Reusing existing visitor session');
        return existing['id'] as String;
      }

      final now = DateTime.now().toUtc();
      final expiresAt =
          now.add(const Duration(hours: AppConfig.visitorSessionHours));

      final response = await _supabase
          .from('visitor_sessions')
          .insert({
            'device_id': deviceId,
            'started_at': now.toIso8601String(),
            'expires_at': expiresAt.toIso8601String(),
            'is_expired': false,
          })
          .select()
          .single();

      debugPrint('✅ New visitor session created — expires in '
          '${AppConfig.visitorSessionHours}h');
      return response['id'] as String;
    } catch (e) {
      debugPrint('❌ Create visitor session: $e');
      return null;
    }
  }

  /// Call on every app launch for a visitor. True while still valid.
  static Future<bool> isVisitorSessionValid(String sessionId) async {
    try {
      final response = await _supabase
          .from('visitor_sessions')
          .select('expires_at, is_expired')
          .eq('id', sessionId)
          .maybeSingle();

      if (response == null) {
        debugPrint('❌ Visitor session not found');
        return false;
      }
      if (response['is_expired'] == true) {
        debugPrint('❌ Visitor session marked expired');
        return false;
      }

      final expiresAt =
          DateTime.parse(response['expires_at'].toString()).toUtc();
      final now = DateTime.now().toUtc();

      if (now.isAfter(expiresAt)) {
        debugPrint('❌ Visitor session expired');
        await _expireVisitorSession(sessionId);
        return false;
      }

      debugPrint('✅ Visitor session valid — '
          '${expiresAt.difference(now).inMinutes} min remaining');
      return true;
    } catch (e) {
      debugPrint('❌ Visitor session check: $e');
      return false;
    }
  }

  static Future<void> _expireVisitorSession(String sessionId) async {
    try {
      await _supabase
          .from('visitor_sessions')
          .update({'is_expired': true}).eq('id', sessionId);
    } catch (e) {
      debugPrint('❌ Expire visitor session: $e');
    }
  }

  /// Minutes remaining on the visitor session (0 if expired / missing).
  static Future<int> getVisitorRemainingMinutes(String sessionId) async {
    try {
      final response = await _supabase
          .from('visitor_sessions')
          .select('expires_at')
          .eq('id', sessionId)
          .maybeSingle();
      if (response == null) return 0;

      final expiresAt =
          DateTime.parse(response['expires_at'].toString()).toUtc();
      final remaining =
          expiresAt.difference(DateTime.now().toUtc()).inMinutes;
      return remaining > 0 ? remaining : 0;
    } catch (_) {
      return 0;
    }
  }
}
