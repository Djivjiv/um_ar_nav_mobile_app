import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';

/// Tracks whether the Supabase backend is reachable.
///
/// State changes come from two sources:
/// - every repository read / queued write reports its outcome
///   ([reportOnline] / [reportOffline]);
/// - a periodic probe (started with [start]) and a probe on app resume.
///
/// Going from offline to online runs the [addReconnectListener] callbacks
/// (background refresh + flushing queued writes).
class ConnectivityService extends ChangeNotifier with WidgetsBindingObserver {
  ConnectivityService({
    Future<bool> Function()? probe,
    DateTime Function()? now,
  })  : _probe = probe ?? _probeSupabase,
        _now = now ?? DateTime.now;

  static final ConnectivityService instance = ConnectivityService();

  static const String _lastSyncKey = 'offline_last_sync_at';
  static const Duration _onlineProbeInterval = Duration(seconds: 45);
  static const Duration _offlineProbeInterval = Duration(seconds: 15);

  final Future<bool> Function() _probe;
  final DateTime Function() _now;
  final List<Future<void> Function()> _reconnectListeners = [];

  bool _online = true;
  bool _started = false;
  bool _probing = false;
  Timer? _timer;
  DateTime? _lastSyncedAt;
  DateTime? _oldestCacheShown;
  DateTime? _lastSyncPersistedAt;

  bool get isOnline => _online;

  /// When the data on screen was last refreshed from the server: the oldest
  /// cached copy served while offline, else the last successful network
  /// read. Null when nothing is known yet.
  DateTime? get dataUpdatedAt => _oldestCacheShown ?? _lastSyncedAt;

  /// Starts periodic probing and app-resume checks. Safe to call twice.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastSyncedAt = DateTime.tryParse(prefs.getString(_lastSyncKey) ?? '');
    } catch (_) {}
    WidgetsBinding.instance.addObserver(this);
    _schedule();
    unawaited(checkNow());
  }

  void addReconnectListener(Future<void> Function() listener) =>
      _reconnectListeners.add(listener);

  /// A server call succeeded.
  void reportOnline() {
    final now = _now();
    _lastSyncedAt = now;
    _persistLastSync(now);
    if (_online) return;
    _online = true;
    _oldestCacheShown = null;
    _schedule();
    notifyListeners();
    _runReconnectListeners();
  }

  /// A server call failed because the server could not be reached.
  void reportOffline() {
    if (!_online) return;
    _online = false;
    _schedule();
    notifyListeners();
  }

  /// A cached copy saved at [savedAt] was shown instead of live data.
  void reportServedFromCache(DateTime savedAt) {
    if (_oldestCacheShown == null || savedAt.isBefore(_oldestCacheShown!)) {
      _oldestCacheShown = savedAt;
      if (!_online) notifyListeners();
    }
  }

  /// Probes the backend now and updates the state.
  Future<void> checkNow() async {
    if (_probing) return;
    _probing = true;
    try {
      final reachable = await _probe();
      reachable ? reportOnline() : reportOffline();
    } catch (_) {
      reportOffline();
    } finally {
      _probing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(checkNow());
  }

  void _schedule() {
    if (!_started) return;
    _timer?.cancel();
    _timer = Timer.periodic(
      _online ? _onlineProbeInterval : _offlineProbeInterval,
      (_) => checkNow(),
    );
  }

  void _runReconnectListeners() {
    for (final l in List.of(_reconnectListeners)) {
      unawaited(Future(l).catchError(
          (Object e) => debugPrint('Reconnect refresh failed: $e')));
    }
  }

  void _persistLastSync(DateTime at) {
    // At most one write per minute — this runs on every successful read.
    final last = _lastSyncPersistedAt;
    if (last != null && at.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _lastSyncPersistedAt = at;
    unawaited(SharedPreferences.getInstance()
        .then((p) => p.setString(_lastSyncKey, at.toIso8601String()))
        .catchError((Object _) => false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Any HTTP answer from Supabase (even 401) means the server is reachable.
  static Future<bool> _probeSupabase() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client
          .getUrl(Uri.parse('${SupabaseConfig.url}/auth/v1/health'))
          .timeout(const Duration(seconds: 5));
      req.headers.set('apikey', SupabaseConfig.anonKey);
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
