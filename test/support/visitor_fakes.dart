import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:um_ar_mobile_app/core/utils/server_clock.dart';
import 'package:um_ar_mobile_app/data/repositories/auth_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/visitor_session_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';

/// A phone whose clock can be changed by hand, unlike its uptime.
class FakeClockSource extends ClockSource {
  DateTime phone;
  Duration runningFor = Duration.zero;

  /// Null on a phone with no uptime.
  int? uptime;

  FakeClockSource({DateTime? phone, this.uptime = 1000})
      : phone = phone ?? DateTime.utc(2026, 11, 1, 8);

  /// [time] really passes.
  void pass(Duration time) {
    phone = phone.add(time);
    runningFor += time;
    final u = uptime;
    if (u != null) uptime = u + time.inMilliseconds;
  }

  /// The app was closed and [time] really passed.
  void passWhileClosed(Duration time) {
    phone = phone.add(time);
    final u = uptime;
    if (u != null) uptime = u + time.inMilliseconds;
  }

  /// The app starts again: its own running time begins from zero.
  void restartApp() => runningFor = Duration.zero;

  /// The phone restarted: its uptime begins from zero as well.
  void restartPhone() {
    restartApp();
    if (uptime != null) uptime = 1000;
  }

  @override
  DateTime phoneNow() => phone;
  @override
  Duration running() => runningFor;
  @override
  Future<int?> uptimeMs() async => uptime;
}

/// `supabase/visitor_sessions.sql` in miniature, with its own clock.
class FakeVisitorServer {
  DateTime now;
  bool offline = false;
  bool rejecting = false;
  int _nextId = 1;

  final Map<String, Map<String, dynamic>> rows = {};
  final List<(String, Map<String, dynamic>)> calls = [];

  FakeVisitorServer(this.now);

  Map<String, dynamic> _answer(Map<String, dynamic> row) => {
        ...row,
        'is_expired': row['is_expired'] == true ||
            !DateTime.parse(row['expires_at'] as String).isAfter(now),
        'server_now': now.toIso8601String(),
      };

  Future<Object?> rpc(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    if (offline) throw const SocketException('no connection');
    if (rejecting) throw const PostgrestException(message: 'no such function');

    if (function == 'start_visitor_session') {
      final code = params['p_device_code'] as String;
      for (final row in rows.values) {
        if (row['device_code'] == code && _answer(row)['is_expired'] == false) {
          return _answer(row);
        }
      }
      final id = '00000000-0000-4000-8000-${'${_nextId++}'.padLeft(12, '0')}';
      rows[id] = {
        'id': id,
        'device_code': code,
        'started_at': now.toIso8601String(),
        'expires_at': now.add(const Duration(hours: 2)).toIso8601String(),
        'is_expired': false,
      };
      return _answer(rows[id]!);
    }
    final row = rows[params['p_session_id']];
    if (row == null || row['device_code'] != params['p_device_code']) {
      return null;
    }
    return _answer(row);
  }

  int get startCalls =>
      calls.where((c) => c.$1 == 'start_visitor_session').length;
}

VisitorSessionRepository visitorRepo(
  FakeVisitorServer server,
  FakeClockSource source, {
  String deviceCode = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
}) =>
    VisitorSessionRepository(
      rpc: server.rpc,
      source: source,
      deviceCode: () async => deviceCode,
    );

class StubAuthRepository implements AuthRepository {
  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An [AuthCubit] that can be put straight into a state.
class SeededAuthCubit extends AuthCubit {
  SeededAuthCubit({AuthState? state, super.visitors})
      : super(StubAuthRepository()) {
    if (state != null) emit(state);
  }
}
