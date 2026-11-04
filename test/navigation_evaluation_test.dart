import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/core/utils/device_utils.dart';
import 'package:um_ar_mobile_app/core/utils/navigation_phase_manager.dart';
import 'package:um_ar_mobile_app/core/utils/uuid.dart';
import 'package:um_ar_mobile_app/data/local/offline_cache.dart';
import 'package:um_ar_mobile_app/data/local/pending_write_queue.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';
import 'package:um_ar_mobile_app/domain/services/off_route_tracker.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/navigation_session_logger.dart';
import 'package:um_ar_mobile_app/presentation/screens/navigation/multi_phase_nav_screen.dart';

/// Collects the rows a screen logs.
class RowRecorder implements OutdoorNavigationRepository {
  final rows = <Map<String, dynamic>>[];

  @override
  Future<void> logNavigationRow(Map<String, dynamic> row) async => rows.add(row);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('leaving the 2D screen logs a trip that was not completed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    DeviceUtils.resetDeviceCode();
    final repo = RowRecorder();
    await tester.pumpWidget(RepositoryProvider<OutdoorNavigationRepository>.value(
      value: repo,
      child: MaterialApp(
        home: MultiPhaseNavScreen(
          navigationRoute: NavigationRoute(
            from: const {'type': 'building', 'id': '2', 'name': 'Gym'},
            to: const {'type': 'building', 'id': '3', 'name': 'Library'},
            phases: const [
              NavigationPhase.outdoorNavigation,
              NavigationPhase.arrived,
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(repo.rows.map((r) => r['row_type']), ['start', 'end']);
    final end = repo.rows.last;
    expect(end['mode'], '2d');
    expect(end['completed'], isFalse);
    expect(end['trip_id'], repo.rows.first['trip_id']);
    expect(end['duration_seconds'], isA<int>());
    expect(isUuid(end['device_code']), isTrue);
    expect(repo.rows.first['device_code'], end['device_code']);
  });

  group('OffRouteTracker — counting deviations', () {
    test('jitter around the limit is ONE deviation (hysteresis)', () {
      final t = OffRouteTracker(enterMeters: 25, exitMeters: 20);
      // Leaves the route, wobbles between 21 and 30 m, comes back.
      final starts = [5, 26, 22, 30, 21, 27, 10]
          .map((d) => t.update(d.toDouble()))
          .toList();
      expect(starts.where((s) => s), hasLength(1));
      expect(t.events, 1);
      expect(t.offRoute, isFalse);
    });

    test('separate deviations each count', () {
      final t = OffRouteTracker(enterMeters: 25, exitMeters: 20);
      for (final d in [5, 30, 5, 30, 5, 40, 3]) {
        t.update(d.toDouble());
      }
      expect(t.events, 3);
    });

    test('a poor GPS fix is ignored, not counted as an error', () {
      final t = OffRouteTracker(maxAccuracyMeters: 30);
      expect(t.update(80, accuracyMeters: 65), isFalse);
      expect(t.events, 0);
      expect(t.tracked, isFalse, reason: 'nothing usable was measured');
      t.update(3, accuracyMeters: 8);
      expect(t.tracked, isTrue);
    });

    test('reset after a re-route keeps the count', () {
      final t = OffRouteTracker(enterMeters: 25, exitMeters: 20);
      t.update(40);
      t.reset(); // new route from here
      expect(t.offRoute, isFalse);
      t.update(40); // off the NEW route — a second deviation
      expect(t.events, 2);
    });
  });

  group('NavigationSessionLogger rows', () {
    late List<Map<String, dynamic>> rows;
    late DateTime now;

    NavigationSessionLogger logger({
      String mode = TripMode.ar,
      Future<String> Function()? deviceCode,
    }) =>
        NavigationSessionLogger(
          sink: (r) async => rows.add(r),
          now: () => now,
          deviceCode: deviceCode,
          mode: mode,
          fromNode: 'n1',
          toNode: 'n9',
          fromName: 'Gate',
          toName: 'Library',
          distanceMeters: 320,
          totalSteps: 8,
          userId: 'u1',
        );

    setUp(() {
      rows = [];
      now = DateTime(2026, 10, 30, 9);
      NavigationSessionLogger.lastCompletedTripId = null;
    });

    test('start + end rows share the trip id and carry the counts', () async {
      final l = logger();
      await l.start();
      l.recordOffRoute();
      l.recordReroute();
      l.recordOffRoute();
      now = now.add(const Duration(minutes: 4, seconds: 10));
      await l.complete();

      expect(rows, hasLength(2));
      final start = rows[0], end = rows[1];
      expect(isUuid(l.tripId), isTrue);
      expect(start['trip_id'], l.tripId);
      expect(end['trip_id'], l.tripId);
      expect(start['row_type'], 'start');
      expect(start['completed'], isFalse);
      expect(start.containsKey('error_count'), isFalse);

      expect(end['row_type'], 'end');
      expect(end['mode'], 'ar');
      expect(end['completed'], isTrue);
      expect(end['completed_manually'], isFalse);
      expect(end['error_count'], 3, reason: 'two off-route + one reroute');
      expect(end['reroute_count'], 1);
      expect(end['total_steps'], 8);
      expect(end['off_route_tracked'], isTrue);
      expect(end['duration_seconds'], 250);
      expect(end['started_at'], start['started_at']);
      expect(end['completed_at'], isNotNull);
      expect(NavigationSessionLogger.lastCompletedTripId, l.tripId);
    });

    test('the rows carry the columns the evaluation needs', () async {
      final l = logger(deviceCode: () async => 'code-1');
      await l.start();
      await l.complete();

      expect(rows.first.keys, containsAll(
          ['trip_id', 'row_type', 'mode', 'total_steps', 'completed',
           'device_code']));
      expect(rows.last.keys, containsAll(
          ['trip_id', 'row_type', 'mode', 'off_route_tracked', 'error_count',
           'total_steps', 'completed', 'duration_seconds', 'device_code']));
    });

    test('every off-route event and every reroute is one error', () async {
      final l = logger();
      await l.start();
      l.recordOffRoute();
      expect(l.errorCount, 1);
      l.recordReroute();
      expect(l.errorCount, 2);
      l.recordReroute();
      expect(l.errorCount, 3);
      await l.complete();
      expect(rows.last['error_count'], 3);
      expect(rows.last['reroute_count'], 2);
      // Off-route events alone stay available from the two columns.
      expect(rows.last['error_count'] - rows.last['reroute_count'], 1);
    });

    test('a reroute after the trip ended is not counted', () async {
      final l = logger();
      await l.start();
      await l.complete();
      l.recordReroute();
      expect(l.errorCount, 0);
      expect(l.rerouteCount, 0);
    });

    test('completed is true only on arrival', () async {
      final l = logger();
      await l.start();
      expect(rows.single['completed'], isFalse);
      l.recordOffRoute();
      l.recordReroute();
      expect(rows.where((r) => r['completed'] == true), isEmpty);
      await l.complete();
      expect(rows.last['completed'], isTrue);
    });

    test('duration runs from start to arrival, not to the screen closing',
        () async {
      final l = logger();
      await l.start();
      now = now.add(const Duration(seconds: 95));
      await l.complete();
      now = now.add(const Duration(minutes: 30));
      await l.abandon();
      expect(rows.where((r) => r['row_type'] == 'end'), hasLength(1));
      expect(rows.last['duration_seconds'], 95);
    });

    test('a cancelled trip is not completed and keeps its duration', () async {
      final l = logger();
      await l.start();
      now = now.add(const Duration(seconds: 40));
      await l.abandon();
      expect(rows.last['completed'], isFalse);
      expect(rows.last['duration_seconds'], 40);
    });

    test('both rows carry the device code', () async {
      final l = logger(deviceCode: () async => 'code-1');
      await l.start();
      await l.complete();
      expect(rows.map((r) => r['device_code']), ['code-1', 'code-1']);
    });

    test('a device code failure never loses the row', () async {
      final l = logger(deviceCode: () async => throw StateError('no storage'));
      await l.start();
      expect(rows, hasLength(1));
      expect(rows.single.containsKey('device_code'), isFalse);
    });

    test('"I have arrived" is stored as completed_manually', () async {
      final l = logger();
      await l.start();
      await l.complete(manual: true);
      expect(rows.last['completed'], isTrue);
      expect(rows.last['completed_manually'], isTrue);
    });

    test('leaving early writes an abandoned end row, once', () async {
      final l = logger(mode: TripMode.twoD);
      await l.start();
      l.recordOffRoute();
      await l.abandon();
      await l.abandon();
      await l.complete(); // too late — already ended
      expect(rows, hasLength(2));
      expect(rows.last['completed'], isFalse);
      expect(rows.last['completed_manually'], isFalse);
      expect(rows.last['error_count'], 1);
      expect(rows.last['mode'], '2d');
      expect(rows.last.containsKey('completed_at'), isFalse);
      expect(NavigationSessionLogger.lastCompletedTripId, isNull);
    });

    test('complete writes one end row; nothing counts after it', () async {
      final l = logger();
      await l.start();
      await l.complete();
      await l.complete();
      await l.abandon();
      l.recordOffRoute();
      expect(rows.where((r) => r['row_type'] == 'end'), hasLength(1));
      expect(l.errorCount, 0);
    });

    test('abandon without start writes nothing', () async {
      await logger().abandon();
      expect(rows, isEmpty);
    });

    test('untracked trips say so (error count not measured)', () async {
      final l = logger();
      await l.start();
      await l.complete();
      expect(rows.last['off_route_tracked'], isFalse);
      expect(rows.last['error_count'], 0);
    });

    test('total steps can grow once indoor legs are known', () async {
      final l = logger()..totalSteps = 5;
      await l.start();
      l.totalSteps = 12;
      await l.complete();
      expect(rows.first['total_steps'], 5);
      expect(rows.last['total_steps'], 12);
    });
  });

  group('device_code', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      DeviceUtils.resetDeviceCode();
    });

    test('is a random UUID, the same for the whole install', () async {
      final code = await DeviceUtils.getDeviceCode();
      expect(isUuid(code), isTrue);
      expect(await DeviceUtils.getDeviceCode(), code);

      DeviceUtils.resetDeviceCode(); // next app run
      expect(await DeviceUtils.getDeviceCode(), code);
    });

    test('calls at the same moment get the same code', () async {
      final codes = await Future.wait(
          [DeviceUtils.getDeviceCode(), DeviceUtils.getDeviceCode()]);
      expect(codes.first, codes.last);
    });

    test('a new install gets a new code', () async {
      final first = await DeviceUtils.getDeviceCode();
      SharedPreferences.setMockInitialValues({});
      DeviceUtils.resetDeviceCode();
      expect(await DeviceUtils.getDeviceCode(), isNot(first));
    });

    test('a stored value that is not a UUID is replaced', () async {
      SharedPreferences.setMockInitialValues(
          {'device_code': 'someone@umindanao.edu.ph'});
      final code = await DeviceUtils.getDeviceCode();
      expect(isUuid(code), isTrue);
    });
  });

  test('error rate = errors / total route steps', () {
    expect(NavigationMetrics.errorRate(3, 12), 0.25);
    expect(NavigationMetrics.errorRate(0, 7), 0);
    expect(NavigationMetrics.errorRate(2, 0), isNull);
  });

  group('survey trip link (read defensively)', () {
    final id = uuidV4();
    setUp(() {
      NavigationSessionLogger.lastCompletedTripId = null;
      DeviceUtils.resetDeviceCode();
    });

    test('route extra: map, bare string, or fallback', () {
      expect(NavigationSessionLogger.tripIdFromRouteExtra(
          {'navigation_session_id': id}), id);
      expect(NavigationSessionLogger.tripIdFromRouteExtra(id), id);
      expect(NavigationSessionLogger.tripIdFromRouteExtra(null), isNull);
      expect(NavigationSessionLogger.tripIdFromRouteExtra(
          {'navigation_session_id': 42}), isNull);
      expect(NavigationSessionLogger.tripIdFromRouteExtra('not-a-uuid'),
          isNull);

      NavigationSessionLogger.lastCompletedTripId = id;
      expect(NavigationSessionLogger.tripIdFromRouteExtra({'x': 1}), id);
    });

    test('submitResponse sends navigation_session_id', () async {
      SharedPreferences.setMockInitialValues({});
      final sent = <(String, Map<String, dynamic>)>[];
      final connectivity = ConnectivityService(probe: () async => true);
      final repo = SurveyRepository(
        SupabaseClient('http://127.0.0.1:9', 'test-key'),
        OfflineCache(connectivity: connectivity),
        PendingWriteQueue(
          sender: (t, p) async => sent.add((t, p)),
          connectivity: connectivity,
        ),
      );
      final ok = await repo.submitResponse(
        answers: List.filled(10, 3),
        susScore: 50,
        userType: 'student',
        navigationSessionId: id,
      );
      expect(ok, isTrue);
      expect(sent.single.$1, 'sus_responses');
      expect(sent.single.$2['navigation_session_id'], id);
      expect(sent.single.$2['device_code'], await DeviceUtils.getDeviceCode());

      sent.clear();
      await repo.submitResponse(
          answers: List.filled(10, 3), susScore: 50, userType: 'student');
      expect(sent.single.$2.containsKey('navigation_session_id'), isFalse);
    });
  });

  group('missing columns are tolerated (SQL not run yet)', () {
    test('unknown columns are dropped and the rest is saved', () async {
      final attempts = <Set<String>>[];
      await PendingWriteQueue.insertDroppingUnknownColumns(
        (row) async {
          attempts.add(row.keys.toSet());
          if (row.containsKey('trip_id')) {
            throw PostgrestException(
                code: 'PGRST204',
                message: "Could not find the 'trip_id' column of "
                    "'navigation_sessions' in the schema cache");
          }
          if (row.containsKey('mode')) {
            throw PostgrestException(
                code: '42703',
                message: 'column "mode" of relation "navigation_sessions" '
                    'does not exist');
          }
        },
        'navigation_sessions',
        {'trip_id': 'x', 'mode': 'ar', 'to_name': 'Library'},
      );
      expect(attempts.last, {'to_name'});
      expect(attempts, hasLength(3));
    });

    test('other server errors are not swallowed', () async {
      await expectLater(
        PendingWriteQueue.insertDroppingUnknownColumns(
          (row) async => throw PostgrestException(
              code: '42501', message: 'violates row-level security policy'),
          'navigation_sessions',
          {'to_name': 'Library'},
        ),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('a missing column that is not in the row is rethrown', () async {
      await expectLater(
        PendingWriteQueue.insertDroppingUnknownColumns(
          (row) async => throw PostgrestException(
              message: "Could not find the 'other' column of 't'"),
          't',
          {'a': 1},
        ),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
