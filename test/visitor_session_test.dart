import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:um_ar_mobile_app/core/constants/visitor_text.dart';
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/core/utils/device_utils.dart';
import 'package:um_ar_mobile_app/core/utils/server_clock.dart';
import 'package:um_ar_mobile_app/data/local/offline_cache.dart';
import 'package:um_ar_mobile_app/data/local/pending_write_queue.dart';
import 'package:um_ar_mobile_app/data/models/user_profile_model.dart';
import 'package:um_ar_mobile_app/data/models/visitor_session_model.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/visitor_session_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/navigation_session_logger.dart';
import 'package:um_ar_mobile_app/presentation/routes/app_router.dart';
import 'package:um_ar_mobile_app/presentation/screens/auth/visitor_ended_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/auth/visitor_screen.dart';
import 'package:um_ar_mobile_app/presentation/screens/profile/profile_screen.dart';

import 'support/visitor_fakes.dart';

const twoHours = Duration(hours: 2);

/// The server is an hour ahead of the phone, so the phone's clock is plainly
/// not what these sessions run on.
final serverStart = DateTime.utc(2026, 11, 1, 9);

class FakeLogRepo implements OutdoorNavigationRepository {
  final rows = <Map<String, dynamic>>[];

  @override
  Future<void> logNavigationRow(Map<String, dynamic> row) async =>
      rows.add(row);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeClockSource phone;
  late FakeVisitorServer server;
  late VisitorSessionRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DeviceUtils.resetDeviceCode();
    phone = FakeClockSource();
    server = FakeVisitorServer(serverStart);
    repo = visitorRepo(server, phone);
  });

  group('server expiry versus the phone clock', () {
    test('the session runs on the server time in the response', () async {
      final s = (await repo.start())!;
      expect(s.expiresAt, serverStart.add(twoHours));
      expect(s.remaining, twoHours); // not 3 hours, from the slower phone
    });

    test('calling start again never lengthens a session', () async {
      final first = (await repo.start())!;
      phone.pass(const Duration(minutes: 30));
      server.now = server.now.add(const Duration(minutes: 30));

      final second = (await repo.start())!;
      expect(second.id, first.id);
      expect(second.expiresAt, first.expiresAt);
      expect(second.remaining, const Duration(minutes: 90));
    });

    test('online, the server has the last word over a changed clock',
        () async {
      final s = (await repo.start())!;
      phone.pass(const Duration(minutes: 10));
      server.now = server.now.add(const Duration(minutes: 10));
      phone.phone = phone.phone.subtract(const Duration(days: 30));

      final checked = await repo.refresh(s, force: true);
      expect(checked.remaining, const Duration(minutes: 110));
    });

    test('offline, it keeps counting from the last known server time',
        () async {
      final s = (await repo.start())!;
      server.offline = true;
      phone.pass(const Duration(minutes: 45));

      final checked = await repo.refresh(s);
      expect(checked.remaining, const Duration(minutes: 75));
      expect(checked.isStillValid, isTrue);
    });

    test('offline, setting the phone back does not extend it', () async {
      final s = (await repo.start())!;
      server.offline = true;
      phone.pass(const Duration(hours: 1));
      phone.phone = phone.phone.subtract(const Duration(days: 365));
      phone.pass(const Duration(minutes: 30));

      final checked = await repo.refresh(s);
      expect(checked.remaining, const Duration(minutes: 30));
    });

    test('offline, it ends on time whatever the phone clock says', () async {
      final s = (await repo.start())!;
      server.offline = true;
      phone.phone = phone.phone.subtract(const Duration(hours: 5));
      phone.pass(twoHours);

      expect((await repo.refresh(s)).isStillValid, isFalse);
    });

    test('closing the app and setting the clock back does not extend it',
        () async {
      await repo.start();
      server.offline = true;
      phone.pass(const Duration(minutes: 30));
      phone.phone = phone.phone.subtract(const Duration(days: 2));
      phone.passWhileClosed(const Duration(minutes: 60));
      phone.restartApp();

      final restored = (await visitorRepo(server, phone).restore())!;
      expect(restored.remaining, const Duration(minutes: 30));
    });

    test('a phone restart with the clock set back does not extend it',
        () async {
      final s = (await repo.start())!;
      server.offline = true;
      phone.pass(const Duration(minutes: 50));
      await repo.refresh(s); // last saved time
      phone.phone = phone.phone.subtract(const Duration(days: 2));
      phone.restartPhone();

      final restored = (await visitorRepo(server, phone).restore())!;
      expect(restored.remaining, const Duration(minutes: 70));
    });

    test('with no uptime (iOS), the clock still only moves forward', () async {
      phone.uptime = null;
      final s = (await repo.start())!;
      server.offline = true;
      phone.pass(const Duration(minutes: 40));
      phone.phone = phone.phone.subtract(const Duration(days: 1));

      expect((await repo.refresh(s)).remaining, const Duration(minutes: 80));
    });

    test('without a connection it starts on the device and is timed the same',
        () async {
      server.offline = true;
      final s = (await repo.start())!;
      expect(s.id, startsWith(VisitorSessionRepository.localPrefix));
      expect(s.remaining, twoHours);

      phone.pass(const Duration(hours: 1));
      phone.phone = phone.phone.subtract(const Duration(days: 1));
      expect((await repo.refresh(s)).remaining, const Duration(hours: 1));
    });

    test('a server error starts nothing', () async {
      server.rejecting = true;
      expect(await repo.start(), isNull);
    });

    test('the server can end a session early', () async {
      final s = (await repo.start())!;
      server.rows[s.id]!['is_expired'] = true;
      expect((await repo.refresh(s, force: true)).isStillValid, isFalse);
    });

    test('a session the server no longer has is over', () async {
      final s = (await repo.start())!;
      server.rows.clear();
      expect((await repo.refresh(s, force: true)).isStillValid, isFalse);
    });

    test('the server is asked about once a minute, not on every check',
        () async {
      final s = (await repo.start())!;
      await repo.refresh(s);
      phone.pass(const Duration(seconds: 5));
      await repo.refresh(s);
      phone.pass(VisitorSessionRepository.serverCheckEvery);
      await repo.refresh(s);
      expect(
        server.calls.where((c) => c.$1 == 'visitor_session_status').length,
        2,
      );
    });

    test('a saved clock survives being stored', () async {
      final clock = await ServerClock.start(serverStart, source: phone);
      final back = ServerClock.fromJson(clock.toJson(), source: phone)!;
      await back.sync();
      expect(back.now, serverStart);
    });
  });

  group('automatic sign-out', () {
    late SeededAuthCubit cubit;

    setUp(() async {
      cubit = SeededAuthCubit(visitors: repo);
      await cubit.continueAsVisitor();
    });

    test('at expiry the visitor is signed out and nothing is left', () async {
      expect(cubit.state, isA<AuthVisitor>());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(VisitorSessionRepository.storageKey), isNotNull);

      phone.pass(twoHours);
      server.now = server.now.add(twoHours);
      await cubit.checkVisitorSession();

      expect(cubit.state, isA<AuthVisitorEnded>());
      expect(prefs.getString(VisitorSessionRepository.storageKey), isNull);
      expect(await repo.restore(), isNull);
    });

    test('a slow check cannot save the session again after it ended',
        () async {
      final release = Completer<void>();
      final slow = SeededAuthCubit(
        visitors: VisitorSessionRepository(
          rpc: (function, params) async {
            if (function == 'visitor_session_status') await release.future;
            return server.rpc(function, params);
          },
          source: phone,
          deviceCode: () async => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        ),
      );
      await slow.continueAsVisitor();
      phone.pass(twoHours);
      server.now = server.now.add(twoHours);

      final first = slow.checkVisitorSession(); // waits on the server
      await slow.checkVisitorSession(); // the watcher's next tick
      release.complete();
      await first;

      expect(slow.state, isA<AuthVisitorEnded>());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(VisitorSessionRepository.storageKey), isNull);
    });

    test('before expiry nothing changes', () async {
      final before = cubit.state;
      phone.pass(const Duration(hours: 1));
      await cubit.checkVisitorSession();
      expect(cubit.state, same(before));
    });

    test('it also ends with no connection', () async {
      server.offline = true;
      phone.pass(twoHours);
      await cubit.checkVisitorSession();
      expect(cubit.state, isA<AuthVisitorEnded>());
    });

    test('a session that ran out while closed ends on launch', () async {
      phone.passWhileClosed(const Duration(hours: 3));
      server.now = server.now.add(const Duration(hours: 3));
      phone.restartApp();

      final fresh = SeededAuthCubit(visitors: visitorRepo(server, phone));
      expect(await fresh.restoreVisitorSession(), isFalse);
      expect(fresh.state, isA<AuthVisitorEnded>());
      expect(await repo.restore(), isNull);
    });

    test('a running session is restored on launch', () async {
      phone.passWhileClosed(const Duration(minutes: 20));
      server.now = server.now.add(const Duration(minutes: 20));
      phone.restartApp();

      final fresh = SeededAuthCubit(visitors: visitorRepo(server, phone));
      expect(await fresh.restoreVisitorSession(), isTrue);
      final s = (fresh.state as AuthVisitor).session;
      expect(s.remaining, const Duration(minutes: 100));
    });

    test('nothing saved: nothing to restore, and no "ended" screen', () async {
      await repo.clear();
      final fresh = SeededAuthCubit(visitors: visitorRepo(server, phone));
      expect(await fresh.restoreVisitorSession(), isFalse);
      expect(fresh.state, isA<AuthInitial>());
    });

    test('a signed-in user is never checked', () async {
      final user = SeededAuthCubit(
        visitors: repo,
        state: const AuthAuthenticated(UserProfileModel(id: 'u1')),
      );
      phone.pass(const Duration(days: 1));
      await user.checkVisitorSession();
      expect(user.state, isA<AuthAuthenticated>());
    });
  });

  group('new session', () {
    test('a new server session with the same device_code', () async {
      final cubit = SeededAuthCubit(visitors: repo);
      await cubit.continueAsVisitor();
      final first = (cubit.state as AuthVisitor).session;

      phone.pass(twoHours);
      server.now = server.now.add(twoHours);
      await cubit.checkVisitorSession();
      phone.pass(const Duration(minutes: 5));
      server.now = server.now.add(const Duration(minutes: 5));
      await cubit.continueAsVisitor();

      final second = (cubit.state as AuthVisitor).session;
      expect(second.id, isNot(first.id));
      expect(second.deviceCode, first.deviceCode);
      expect(second.remaining, twoHours);
      expect(server.startCalls, 2);
    });

    test('an expired saved session is not carried on', () async {
      final first = (await repo.start())!;
      phone.pass(twoHours);
      server.now = server.now.add(twoHours);

      final second = (await repo.start())!;
      expect(second.id, isNot(first.id));
      expect(second.isStillValid, isTrue);
    });
  });

  group('routing', () {
    VisitorSessionModel session(Duration left) => VisitorSessionModel(
          id: 's',
          deviceCode: 'c',
          startedAt: serverStart,
          expiresAt: serverStart.add(left),
          clock: _frozenClock(phone),
        );

    test('an ended session reaches only the ended screen', () {
      const ended = AuthVisitorEnded();
      for (final loc in ['/map', '/ar', '/login', '/visitor', '/survey']) {
        expect(AppRouter.visitorEndedRedirect(ended, loc), '/visitor-ended');
      }
      expect(AppRouter.visitorEndedRedirect(ended, '/visitor-ended'), isNull);
    });

    test('so does one whose time ran out before the next check', () {
      final state = AuthVisitor(session(Duration.zero));
      expect(AppRouter.visitorEndedRedirect(state, '/map'), '/visitor-ended');
    });

    test('a running session and everyone else are left alone', () {
      expect(
        AppRouter.visitorEndedRedirect(AuthVisitor(session(twoHours)), '/map'),
        isNull,
      );
      expect(
        AppRouter.visitorEndedRedirect(const AuthUnauthenticated(), '/map'),
        isNull,
      );
    });

    test('the floor plan viewer is closed to visitors only', () {
      final visitor = AuthVisitor(session(twoHours));
      const user = AuthAuthenticated(UserProfileModel(id: 'u1'));
      expect(
        AppRouter.indoorMapRedirect(visitor, '/floor-plan/10'),
        '/map',
      );
      expect(AppRouter.indoorMapRedirect(visitor, '/map'), isNull);
      expect(AppRouter.indoorMapRedirect(user, '/floor-plan/10'), isNull);
    });

    test('the rule is an allow-list', () {
      expect(canSeeIndoorMap(const AuthAuthenticated(UserProfileModel(id: 'u'))),
          isTrue);
      for (final state in <AuthState>[
        AuthVisitor(session(twoHours)),
        const AuthVisitorEnded(),
        const AuthUnauthenticated(),
        const AuthLoading(),
      ]) {
        expect(canSeeIndoorMap(state), isFalse);
      }
    });
  });

  group('screens', () {
    GoRouter testRouter(SeededAuthCubit cubit, String start) => GoRouter(
          initialLocation: start,
          routes: [
            GoRoute(path: '/map', builder: (_, _) => const Text('THE MAP')),
            GoRoute(path: '/login', builder: (_, _) => const Text('THE LOGIN')),
            GoRoute(path: '/visitor', builder: (_, _) => const VisitorScreen()),
            GoRoute(
              path: '/visitor-ended',
              builder: (_, _) => const VisitorEndedScreen(),
            ),
          ],
        );

    Future<void> pumpAt(
        WidgetTester tester, SeededAuthCubit cubit, String start) async {
      await tester.pumpWidget(BlocProvider<AuthCubit>.value(
        value: cubit,
        child: MaterialApp.router(routerConfig: testRouter(cubit, start)),
      ));
      await tester.pump();
    }

    Future<void> tearDownScreen(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('the ended screen: start a new session', (tester) async {
      final cubit = SeededAuthCubit(
          visitors: repo, state: const AuthVisitorEnded());
      await pumpAt(tester, cubit, '/visitor-ended');
      expect(find.text('Your visitor session ended'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Start a new session'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(cubit.state, isA<AuthVisitor>());
      expect(find.text('THE MAP'), findsOneWidget);
    });

    testWidgets('the ended screen: log in leaves no ended state',
        (tester) async {
      final cubit = SeededAuthCubit(
          visitors: repo, state: const AuthVisitorEnded());
      await pumpAt(tester, cubit, '/visitor-ended');

      await tester.tap(find.text('Log in with your UM account'));
      await tester.pumpAndSettle();

      expect(cubit.state, isA<AuthUnauthenticated>());
      expect(find.text('THE LOGIN'), findsOneWidget);
    });

    testWidgets('Continue as Visitor after an ended session never shows '
        '00:00:00', (tester) async {
      // The state the login screen is left in: signed out, nothing saved.
      final cubit = SeededAuthCubit(
          visitors: repo, state: const AuthUnauthenticated());
      await pumpAt(tester, cubit, '/visitor');
      expect(find.text('00:00:00'), findsNothing);

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(cubit.state, isA<AuthVisitor>());
      expect(find.text('02:00:00'), findsOneWidget);
      expect(find.text('00:00:00'), findsNothing);
      await tearDownScreen(tester);
    });

    testWidgets('an expired session left in the state starts afresh',
        (tester) async {
      final old = (await tester.runAsync(repo.start))!;
      phone.pass(twoHours);
      server.now = server.now.add(twoHours);
      final cubit =
          SeededAuthCubit(visitors: repo, state: AuthVisitor(old));

      await pumpAt(tester, cubit, '/visitor');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.text('00:00:00'), findsNothing);
      expect(find.text('02:00:00'), findsOneWidget);
      await tearDownScreen(tester);
    });

    testWidgets('running out on the visitor screen never shows 00:00:00',
        (tester) async {
      final cubit = SeededAuthCubit(visitors: repo);
      await tester.runAsync(cubit.continueAsVisitor);
      await pumpAt(tester, cubit, '/visitor');

      phone.pass(twoHours);
      server.now = server.now.add(twoHours);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:00:00'), findsNothing);

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(cubit.state, isA<AuthVisitorEnded>());
      await tearDownScreen(tester);
    });

    testWidgets('a failed start offers a retry, not a countdown',
        (tester) async {
      server.rejecting = true;
      final cubit = SeededAuthCubit(
          visitors: repo, state: const AuthUnauthenticated());
      await pumpAt(tester, cubit, '/visitor');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(cubit.state, isA<AuthError>());
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('00:00:00'), findsNothing);
      await tearDownScreen(tester);
    });

    testWidgets('visitor and profile screens say the same true thing',
        (tester) async {
      final session = (await tester.runAsync(repo.start))!;
      final cubit =
          SeededAuthCubit(visitors: repo, state: AuthVisitor(session));

      await pumpAt(tester, cubit, '/visitor');
      expect(find.text(VisitorText.access), findsOneWidget);
      await tearDownScreen(tester);

      await tester.pumpWidget(BlocProvider<AuthCubit>.value(
        value: cubit,
        child: const MaterialApp(home: ProfileScreen()),
      ));
      await tester.pump();
      expect(find.text(VisitorText.access), findsOneWidget);
      expect(find.textContaining('Full campus navigation'), findsNothing);
      await tearDownScreen(tester);

      expect(VisitorText.access, contains('no 2D indoor map'));
      expect(VisitorText.access, contains('2 hours'));
    });
  });

  group('tagging', () {
    Future<List<Map<String, dynamic>>> logTrip(
        WidgetTester tester, VisitorSessionModel session) async {
      final log = FakeLogRepo();
      final cubit = SeededAuthCubit(state: AuthVisitor(session));
      late BuildContext ctx;
      await tester.pumpWidget(RepositoryProvider<OutdoorNavigationRepository>.value(
        value: log,
        child: BlocProvider<AuthCubit>.value(
          value: cubit,
          child: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
        ),
      ));
      final logger = NavigationSessionLogger.of(
        ctx,
        mode: TripMode.ar,
        fromNode: 'a',
        toNode: 'b',
        fromName: 'A',
        toName: 'B',
      );
      await tester.runAsync(() async {
        await logger.start();
        await logger.complete();
      });
      return log.rows;
    }

    testWidgets('every trip row has the session\'s device_code and no user',
        (tester) async {
      final realRepo = VisitorSessionRepository(rpc: server.rpc, source: phone);
      final session = (await tester.runAsync(realRepo.start))!;
      final code = await tester.runAsync(DeviceUtils.getDeviceCode);

      final rows = await logTrip(tester, session);

      expect(session.deviceCode, code);
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(row['device_code'], code);
        expect(row['visitor_session_id'], session.id);
        expect(row['user_id'], isNull); // is_visitor in the database
      }
    });

    testWidgets('a device-only session is tagged by device_code alone',
        (tester) async {
      server.offline = true;
      final realRepo = VisitorSessionRepository(rpc: server.rpc, source: phone);
      final session = (await tester.runAsync(realRepo.start))!;
      final code = await tester.runAsync(DeviceUtils.getDeviceCode);

      final rows = await logTrip(tester, session);

      for (final row in rows) {
        expect(row['device_code'], code);
        expect(row['visitor_session_id'], isNull);
        expect(row['user_id'], isNull);
      }
    });

    test('SUS rows carry the same device_code, and no user', () async {
      final realRepo = VisitorSessionRepository(rpc: server.rpc, source: phone);
      final session = (await realRepo.start())!;

      final sent = <(String, Map<String, dynamic>)>[];
      final connectivity = ConnectivityService(probe: () async => true);
      await SurveyRepository(
        SupabaseClient('http://127.0.0.1:9', 'test-key'),
        OfflineCache(connectivity: connectivity),
        PendingWriteQueue(
          sender: (t, p) async => sent.add((t, p)),
          connectivity: connectivity,
        ),
      ).submitResponse(
        visitorSessionId: session.id,
        answers: List.filled(10, 3),
        susScore: 50,
        userType: 'visitor',
      );

      final row = sent.single.$2;
      expect(row['device_code'], session.deviceCode);
      expect(row['visitor_session_id'], session.id);
      expect(row['user_type'], 'visitor');
      expect(row['user_id'], isNull);
    });

    test('sessions start with device_code, never device_id', () async {
      await repo.start();
      final params = server.calls.first.$2;
      expect(params.keys, ['p_device_code']);
      expect(params['p_device_code'], isNotEmpty);
    });

    test('the SQL flags visitors and sets every time on the server', () {
      final sql = File('supabase/visitor_sessions.sql').readAsStringSync();
      expect(sql, contains("now() + interval '2 hours'"));
      expect(
        'generated always as (user_id is null)'.allMatches(sql),
        hasLength(2),
      );
      expect(sql, contains('revoke all on public.visitor_sessions'));
      expect(sql, contains('grant select on public.visitor_sessions'));
      expect(RegExp(r'^create policy.*\n.*\n\s*for (insert|update|delete)',
              multiLine: true)
          .hasMatch(sql), isFalse);
    });
  });
}

ServerClock _frozenClock(FakeClockSource phone) => ServerClock.fromJson({
      'server': serverStart.toIso8601String(),
      'phone': phone.phone.toIso8601String(),
    }, source: phone)!;
