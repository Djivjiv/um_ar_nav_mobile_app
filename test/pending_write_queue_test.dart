import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/data/local/offline_cache.dart';
import 'package:um_ar_mobile_app/data/local/pending_write_queue.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';

/// A fake server: records inserts, or fails the way the network would.
class FakeServer {
  bool online = true;
  Set<String> rejectTables = {};
  final List<(String, Map<String, dynamic>)> inserted = [];

  Future<void> send(String table, Map<String, dynamic> payload) async {
    if (!online) throw const SocketException('No route to host');
    if (rejectTables.contains(table)) {
      throw PostgrestException(message: 'violates row-level security');
    }
    inserted.add((table, payload));
  }
}

void main() {
  late FakeServer server;
  late ConnectivityService connectivity;

  PendingWriteQueue newQueue() => PendingWriteQueue(
        sender: server.send,
        connectivity: connectivity,
        sendTimeout: const Duration(seconds: 2),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = FakeServer();
    connectivity = ConnectivityService(probe: () async => true);
  });

  test('offline writes stay queued and are sent when the connection returns',
      () async {
    final queue = newQueue();
    server.online = false;
    await queue.enqueue('navigation_sessions', {'from_node': 'a'});
    await queue.enqueue('sus_responses', {'q1': 5}, keepForever: true);

    final offline = await queue.flush();
    expect(offline.sent, 0);
    expect(offline.remaining, 2);
    expect(server.inserted, isEmpty);
    expect(connectivity.isOnline, isFalse);

    server.online = true;
    final online = await queue.flush();
    expect(online.sent, 2);
    expect(online.remaining, 0);
    // Oldest first, payloads unchanged.
    expect(server.inserted.map((e) => e.$1),
        ['navigation_sessions', 'sus_responses']);
    expect(server.inserted.last.$2, {'q1': 5});
    expect(await queue.pending(), isEmpty);
    expect(connectivity.isOnline, isTrue);
  });

  test('queued writes survive an app restart and are retried on start',
      () async {
    server.online = false;
    await newQueue().enqueue('sus_responses', {'q1': 4}, keepForever: true);
    await newQueue().flush();

    // "Restart": a brand-new queue reading the same device storage.
    server.online = true;
    final restarted = newQueue();
    expect(await restarted.pending(), hasLength(1));
    final r = await restarted.flush();
    expect(r.sent, 1);
    expect(server.inserted.single.$2, {'q1': 4});
  });

  test('a network failure stops the flush; nothing after it is lost',
      () async {
    final queue = newQueue();
    for (var i = 0; i < 3; i++) {
      await queue.enqueue('navigation_sessions', {'i': i});
    }
    server.online = false;
    await queue.flush();
    final left = await queue.pending();
    expect(left.map((w) => w.payload['i']), [0, 1, 2]);
  });

  test('a rejected write does not block the writes behind it', () async {
    final queue = newQueue();
    server.rejectTables = {'navigation_sessions'};
    await queue.enqueue('navigation_sessions', {'bad': true});
    await queue.enqueue('sus_responses', {'q1': 3}, keepForever: true);

    final r = await queue.flush();
    expect(r.sent, 1);
    expect(server.inserted.single.$1, 'sus_responses');
    expect((await queue.pending()).single.attempts, 1);
  });

  test('survey answers are never dropped; other writes are after '
      '${PendingWriteQueue.maxRejections} rejections', () async {
    final queue = newQueue();
    server.rejectTables = {'sus_responses', 'navigation_sessions'};
    await queue.enqueue('sus_responses', {'q1': 1}, keepForever: true);
    await queue.enqueue('navigation_sessions', {'n': 1});

    for (var i = 0; i < PendingWriteQueue.maxRejections + 3; i++) {
      await queue.flush();
    }
    final left = await queue.pending();
    expect(left.map((w) => w.table), ['sus_responses']);

    // Once the server accepts it, the kept answer goes through.
    server.rejectTables = {};
    await queue.flush();
    expect(server.inserted.single.$2, {'q1': 1});
  });

  test('a row the server already has leaves the queue, even a kept one',
      () async {
    final queue = PendingWriteQueue(
      sender: (table, payload) async {
        if (payload['q1'] == 1) {
          throw const PostgrestException(
              message: 'duplicate key value',
              code: PendingWriteQueue.uniqueViolation);
        }
        server.inserted.add((table, payload));
      },
      connectivity: connectivity,
    );
    await queue.enqueue('sus_responses', {'q1': 1}, keepForever: true);
    await queue.enqueue('sus_responses', {'q1': 2}, keepForever: true);

    final r = await queue.flush();

    expect(await queue.pending(), isEmpty);
    expect(r.remaining, 0);
    expect(server.inserted.single.$2, {'q1': 2});
  });

  group('retry', () {
    test('the attempt count survives a restart', () async {
      server.rejectTables = {'navigation_sessions'};
      await newQueue().enqueue('navigation_sessions', {'n': 1});
      await newQueue().flush();
      await newQueue().flush();

      expect((await newQueue().pending()).single.attempts, 2);
    });

    test('being offline is not a rejection: no attempts are used', () async {
      final queue = newQueue();
      await queue.enqueue('navigation_sessions', {'n': 1});
      server.online = false;

      for (var i = 0; i < PendingWriteQueue.maxRejections + 2; i++) {
        await queue.flush();
      }

      final left = (await queue.pending()).single;
      expect(left.attempts, 0);
    });

    test('a send that hangs counts as offline and the row stays', () async {
      final queue = PendingWriteQueue(
        sender: (_, _) => Completer<void>().future,
        connectivity: connectivity,
        sendTimeout: const Duration(milliseconds: 20),
      );
      await queue.enqueue('sus_responses', {'q1': 1}, keepForever: true);

      final r = await queue.flush();

      expect(r.remaining, 1);
      expect(connectivity.isOnline, isFalse);
    });

    test('writes added during a flush are not lost', () async {
      late PendingWriteQueue queue;
      queue = PendingWriteQueue(
        sender: (table, payload) async {
          if (payload['first'] == true) {
            unawaited(queue.enqueue('sus_responses', {'second': true}));
          }
          server.inserted.add((table, payload));
        },
        connectivity: connectivity,
      );
      await queue.enqueue('sus_responses', {'first': true});

      await queue.flush();
      expect((await queue.pending()).single.payload, {'second': true});
    });

    test('a retried write keeps its id and table', () async {
      server.rejectTables = {'navigation_sessions'};
      final queue = newQueue();
      final id = await queue.enqueue('navigation_sessions', {'n': 1});

      await queue.flush();

      expect(await queue.isPending(id), isTrue);
      expect((await queue.pending()).single.table, 'navigation_sessions');
    });

    test('an unreadable queue is set aside, not wiped', () async {
      SharedPreferences.setMockInitialValues(
          {PendingWriteQueue.storageKey: 'not json'});

      expect(await newQueue().pending(), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('${PendingWriteQueue.storageKey}.corrupt'),
          'not json');
    });
  });

  group('duplicate reply', () {
    Future<void> duplicate(String _, Map<String, dynamic> _) async {
      throw const PostgrestException(
          message: 'duplicate key value',
          code: PendingWriteQueue.uniqueViolation);
    }

    test('counts as sent, for an ordinary row too', () async {
      final queue = PendingWriteQueue(
          sender: duplicate, connectivity: connectivity);
      await queue.enqueue('navigation_sessions', {'n': 1});

      final r = await queue.flush();

      expect(r.sent, 1);
      expect(r.dropped, 0);
      expect(r.remaining, 0);
    });

    test('a lost reply is not sent twice', () async {
      var sends = 0;
      final queue = PendingWriteQueue(
        sender: (table, payload) async {
          sends++;
          if (sends == 1) throw const SocketException('reply lost');
          throw const PostgrestException(
              message: 'duplicate key value',
              code: PendingWriteQueue.uniqueViolation);
        },
        connectivity: connectivity,
      );
      await queue.enqueue('sus_responses', {'q1': 1}, keepForever: true);

      await queue.flush();
      expect(await queue.pending(), hasLength(1));

      await queue.flush();
      expect(await queue.pending(), isEmpty);
      expect(sends, 2);
    });

    test('does not stop the rows behind it', () async {
      final queue = PendingWriteQueue(
        sender: (table, payload) async {
          if (payload['dup'] == true) {
            await duplicate(table, payload);
          }
          server.inserted.add((table, payload));
        },
        connectivity: connectivity,
      );
      await queue.enqueue('sus_responses', {'dup': true});
      await queue.enqueue('sus_responses', {'q1': 2});

      await queue.flush();

      expect(server.inserted.single.$2, {'q1': 2});
    });
  });

  group('permanent rejection', () {
    Future<void> rejectTimes(PendingWriteQueue queue, int times) async {
      for (var i = 0; i < times; i++) {
        await queue.flush();
      }
    }

    test('one rejection short of the limit, the row stays', () async {
      final queue = newQueue();
      server.rejectTables = {'navigation_sessions'};
      await queue.enqueue('navigation_sessions', {'n': 1});

      await rejectTimes(queue, PendingWriteQueue.maxRejections - 1);

      expect((await queue.pending()).single.attempts,
          PendingWriteQueue.maxRejections - 1);
    });

    test('the last rejection drops it and says so', () async {
      final queue = newQueue();
      server.rejectTables = {'navigation_sessions'};
      await queue.enqueue('navigation_sessions', {'n': 1});
      await rejectTimes(queue, PendingWriteQueue.maxRejections - 1);

      final r = await queue.flush();

      expect(r.dropped, 1);
      expect(r.sent, 0);
      expect(await queue.pending(), isEmpty);
    });

    test('a kept row outlives the limit and keeps counting', () async {
      final queue = newQueue();
      server.rejectTables = {'sus_responses'};
      await queue.enqueue('sus_responses', {'q1': 1}, keepForever: true);

      await rejectTimes(queue, PendingWriteQueue.maxRejections + 2);

      final left = (await queue.pending()).single;
      expect(left.keepForever, isTrue);
      expect(left.attempts, PendingWriteQueue.maxRejections + 2);
    });

    test('a rejection does not mean the phone is offline', () async {
      final queue = newQueue();
      server.rejectTables = {'navigation_sessions'};
      await queue.enqueue('navigation_sessions', {'n': 1});

      await queue.flush();

      expect(connectivity.isOnline, isTrue);
    });
  });

  group('SurveyRepository.submitResponse', () {
    SurveyRepository repo(PendingWriteQueue queue) => SurveyRepository(
          SupabaseClient('http://localhost:54321', 'test-anon-key'),
          OfflineCache(connectivity: connectivity),
          queue,
        );

    Future<bool> submit(SurveyRepository r) => r.submitResponse(
          visitorSessionId: 'v1',
          answers: List.filled(10, 3),
          susScore: 50,
          userType: 'visitor',
        );

    test('offline: kept on the device and reported as queued', () async {
      final queue = newQueue();
      server.online = false;
      expect(await submit(repo(queue)), isFalse);

      final saved = (await queue.pending()).single;
      expect(saved.table, 'sus_responses');
      expect(saved.keepForever, isTrue);
      expect(saved.payload['q10'], 3);
      expect(saved.payload['sus_score'], 50);

      server.online = true;
      await queue.flush();
      expect(server.inserted.single.$2['visitor_session_id'], 'v1');
    });

    test('online: sent immediately and not left in the queue', () async {
      final queue = newQueue();
      expect(await submit(repo(queue)), isTrue);
      expect(await queue.pending(), isEmpty);
      expect(server.inserted, hasLength(1));
    });
  });
}
