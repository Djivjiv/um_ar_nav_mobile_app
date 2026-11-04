import 'dart:math' as math;

import 'package:flutter/services.dart';

/// The time sources [ServerClock] reads. Replaced in tests.
class ClockSource {
  const ClockSource();

  static const MethodChannel _channel = MethodChannel('com.um.arnav/clock');
  static final Stopwatch _running = Stopwatch()..start();

  /// The phone's clock, which its owner can change.
  DateTime phoneNow() => DateTime.now().toUtc();

  /// Time this app run has been going. It can't be changed from the phone's
  /// settings, but it may pause while the phone sleeps and restarts with the
  /// app, so [uptimeMs] is preferred when there is one.
  Duration running() => _running.elapsed;

  /// Milliseconds since the phone booted: keeps counting through sleep and
  /// across app restarts, and can't be changed. Null where it isn't available
  /// (iOS, for now).
  Future<int?> uptimeMs() async {
    try {
      return await _channel.invokeMethod<int>('elapsedRealtime');
    } catch (_) {
      return null;
    }
  }
}

/// The server's time, as last heard from the server and counted forward on
/// the device.
///
/// It counts from [ClockSource.uptimeMs], never from the phone's clock, so
/// changing that clock can't move it. The phone's clock is only used when the
/// phone has restarted or has no uptime, and then it can only move time
/// forward. Only a new answer from the server ([correct]) moves it back.
class ServerClock {
  final ClockSource _source;
  DateTime _server;
  DateTime _phone;
  int? _uptime;
  Duration _running;

  ServerClock._(this._source, this._server, this._phone, this._uptime)
      : _running = _source.running();

  /// [serverNow] is the time in a server response just received.
  static Future<ServerClock> start(
    DateTime serverNow, {
    ClockSource source = const ClockSource(),
  }) async {
    return ServerClock._(
      source,
      serverNow.toUtc(),
      source.phoneNow(),
      await source.uptimeMs(),
    );
  }

  /// Rebuilds a saved clock, or null when [json] is unusable. Call [sync]
  /// before reading it, to count the time since it was saved.
  static ServerClock? fromJson(
    Map<String, dynamic> json, {
    ClockSource source = const ClockSource(),
  }) {
    final server = DateTime.tryParse(json['server']?.toString() ?? '');
    final phone = DateTime.tryParse(json['phone']?.toString() ?? '');
    if (server == null || phone == null) return null;
    final uptime = json['uptime'];
    return ServerClock._(
      source,
      server.toUtc(),
      phone.toUtc(),
      uptime is num ? uptime.toInt() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'server': _server.toIso8601String(),
        'phone': _phone.toIso8601String(),
        'uptime': ?_uptime,
      };

  /// The server's time now. Reliable to the last [sync]; between syncs it
  /// runs on [ClockSource.running].
  DateTime get now => _server.add(_source.running() - _running);

  /// Counts the time since the last sync. It never moves [now] back.
  Future<void> sync() async {
    final uptime = await _source.uptimeMs();
    final phone = _source.phoneNow();
    final running = _source.running();

    var passed = running - _running;
    final last = _uptime;
    if (uptime != null && last != null && uptime >= last) {
      passed = _longer(passed, Duration(milliseconds: uptime - last));
    } else {
      // Restarted, or no uptime here: all that's left is the phone's clock.
      passed = _longer(passed, phone.difference(_phone));
    }
    _server = _server.add(passed);
    _phone = phone;
    _uptime = uptime;
    _running = running;
  }

  /// A server response says it is [serverNow].
  Future<void> correct(DateTime serverNow) async {
    _uptime = await _source.uptimeMs();
    _server = serverNow.toUtc();
    _phone = _source.phoneNow();
    _running = _source.running();
  }

  static Duration _longer(Duration a, Duration b) => Duration(
      microseconds: math.max(a.inMicroseconds, b.inMicroseconds));
}
