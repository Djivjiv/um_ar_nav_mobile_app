import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/navigation_session_logger.dart';

/// The rules navigation_evaluation_test.dart doesn't already pin down.
void main() {
  late List<Map<String, dynamic>> rows;
  late DateTime now;

  NavigationSessionLogger logger({
    String? userId,
    String? visitorSessionId,
    Future<void> Function(Map<String, dynamic>)? sink,
  }) =>
      NavigationSessionLogger(
        sink: sink ?? (r) async => rows.add(r),
        now: () => now,
        mode: TripMode.ar,
        fromNode: 'n1',
        toNode: 'n9',
        fromName: 'Gate',
        toName: 'Library',
        distanceMeters: 320,
        totalSteps: 8,
        userId: userId,
        visitorSessionId: visitorSessionId,
      );

  setUp(() {
    rows = [];
    now = DateTime.utc(2026, 11, 1, 1, 30);
    NavigationSessionLogger.lastCompletedTripId = null;
  });

  group('start row', () {
    test('is written once, however often start is called', () async {
      final l = logger();
      await l.start();
      await l.start();

      expect(rows, hasLength(1));
    });

    test('names the trip and has no outcome yet', () async {
      await logger(userId: 'u1').start();

      final row = rows.single;
      expect(row['row_type'], 'start');
      expect(row['user_id'], 'u1');
      expect(row['from_node'], 'n1');
      expect(row['to_node'], 'n9');
      expect(row['from_name'], 'Gate');
      expect(row['to_name'], 'Library');
      expect(row['distance_meters'], 320);
      expect(row['started_at'], '2026-11-01T01:30:00.000Z');
      expect(row['completed'], isFalse);
      for (final outcome in [
        'duration_seconds',
        'completed_manually',
        'reroute_count',
        'off_route_tracked',
        'completed_at',
      ]) {
        expect(row.containsKey(outcome), isFalse, reason: outcome);
      }
    });

    test('a visitor trip carries the visitor session, not a user', () async {
      await logger(visitorSessionId: 'v1').start();

      expect(rows.single['visitor_session_id'], 'v1');
      expect(rows.single['user_id'], isNull);
    });

    test('with nowhere to send, nothing breaks', () async {
      final l = NavigationSessionLogger(
          sink: null,
          mode: TripMode.ar,
          fromNode: 'a',
          toNode: 'b',
          fromName: 'A',
          toName: 'B');

      await l.start();
      await l.complete();

      expect(l.ended, isTrue);
    });

    test('a failing send never reaches navigation', () async {
      final l = logger(sink: (_) async => throw StateError('queue is broken'));

      await expectLater(l.start(), completes);
      await expectLater(l.complete(), completes);
    });

    test('a new logger is a new trip', () {
      expect(logger().tripId, isNot(logger().tripId));
    });
  });

  group('end row', () {
    test('keeps the start time and adds the arrival time in UTC', () async {
      final l = logger();
      await l.start();
      now = now.add(const Duration(minutes: 2));
      await l.complete();

      final end = rows.last;
      expect(end['row_type'], 'end');
      expect(end['started_at'], '2026-11-01T01:30:00.000Z');
      expect(end['completed_at'], '2026-11-01T01:32:00.000Z');
      expect(end['duration_seconds'], 120);
    });

    test('a completed trip is remembered for the survey', () async {
      final l = logger();
      await l.start();
      await l.complete();

      expect(NavigationSessionLogger.lastCompletedTripId, l.tripId);
    });

    test('with no trip started, arrival is a zero-length trip', () async {
      await logger().complete();

      expect(rows.single['row_type'], 'end');
      expect(rows.single['duration_seconds'], 0);
    });
  });

  group('cancel', () {
    test('is an end row with no arrival time', () async {
      final l = logger();
      await l.start();
      now = now.add(const Duration(seconds: 30));
      await l.abandon();

      final end = rows.last;
      expect(end['row_type'], 'end');
      expect(end['completed'], isFalse);
      expect(end['duration_seconds'], 30);
      expect(end.containsKey('completed_at'), isFalse);
    });

    test('does not count as the trip the survey belongs to', () async {
      final l = logger();
      await l.start();
      await l.abandon();

      expect(NavigationSessionLogger.lastCompletedTripId, isNull);
    });

    test('a manual arrival flag is never set on it', () async {
      final l = logger();
      await l.start();
      await l.abandon();

      expect(rows.last['completed_manually'], isFalse);
    });

    test('keeps the errors made before cancelling', () async {
      final l = logger();
      await l.start();
      l.recordOffRoute();
      l.recordReroute();
      await l.abandon();

      expect(rows.last['error_count'], 2);
      expect(rows.last['reroute_count'], 1);
    });
  });

  group('error count', () {
    test('an off-route event alone is one error and no reroute', () async {
      final l = logger();
      await l.start();
      l.recordOffRoute();
      await l.complete();

      expect(rows.last['error_count'], 1);
      expect(rows.last['reroute_count'], 0);
      expect(rows.last['off_route_tracked'], isTrue);
    });

    test('a reroute alone is one error and leaves tracking alone', () async {
      final l = logger();
      await l.start();
      l.recordReroute();
      await l.complete();

      expect(rows.last['error_count'], 1);
      expect(rows.last['reroute_count'], 1);
      expect(rows.last['off_route_tracked'], isFalse);
    });

    test('tracking with no deviation is a clean, measured trip', () async {
      final l = logger();
      await l.start();
      l.markOffRouteTracked();
      await l.complete();

      expect(rows.last['error_count'], 0);
      expect(rows.last['off_route_tracked'], isTrue);
    });

    test('nothing is counted after the trip is cancelled', () async {
      final l = logger();
      await l.start();
      await l.abandon();
      l.recordOffRoute();
      l.recordReroute();

      expect(l.errorCount, 0);
      expect(l.rerouteCount, 0);
    });

    test('the error rate uses the count and the planned steps', () async {
      final l = logger();
      await l.start();
      l.recordOffRoute();
      l.recordReroute();
      await l.complete();

      expect(
        NavigationMetrics.errorRate(
            rows.last['error_count'] as int, rows.last['total_steps'] as int),
        0.25,
      );
    });
  });
}
