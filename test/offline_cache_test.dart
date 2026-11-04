import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/data/local/offline_cache.dart';

void main() {
  late DateTime clock;
  late ConnectivityService connectivity;
  late OfflineCache cache;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 10, 28, 9);
    // Never started → no timers; state changes only through reports.
    connectivity = ConnectivityService(probe: () async => true, now: () => clock);
    cache = OfflineCache(
      connectivity: connectivity,
      now: () => clock,
      networkTimeout: const Duration(milliseconds: 200),
    );
  });

  Future<List<dynamic>> offline() async =>
      throw const SocketException('Failed host lookup');

  group('network first, cache fallback', () {
    test('a live load is returned and saved', () async {
      final r = await cache.read<List<dynamic>>('buildings', () async => [
            {'id': 1, 'name': 'BE'}
          ]);
      expect(r.fromCache, isFalse);
      expect(r.data, [
        {'id': 1, 'name': 'BE'}
      ]);
      final saved = await cache.get('buildings');
      expect(saved!.data, r.data);
      expect(saved.savedAt, clock);
    });

    test('no connection → the saved copy, marked offline', () async {
      await cache.read<List<dynamic>>('buildings', () async => [
            {'id': 1}
          ]);
      final savedAt = clock;
      clock = clock.add(const Duration(hours: 3));

      final r = await cache.read<List<dynamic>>('buildings', offline);
      expect(r.fromCache, isTrue);
      expect(r.data, [
        {'id': 1}
      ]);
      expect(r.savedAt, savedAt);
      expect(connectivity.isOnline, isFalse);
      expect(connectivity.dataUpdatedAt, savedAt);
    });

    test('a timeout also falls back to the saved copy', () async {
      await cache.save('about_um', {'mission': 'saved'});
      final never = Completer<Map<String, dynamic>?>();
      final r = await cache.read<Map<String, dynamic>?>(
          'about_um', () => never.future);
      expect(r.fromCache, isTrue);
      expect(r.data, {'mission': 'saved'});
    });

    test('no connection and no saved copy → the original error', () async {
      expect(
        () => cache.read<List<dynamic>>('rooms:all', offline),
        throwsA(isA<SocketException>()),
      );
    });

    test('a server error uses the copy but does not mean "offline"',
        () async {
      await cache.save('outdoor_nodes', [
        {'id': 'n1'}
      ]);
      final r = await cache.read<List<dynamic>>('outdoor_nodes',
          () async => throw PostgrestException(message: 'column missing'));
      expect(r.fromCache, isTrue);
      expect(connectivity.isOnline, isTrue);
    });

    test('a failed load never overwrites the saved copy', () async {
      await cache.save('survey_questions', [1, 2, 3]);
      final before = await cache.get('survey_questions');
      clock = clock.add(const Duration(days: 1));
      await cache.read<List<dynamic>>('survey_questions', offline);
      final after = await cache.get('survey_questions');
      expect(after!.data, [1, 2, 3]);
      expect(after.savedAt, before!.savedAt);
    });
  });

  group('older cache replaced by live data', () {
    test('fresh rows and timestamp replace an older copy', () async {
      final old = DateTime(2026, 9, 1);
      await cache.save('outdoor_edges', [
        {'id': 'e1', 'weight': 10}
      ], savedAt: old);

      clock = DateTime(2026, 10, 28, 10);
      final r = await cache.read<List<dynamic>>('outdoor_edges', () async => [
            {'id': 'e1', 'weight': 12},
            {'id': 'e2', 'weight': 4},
          ]);
      expect(r.fromCache, isFalse);
      expect(r.data, hasLength(2));

      final saved = await cache.get('outdoor_edges');
      expect(saved!.savedAt, clock);
      expect(saved.savedAt.isAfter(old), isTrue);
      expect((saved.data as List).first, {'id': 'e1', 'weight': 12});

      // Later offline reads get the new data, not the old copy.
      final offlineRead =
          await cache.read<List<dynamic>>('outdoor_edges', offline);
      expect(offlineRead.data, hasLength(2));
      expect(offlineRead.savedAt, clock);
    });

    test('an empty live result also replaces the copy', () async {
      await cache.save('indoor_edges:floor:7', [
        {'id': 'x'}
      ], savedAt: DateTime(2026, 1, 1));
      await cache.read<List<dynamic>>(
          'indoor_edges:floor:7', () async => const []);
      expect((await cache.get('indoor_edges:floor:7'))!.data, isEmpty);
    });
  });

  test('getAll lists entries under a prefix', () async {
    await cache.save('indoor_nodes:floor:1', [1]);
    await cache.save('indoor_nodes:floor:2', [2]);
    await cache.save('indoor_edges:floor:1', [3]);
    final all = await cache.getAll('indoor_nodes:floor:');
    expect(all.keys.toSet(), {'indoor_nodes:floor:1', 'indoor_nodes:floor:2'});
  });

  test('coming back online runs reconnect listeners once and clears the '
      'offline timestamp', () async {
    var reconnects = 0;
    connectivity.addReconnectListener(() async => reconnects++);
    await cache.save('buildings', [1]);
    await cache.read<List<dynamic>>('buildings', offline);
    expect(connectivity.isOnline, isFalse);

    await cache.read<List<dynamic>>('buildings', () async => [2]);
    await cache.read<List<dynamic>>('buildings', () async => [3]);
    await Future<void>.delayed(Duration.zero);
    expect(connectivity.isOnline, isTrue);
    expect(reconnects, 1);
    expect(connectivity.dataUpdatedAt, clock);
  });
}
