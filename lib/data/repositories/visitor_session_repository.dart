import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/device_utils.dart';
import '../../core/utils/server_clock.dart';
import '../../core/utils/uuid.dart';
import '../models/visitor_session_model.dart';

/// Calls a database function.
typedef RpcCall = Future<Object?> Function(
    String function, Map<String, dynamic> params);

/// Visitor sessions, started and timed by the server (see
/// `supabase/visitor_sessions.sql`). The session and its [ServerClock] are
/// also kept on the device, so without a connection it counts down to the
/// same moment.
class VisitorSessionRepository {
  VisitorSessionRepository({
    RpcCall? rpc,
    ClockSource? source,
    Future<String> Function()? deviceCode,
  })  : _rpc = rpc ?? _supabaseRpc,
        _source = source ?? const ClockSource(),
        _deviceCode = deviceCode ?? DeviceUtils.getDeviceCode;

  final RpcCall _rpc;
  final ClockSource _source;
  final Future<String> Function() _deviceCode;

  static const String storageKey = 'visitor_session';

  /// Prefix of sessions started without a connection. They exist only on this
  /// device (no `visitor_sessions` row), and their trips and SUS answers are
  /// tagged by `device_code` alone.
  static const String localPrefix = 'local-';

  /// How often [refresh] asks the server, when it can.
  static const Duration serverCheckEvery = Duration(minutes: 1);

  static const Duration _timeout = Duration(seconds: 10);

  Duration? _lastServerCheck;

  static Future<Object?> _supabaseRpc(
          String function, Map<String, dynamic> params) =>
      Supabase.instance.client.rpc(function, params: params);

  /// The session still running on this device, else a new one on the server
  /// with this device's `device_code`. Without a connection, a device-only
  /// session so a visitor can still navigate. Null when the server answered
  /// with an error.
  Future<VisitorSessionModel?> start() async {
    final stored = await restore();
    if (stored != null && stored.isStillValid) return stored;
    await clear();

    final code = await _deviceCode();
    try {
      final row = await _rpc('start_visitor_session', {'p_device_code': code})
          .timeout(_timeout);
      if (row is! Map) {
        debugPrint('❌ Start visitor session: unexpected answer');
        return null;
      }
      final session = await _fromServer(row.cast<String, dynamic>());
      if (session == null) {
        debugPrint('❌ Start visitor session: unreadable answer');
        return null;
      }
      debugPrint('✅ Visitor session started — '
          '${session.remaining.inMinutes} min remaining');
      return await _save(session);
    } on PostgrestException catch (e) {
      debugPrint('❌ Start visitor session: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('⚠️ Offline — started a device-only visitor session ($e)');
      return await _save(await _deviceOnly(code));
    }
  }

  /// The saved session, brought up to date, or null when there is none. It
  /// may have ended: check [VisitorSessionModel.isStillValid].
  Future<VisitorSessionModel?> restore() async {
    final session = await _load();
    return session == null ? null : refresh(session, force: true);
  }

  /// Counts the time that has passed and, when due or [force], takes the
  /// server's word on the time and on whether the session still stands.
  Future<VisitorSessionModel> refresh(
    VisitorSessionModel session, {
    bool force = false,
  }) async {
    await session.clock.sync();
    var current = session;
    if (!session.id.startsWith(localPrefix) && (force || _serverCheckDue)) {
      _lastServerCheck = _source.running();
      current = await _askServer(session);
    }
    return _save(current);
  }

  /// Removes the session from the device.
  Future<void> clear() async {
    _lastServerCheck = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (e) {
      debugPrint('Clear visitor session: $e');
    }
  }

  bool get _serverCheckDue {
    final last = _lastServerCheck;
    return last == null || _source.running() - last >= serverCheckEvery;
  }

  Future<VisitorSessionModel> _askServer(VisitorSessionModel session) async {
    try {
      final row = await _rpc('visitor_session_status', {
        'p_session_id': session.id,
        'p_device_code': session.deviceCode,
      }).timeout(_timeout);
      if (row == null) return session.copyWith(isExpired: true);
      if (row is! Map) return session;

      final serverNow = DateTime.tryParse(row['server_now']?.toString() ?? '');
      final expiresAt = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (serverNow == null || expiresAt == null) return session;
      await session.clock.correct(serverNow);
      return session.copyWith(
        expiresAt: expiresAt.toUtc(),
        isExpired: row['is_expired'] == true,
      );
    } on PostgrestException catch (e) {
      debugPrint('❌ Visitor session check: ${e.message}');
    } catch (e) {
      debugPrint('⚠️ Visitor session check offline — counting on device ($e)');
    }
    return session;
  }

  Future<VisitorSessionModel?> _fromServer(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    final code = row['device_code']?.toString();
    final serverNow = DateTime.tryParse(row['server_now']?.toString() ?? '');
    final startedAt = DateTime.tryParse(row['started_at']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(row['expires_at']?.toString() ?? '');
    if (id == null ||
        code == null ||
        serverNow == null ||
        startedAt == null ||
        expiresAt == null) {
      return null;
    }
    return VisitorSessionModel(
      id: id,
      deviceCode: code,
      startedAt: startedAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      clock: await ServerClock.start(serverNow, source: _source),
      isExpired: row['is_expired'] == true,
    );
  }

  /// With no server to ask, the 2 hours start from the phone's clock, but
  /// count on [ServerClock] like any other session.
  Future<VisitorSessionModel> _deviceOnly(String code) async {
    final now = _source.phoneNow();
    return VisitorSessionModel(
      id: '$localPrefix${uuidV4()}',
      deviceCode: code,
      startedAt: now,
      expiresAt: now.add(const Duration(hours: AppConfig.visitorSessionHours)),
      clock: await ServerClock.start(now, source: _source),
    );
  }

  Future<VisitorSessionModel> _save(VisitorSessionModel session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(session.toJson()));
    } catch (e) {
      debugPrint('Save visitor session: $e');
    }
    return session;
  }

  Future<VisitorSessionModel?> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return VisitorSessionModel.fromJson(json.cast<String, dynamic>(),
          source: _source);
    } catch (e) {
      debugPrint('Load visitor session: $e');
      return null;
    }
  }
}
