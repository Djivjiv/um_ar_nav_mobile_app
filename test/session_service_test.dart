import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:um_ar_mobile_app/core/config/app_config.dart';
import 'package:um_ar_mobile_app/core/utils/session_service.dart';

const userId = '11111111-1111-4111-8111-111111111111';

/// `user_profiles` behind a real local HTTP server, so the real Supabase
/// client runs. No binding here: the test binding would block real HTTP.
class FakeProfiles {
  late HttpServer _server;

  /// `session_start` of the one row; null when it has none.
  String? sessionStart;
  bool hasRow = true;
  final List<Map<String, dynamic>> updates = [];

  Future<SupabaseClient> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_answer);
    return client(_server.port);
  }

  static SupabaseClient client(int port) =>
      SupabaseClient('http://127.0.0.1:$port', 'test-key');

  Future<void> _answer(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final res = request.response;
    if (request.method == 'PATCH') {
      updates.add(jsonDecode(body) as Map<String, dynamic>);
      final patch = updates.last;
      if (patch.containsKey('session_start')) {
        sessionStart = patch['session_start'] as String?;
      }
      res.statusCode = HttpStatus.noContent;
    } else {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode([
        if (hasRow) {'session_start': sessionStart},
      ]));
    }
    await res.close();
  }

  Future<void> stop() => _server.close(force: true);
}

String hoursAgo(num hours) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: (hours * 60).round()))
    .toIso8601String();

void main() {
  late FakeProfiles server;

  Future<String?> deviceCopy() async => (await SharedPreferences.getInstance())
      .getString(SessionService.loginTimeKey);

  /// Pretends the server can't be reached: nothing listens on this port.
  Future<void> goOffline() async {
    final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = free.port;
    await free.close();
    SessionService.testClient = FakeProfiles.client(port);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = FakeProfiles();
    SessionService.testClient = await server.start();
  });

  tearDown(() async {
    SessionService.testClient = null;
    await server.stop();
  });

  group('saveUserSessionStart', () {
    test('writes the same UTC time to the phone and the server', () async {
      await SessionService.saveUserSessionStart(userId);

      final saved = await deviceCopy();
      expect(saved, endsWith('Z'));
      expect(server.updates.single['session_start'], saved);
      expect(server.updates.single['last_seen'], saved);
    });

    test('offline: the phone still keeps it', () async {
      await goOffline();

      await SessionService.saveUserSessionStart(userId);

      expect(await deviceCopy(), isNotNull);
      expect(await SessionService.isUserSessionValid(userId), isTrue);
    });
  });

  group('the ${AppConfig.userSessionHours} hour window', () {
    test('a session just inside it is valid', () async {
      server.sessionStart = hoursAgo(AppConfig.userSessionHours - 0.5);

      expect(await SessionService.isUserSessionValid(userId), isTrue);
      expect(server.updates, isEmpty);
    });

    test('at the limit it has expired, and both copies are cleared',
        () async {
      server.sessionStart = hoursAgo(AppConfig.userSessionHours);
      SharedPreferences.setMockInitialValues(
          {SessionService.loginTimeKey: hoursAgo(1)});

      expect(await SessionService.isUserSessionValid(userId), isFalse);

      expect(server.updates.single, {'session_start': null});
      expect(await deviceCopy(), isNull);
    });

    test('no time anywhere is not a session', () async {
      server.sessionStart = null;

      expect(await SessionService.isUserSessionValid(userId), isFalse);
    });

    test('no profile row is not a session', () async {
      server.hasRow = false;

      expect(await SessionService.isUserSessionValid(userId), isFalse);
    });
  });

  group('which copy counts', () {
    test('the server copy beats the phone copy', () async {
      server.sessionStart = hoursAgo(AppConfig.userSessionHours + 1);
      SharedPreferences.setMockInitialValues(
          {SessionService.loginTimeKey: hoursAgo(1)});

      expect(await SessionService.isUserSessionValid(userId), isFalse);
    });

    test('a server row with no time falls back to the phone', () async {
      server.sessionStart = null;
      SharedPreferences.setMockInitialValues(
          {SessionService.loginTimeKey: hoursAgo(1)});

      expect(await SessionService.isUserSessionValid(userId), isTrue);
    });

    test('offline: the phone copy keeps the user signed in', () async {
      SharedPreferences.setMockInitialValues(
          {SessionService.loginTimeKey: hoursAgo(1)});
      await goOffline();

      expect(await SessionService.isUserSessionValid(userId), isTrue);
    });

    test('offline: the same deadline still applies', () async {
      SharedPreferences.setMockInitialValues({
        SessionService.loginTimeKey:
            hoursAgo(AppConfig.userSessionHours + 1),
      });
      await goOffline();

      expect(await SessionService.isUserSessionValid(userId), isFalse);
      expect(await deviceCopy(), isNull);
    });

    test('a phone copy that cannot be read is not a session', () async {
      SharedPreferences.setMockInitialValues(
          {SessionService.loginTimeKey: 'not a time'});
      await goOffline();

      expect(await SessionService.isUserSessionValid(userId), isFalse);
    });
  });

  group('getUserRemainingHours', () {
    test('counts down whole hours', () async {
      server.sessionStart = hoursAgo(2.5);

      expect(await SessionService.getUserRemainingHours(userId),
          AppConfig.userSessionHours - 2);
    });

    test('is 0 once expired, never negative', () async {
      server.sessionStart = hoursAgo(AppConfig.userSessionHours + 3);

      expect(await SessionService.getUserRemainingHours(userId), 0);
    });

    test('is 0 with no session', () async {
      expect(await SessionService.getUserRemainingHours(userId), 0);
    });
  });
}
