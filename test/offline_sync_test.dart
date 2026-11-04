import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/data/local/campus_tile_cache.dart';
import 'package:um_ar_mobile_app/data/local/offline_cache.dart';
import 'package:um_ar_mobile_app/data/local/pending_write_queue.dart';
import 'package:um_ar_mobile_app/data/models/about_um_model.dart';
import 'package:um_ar_mobile_app/data/models/building_model.dart';
import 'package:um_ar_mobile_app/data/models/survey_question_model.dart';
import 'package:um_ar_mobile_app/data/offline_sync.dart';
import 'package:um_ar_mobile_app/data/repositories/about_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/building_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/facility_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/floor_plan_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/indoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_ar_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/room_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';

const lastWarmUpKey = 'offline_last_warmup';

class FakeBuildings implements BuildingRepository {
  int refreshes = 0;
  @override
  Future<List<BuildingModel>> getBuildings({bool forceRefresh = false}) async {
    if (forceRefresh) refreshes++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOutdoor implements OutdoorNavigationRepository {
  bool failing = false;
  @override
  Future<void> loadGraph({bool forceRefresh = false}) async {
    if (failing) throw StateError('no graph');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAr implements OutdoorArRepository {
  @override
  Future<ArNetwork> getNetwork({bool forceRefresh = false}) async =>
      const ArNetwork(nodes: [], edges: []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAbout implements AboutRepository {
  @override
  Future<AboutUmModel> getAbout() async => const AboutUmModel(id: '1');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSurvey implements SurveyRepository {
  @override
  Future<List<SurveyQuestionModel>> getQuestions() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeIndoor implements IndoorNavigationRepository {
  @override
  void clearCache() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Rooms, facilities and floor plans only lend their cache keys, which are
/// static, so nothing is ever called on these.
class NoCalls
    implements RoomRepository, FacilityRepository, FloorPlanRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTiles implements CampusTileCache {
  int warms = 0;
  @override
  Future<TileWarmResult> warm(
      {List<CampusTileSource> sources = const []}) async {
    warms++;
    return const TileWarmResult();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late HttpServer rest;
  late FakeBuildings buildings;
  late FakeOutdoor outdoor;
  late FakeTiles tiles;
  late ConnectivityService connectivity;
  late List<(String, Map<String, dynamic>)> sent;
  late bool serverUp;
  late PendingWriteQueue queue;
  late bool reachable;
  late OfflineSync sync;

  setUpAll(() {
    // start() needs the binding, which blocks HTTP unless told otherwise.
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Every table is empty, which is all the warm-up needs from the server.
    rest = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    rest.listen((request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write('[]');
      await request.response.close();
    });

    buildings = FakeBuildings();
    outdoor = FakeOutdoor();
    tiles = FakeTiles();
    sent = [];
    serverUp = true;
    reachable = true;
    connectivity = ConnectivityService(probe: () async => reachable);
    queue = PendingWriteQueue(
      sender: (table, payload) async {
        if (!serverUp) throw const SocketException('No route to host');
        sent.add((table, payload));
      },
      connectivity: connectivity,
      sendTimeout: const Duration(seconds: 1),
    );
    final none = NoCalls();
    sync = OfflineSync(
      buildings: buildings,
      rooms: none,
      facilities: none,
      floorPlans: none,
      indoor: FakeIndoor(),
      outdoor: outdoor,
      outdoorAr: FakeAr(),
      about: FakeAbout(),
      survey: FakeSurvey(),
      client: SupabaseClient('http://127.0.0.1:${rest.port}', 'test-key'),
      cache: OfflineCache(connectivity: connectivity),
      queue: queue,
      connectivity: connectivity,
      tiles: tiles,
    );
  });

  tearDown(() async {
    connectivity.dispose();
    await rest.close(force: true);
  });

  Future<String?> stamp() async =>
      (await SharedPreferences.getInstance()).getString(lastWarmUpKey);

  /// Waits for background work, which goes through a real socket.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  group('warm-up', () {
    test('refreshes everything and stamps the time', () async {
      await sync.warmUp();

      expect(buildings.refreshes, 1);
      expect(tiles.warms, 1);
      expect(await stamp(), isNotNull);
    });

    test('is skipped soon after the last one', () async {
      SharedPreferences.setMockInitialValues(
          {lastWarmUpKey: DateTime.now().toIso8601String()});

      await sync.warmUp();

      expect(buildings.refreshes, 0);
    });

    test('runs again once the interval has passed', () async {
      SharedPreferences.setMockInitialValues({
        lastWarmUpKey: DateTime.now()
            .subtract(OfflineSync.warmUpInterval + const Duration(minutes: 1))
            .toIso8601String(),
      });

      await sync.warmUp();

      expect(buildings.refreshes, 1);
    });

    test('force ignores the interval', () async {
      SharedPreferences.setMockInitialValues(
          {lastWarmUpKey: DateTime.now().toIso8601String()});

      await sync.warmUp(force: true);

      expect(buildings.refreshes, 1);
    });

    test('offline it downloads nothing', () async {
      reachable = false;

      await sync.warmUp();

      expect(buildings.refreshes, 0);
      expect(await stamp(), isNull);
    });

    test('a failed step does not stop the rest or throw', () async {
      outdoor.failing = true;

      await expectLater(sync.warmUp(), completes);

      expect(tiles.warms, 1);
    });

    test('a partly failed warm-up is not stamped, so it runs again', () async {
      outdoor.failing = true;
      await sync.warmUp();
      expect(await stamp(), isNull);

      outdoor.failing = false;
      await sync.warmUp();
      expect(buildings.refreshes, 2);
      expect(await stamp(), isNotNull);
    });

    test('two at once run as one', () async {
      await Future.wait([sync.warmUp(), sync.warmUp()]);

      expect(buildings.refreshes, 1);
    });
  });

  group('when the connection returns', () {
    test('queued writes go out and the data refreshes', () async {
      sync.start();
      await queue.enqueue('sus_responses', {'q1': 1}, keepForever: true);
      serverUp = false;
      await queue.flush();
      expect(connectivity.isOnline, isFalse);

      serverUp = true;
      connectivity.reportOnline();
      await until(() => tiles.warms > 0);

      expect(sent.single.$2, {'q1': 1});
      expect(await queue.pending(), isEmpty);
      expect(buildings.refreshes, 1);
    });

    test('the refresh ignores the interval', () async {
      SharedPreferences.setMockInitialValues(
          {lastWarmUpKey: DateTime.now().toIso8601String()});
      sync.start();
      connectivity.reportOffline();

      connectivity.reportOnline();
      await until(() => tiles.warms > 0);

      expect(buildings.refreshes, 1);
    });

    test('a queue that fails to send does not stop the refresh', () async {
      sync.start();
      await queue.enqueue('sus_responses', {'q1': 1}, keepForever: true);
      serverUp = false;
      await queue.flush();

      connectivity.reportOnline();
      await until(() => tiles.warms > 0);

      expect(tiles.warms, 1);
      expect(await queue.pending(), hasLength(1));
    });
  });
}
