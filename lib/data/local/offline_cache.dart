import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/network/connectivity_service.dart';

/// A cached copy of server rows and when it was saved.
class CacheEntry {
  final Object? data;
  final DateTime savedAt;
  const CacheEntry(this.data, this.savedAt);
}

/// The result of a network-first read.
class CacheRead<T> {
  final T data;

  /// True when the network failed and [data] came from the local cache.
  final bool fromCache;

  /// When [data] was fetched from the server.
  final DateTime savedAt;

  const CacheRead(this.data, {required this.fromCache, required this.savedAt});
}

/// Local, timestamped copies of server data for offline use.
///
/// [read] is network-first: a successful load replaces the cached copy; a
/// failed one (no connection, timeout, server error) falls back to the last
/// saved copy, and rethrows the original error only when there is none.
///
/// Values must be JSON-encodable (Supabase rows are). Stored in
/// SharedPreferences under [_prefix].
class OfflineCache {
  OfflineCache({
    ConnectivityService? connectivity,
    DateTime Function()? now,
    this.networkTimeout = const Duration(seconds: 12),
  })  : _connectivity = connectivity ?? ConnectivityService.instance,
        _now = now ?? DateTime.now;

  static final OfflineCache instance = OfflineCache();

  static const String _prefix = 'offline_cache.';

  final ConnectivityService _connectivity;
  final DateTime Function() _now;
  final Duration networkTimeout;

  /// [key] for the log, without the id of the row or person after the colon.
  static String _logName(String key) => key.split(':').first;

  Future<CacheRead<T>> read<T>(
    String key,
    Future<T> Function() network,
  ) async {
    try {
      final live = await network().timeout(networkTimeout);
      _connectivity.reportOnline();
      final savedAt = _now();
      await save(key, live, savedAt: savedAt);
      return CacheRead(live, fromCache: false, savedAt: savedAt);
    } catch (e) {
      // A PostgrestException means the server answered — still online.
      if (e is! PostgrestException) _connectivity.reportOffline();
      final cached = await get(key);
      if (cached == null) rethrow;
      debugPrint('📦 Offline: using cached "${_logName(key)}" '
          'from ${cached.savedAt} ($e)');
      _connectivity.reportServedFromCache(cached.savedAt);
      return CacheRead(cached.data as T,
          fromCache: true, savedAt: cached.savedAt);
    }
  }

  /// Convenience for [read] when only the data is needed.
  Future<T> fetch<T>(String key, Future<T> Function() network) async =>
      (await read<T>(key, network)).data;

  Future<void> save(String key, Object? data, {DateTime? savedAt}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefix$key',
        jsonEncode({
          'savedAt': (savedAt ?? _now()).toIso8601String(),
          'data': data,
        }),
      );
    } catch (e) {
      // A cache write must never break a successful load.
      debugPrint('📦 Could not cache "${_logName(key)}": $e');
    }
  }

  Future<CacheEntry?> get(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(m['savedAt']?.toString() ?? '');
      if (savedAt == null) return null;
      return CacheEntry(m['data'], savedAt);
    } catch (e) {
      debugPrint('📦 Unreadable cache "${_logName(key)}": $e');
      return null;
    }
  }

  Future<void> remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
    } catch (_) {}
  }

  /// Every cached entry whose key starts with [keyPrefix].
  Future<Map<String, CacheEntry>> getAll(String keyPrefix) async {
    final out = <String, CacheEntry>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        if (!k.startsWith('$_prefix$keyPrefix')) continue;
        final key = k.substring(_prefix.length);
        final entry = await get(key);
        if (entry != null) out[key] = entry;
      }
    } catch (_) {}
    return out;
  }
}
