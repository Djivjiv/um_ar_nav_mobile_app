import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/data/local/pending_write_queue.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/navigation/navigation_session_logger.dart';

import 'support/feedback_fakes.dart';

final isUtcIso = matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+Z$'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('new rows', () {
    final phoneTime = DateTime(2026, 11, 1, 17, 30);

    test('navigation_sessions: started_at and completed_at', () async {
      final rows = <Map<String, dynamic>>[];
      final logger = NavigationSessionLogger(
        sink: (row) async => rows.add(row),
        mode: TripMode.ar,
        fromNode: 'a',
        toNode: 'b',
        fromName: 'A',
        toName: 'B',
        now: () => phoneTime,
      );

      await logger.start();
      await logger.complete();

      for (final row in rows) {
        expect(row['started_at'], isUtcIso);
        expect(DateTime.parse(row['started_at'] as String).toLocal(), phoneTime);
      }
      expect(rows.last['completed_at'], isUtcIso);
      expect(
          DateTime.parse(rows.last['completed_at'] as String).toLocal(), phoneTime);
    });

    test('sus_responses: submitted_at', () async {
      await FeedbackWorld.resetPhone();
      final world = FeedbackWorld();

      await world.submitSus();

      expect(
        world.server.rowsOf(SurveyRepository.table).single['submitted_at'],
        isUtcIso,
      );
    });

    test('nothing in lib sends DateTime.now() without toUtc', () {
      // offline_sync.dart keeps its time on the phone and never sends it.
      final local = RegExp(r'(DateTime\.now\(\)|\bnow|\bstarted)\.toIso8601String');
      final found = [
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              !f.path.endsWith('offline_sync.dart'))
            if (local.hasMatch(f.readAsStringSync())) f.path,
      ];

      expect(found, isEmpty);
    });
  });

  group('queued rows', () {
    late List<Map<String, dynamic>> sent;
    late PendingWriteQueue queue;

    setUp(() {
      sent = [];
      queue = PendingWriteQueue(
        sender: (_, payload) async => sent.add(payload),
        connectivity: ConnectivityService(probe: () async => true),
      );
    });

    Future<void> savedByAnOlderApp(Map<String, dynamic> payload) async {
      SharedPreferences.setMockInitialValues({
        PendingWriteQueue.storageKey: jsonEncode([
          {
            'id': '1',
            'table': 'sus_responses',
            'payload': payload,
            'createdAt': '2026-11-01T09:00:00.000',
            'attempts': 0,
            'keepForever': true,
          }
        ]),
      });
    }

    test('a time with no timezone is the phone\'s local time', () async {
      await savedByAnOlderApp({'submitted_at': '2026-11-01T17:30:00.000'});

      await queue.flush();

      final at = sent.single['submitted_at'] as String;
      expect(at, isUtcIso);
      expect(DateTime.parse(at).toLocal(), DateTime(2026, 11, 1, 17, 30));
    });

    test('every *_at column of a row is converted', () async {
      await savedByAnOlderApp({
        'started_at': '2026-11-01T17:00:00.000',
        'completed_at': '2026-11-01T17:30:00.000',
      });

      await queue.flush();

      expect(sent.single['started_at'], isUtcIso);
      expect(sent.single['completed_at'], isUtcIso);
    });

    test('a time already in UTC goes unchanged', () async {
      await savedByAnOlderApp({'submitted_at': '2026-11-01T09:30:00.000Z'});

      await queue.flush();

      expect(sent.single['submitted_at'], '2026-11-01T09:30:00.000Z');
    });

    test('a time with an offset becomes UTC', () async {
      await savedByAnOlderApp({'submitted_at': '2026-11-01T17:30:00.000+08:00'});

      await queue.flush();

      expect(sent.single['submitted_at'], '2026-11-01T09:30:00.000Z');
    });

    test('everything else in the row is left alone', () async {
      await savedByAnOlderApp({
        'submitted_at': null,
        'looked_at': 'not a time',
        'answered_at': 3,
        'device_code': '2026-11-01T17:30:00.000',
        'q1': 4,
      });

      await queue.flush();

      expect(sent.single, {
        'submitted_at': null,
        'looked_at': 'not a time',
        'answered_at': 3,
        'device_code': '2026-11-01T17:30:00.000',
        'q1': 4,
      });
    });

    test('an old row stays correct across failed sends', () async {
      await savedByAnOlderApp({'submitted_at': '2026-11-01T17:30:00.000'});
      var online = false;
      final retrying = PendingWriteQueue(
        sender: (_, payload) async {
          if (!online) throw const SocketException('no route');
          sent.add(payload);
        },
        connectivity: ConnectivityService(probe: () async => true),
      );

      await retrying.flush();
      expect((await retrying.pending()).single.keepForever, isTrue);

      online = true;
      await retrying.flush();

      expect(sent.single['submitted_at'], isUtcIso);
      expect(DateTime.parse(sent.single['submitted_at'] as String).toLocal(),
          DateTime(2026, 11, 1, 17, 30));
    });

    test('a row queued by this version goes as it was built', () async {
      SharedPreferences.setMockInitialValues({});
      await queue.enqueue(
          'feedback_comments', {'created_at': '2026-11-01T09:30:00.000Z'});

      await queue.flush();

      expect(sent.single['created_at'], '2026-11-01T09:30:00.000Z');
    });
  });
}
