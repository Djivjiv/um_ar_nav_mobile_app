import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/connectivity_service.dart';

/// One insert waiting to reach the server.
class PendingWrite {
  final String id;
  final String table;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;

  /// True for data that must never be discarded (survey answers, comments).
  /// Other writes are dropped after [PendingWriteQueue.maxRejections] server
  /// rejections, so a permanently invalid row can't pile up forever.
  final bool keepForever;

  const PendingWrite({
    required this.id,
    required this.table,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.keepForever = false,
  });

  PendingWrite retried() => PendingWrite(
        id: id,
        table: table,
        payload: payload,
        createdAt: createdAt,
        attempts: attempts + 1,
        keepForever: keepForever,
      );

  /// [payload] as it goes to the server: each `*_at` time in UTC. Rows queued
  /// by an older app have times with no timezone, which read as the phone's
  /// local time.
  Map<String, dynamic> get sendable => {
        for (final MapEntry(:key, :value) in payload.entries)
          key: key.endsWith('_at') && value is String
              ? DateTime.tryParse(value)?.toUtc().toIso8601String() ?? value
              : value,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
        'keepForever': keepForever,
      };

  static PendingWrite? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final payload = m['payload'];
    if (payload is! Map || m['table'] == null || m['id'] == null) return null;
    return PendingWrite(
      id: m['id'].toString(),
      table: m['table'].toString(),
      payload: payload.cast<String, dynamic>(),
      createdAt:
          DateTime.tryParse(m['createdAt']?.toString() ?? '') ?? DateTime.now(),
      attempts: (m['attempts'] as num?)?.toInt() ?? 0,
      keepForever: m['keepForever'] == true,
    );
  }
}

/// Outcome of a [PendingWriteQueue.flush].
class FlushResult {
  final int sent;
  final int remaining;
  final int dropped;
  const FlushResult({this.sent = 0, this.remaining = 0, this.dropped = 0});
}

/// A persistent outbox for inserts (SUS responses, comments, navigation logs).
///
/// Callers [enqueue] first, then [flush]: the row is on disk before any
/// network attempt, so it survives a dead connection, a timeout or the app
/// being killed. [flush] runs on app start, when the connection returns and
/// after every enqueue. Rows are sent oldest first.
class PendingWriteQueue {
  PendingWriteQueue({
    Future<void> Function(String table, Map<String, dynamic> payload)? sender,
    ConnectivityService? connectivity,
    DateTime Function()? now,
    this.sendTimeout = const Duration(seconds: 12),
  })  : _sender = sender ?? _supabaseInsert,
        _connectivity = connectivity ?? ConnectivityService.instance,
        _now = now ?? DateTime.now;

  static final PendingWriteQueue instance = PendingWriteQueue();

  static const String storageKey = 'pending_writes';

  /// Server rejections after which a non-[PendingWrite.keepForever] write is
  /// dropped.
  static const int maxRejections = 5;

  /// Postgres error code for a row that breaks a unique rule.
  static const String uniqueViolation = '23505';

  final Future<void> Function(String table, Map<String, dynamic> payload)
      _sender;
  final ConnectivityService _connectivity;
  final DateTime Function() _now;
  final Duration sendTimeout;

  /// Serialises every read-modify-write of the stored list.
  Future<void> _lock = Future.value();

  Future<R> _synchronized<R>(Future<R> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<void> _supabaseInsert(
          String table, Map<String, dynamic> payload) =>
      insertDroppingUnknownColumns(
          (row) => Supabase.instance.client.from(table).insert(row),
          table,
          payload);

  static final RegExp _unknownColumn = RegExp(
      r"""Could not find the '([^']+)' column|column "([^"]+)" of relation "[^"]+" does not exist""");

  /// The column a server error says is missing, else null.
  static String? unknownColumnIn(PostgrestException e) {
    final m = _unknownColumn.firstMatch(e.message);
    return m == null ? null : (m.group(1) ?? m.group(2));
  }

  /// Inserts [payload] with [insert]; when the server says a column does
  /// not exist (database not migrated yet — see
  /// `supabase/navigation_evaluation.sql`), that column is dropped and the
  /// insert retried, so the rest of the row is still saved.
  static Future<void> insertDroppingUnknownColumns(
    Future<void> Function(Map<String, dynamic> row) insert,
    String table,
    Map<String, dynamic> payload,
  ) async {
    final row = Map<String, dynamic>.of(payload);
    while (true) {
      try {
        await insert(row);
        return;
      } on PostgrestException catch (e) {
        final column = unknownColumnIn(e);
        if (column == null || !row.containsKey(column)) rethrow;
        debugPrint('📤 $table has no "$column" column — sending without it. '
            'Run supabase/navigation_evaluation.sql to keep this data.');
        row.remove(column);
      }
    }
  }

  /// Stores [payload] for [table] and returns its id. Throws only if the
  /// device storage itself fails.
  Future<String> enqueue(
    String table,
    Map<String, dynamic> payload, {
    bool keepForever = false,
  }) {
    return _synchronized(() async {
      final items = await _load();
      final id =
          '${_now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
      items.add(PendingWrite(
        id: id,
        table: table,
        payload: payload,
        createdAt: _now(),
        keepForever: keepForever,
      ));
      await _store(items);
      return id;
    });
  }

  Future<List<PendingWrite>> pending() => _synchronized(_load);

  Future<bool> isPending(String id) async =>
      (await pending()).any((w) => w.id == id);

  /// Sends queued writes oldest first. Stops at the first network failure
  /// (the rest would fail too); a server rejection moves on to the next.
  Future<FlushResult> flush() {
    return _synchronized(() async {
      final items = await _load();
      if (items.isEmpty) return const FlushResult();
      var sent = 0;
      var dropped = 0;
      final keep = <PendingWrite>[];
      var offline = false;
      for (final w in items) {
        if (offline) {
          keep.add(w);
          continue;
        }
        try {
          await _sender(w.table, w.sendable).timeout(sendTimeout);
          sent++;
          _connectivity.reportOnline();
        } on PostgrestException catch (e) {
          if (e.code == uniqueViolation) {
            // The server already has this row, so this isn't a lost answer:
            // a retry after a lost reply, or a second SUS from one person
            // (supabase/sus_once_per_person.sql). It can never succeed.
            sent++;
            debugPrint('📤 ${w.table} write already on the server');
            continue;
          }
          final next = w.retried();
          if (!w.keepForever && next.attempts >= maxRejections) {
            dropped++;
            debugPrint('📤 Dropping ${w.table} write after '
                '${next.attempts} rejections: ${e.message}');
          } else {
            debugPrint('📤 ${w.table} write rejected: ${e.message}');
            keep.add(next);
          }
        } catch (e) {
          debugPrint('📤 Offline — ${items.length - sent - dropped} '
              'write(s) stay queued ($e)');
          _connectivity.reportOffline();
          offline = true;
          keep.add(w);
        }
      }
      await _store(keep);
      return FlushResult(sent: sent, remaining: keep.length, dropped: dropped);
    });
  }

  Future<List<PendingWrite>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map(PendingWrite.fromJson)
          .whereType<PendingWrite>()
          .toList();
    } catch (e) {
      // Never silently wipe a corrupt queue — keep the raw text aside.
      debugPrint('📤 Unreadable write queue, preserving it: $e');
      await prefs.setString('$storageKey.corrupt', raw);
      await prefs.remove(storageKey);
      return [];
    }
  }

  Future<void> _store(List<PendingWrite> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(storageKey);
    } else {
      await prefs.setString(
          storageKey, jsonEncode(items.map((w) => w.toJson()).toList()));
    }
  }
}
