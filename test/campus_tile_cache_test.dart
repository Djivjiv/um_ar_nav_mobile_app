import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/core/config/maptiler_config.dart';
import 'package:um_ar_mobile_app/data/local/campus_tile_cache.dart';

void main() {
  late Directory dir;
  late bool online;
  late int downloads;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('campus_tiles_test');
    online = true;
    downloads = 0;
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  CampusTileCache newCache({int maxBytes = 200 * 1024 * 1024}) =>
      CampusTileCache(
        maxBytes: maxBytes,
        directory: () async => dir,
        download: (url) async {
          if (!online) throw const SocketException('offline');
          downloads++;
          if (url.toString().contains('/16/')) {
            // pretend the overlay has nothing at zoom 16
            if (url.toString().contains('tiles/')) throw NoTileException(url);
          }
          return List<int>.filled(1000, 7);
        },
      );

  test('tile maths: campus centre at zoom 16', () {
    final c = MapTilerConfig.campusCenter;
    // 125.595°E, 7.067°N → tile 55631 / 31478 at z16 (checked with awk
    // using the standard slippy-map formula).
    expect(CampusTileCache.tileX(c.longitude, 16), 55631);
    expect(CampusTileCache.tileY(c.latitude, 16), 31478);
    expect(CampusTileCache.tileX(c.longitude, 19), 445055);
    expect(CampusTileCache.tileY(c.latitude, 19), 251825);
  });

  test('covers only campus tiles at zoom 16–19', () {
    final cache = newCache();
    final c = MapTilerConfig.campusCenter;
    for (var z = 16; z <= 19; z++) {
      expect(
          cache.covers(z, CampusTileCache.tileX(c.longitude, z),
              CampusTileCache.tileY(c.latitude, z)),
          isTrue,
          reason: 'zoom $z');
    }
    expect(cache.covers(15, 27817, 15739), isFalse, reason: 'zoom 15');
    expect(cache.covers(17, 0, 0), isFalse, reason: 'far away');
  });

  test('the campus is a few hundred tiles per layer, not thousands', () {
    final n = newCache().allTiles().length;
    expect(n, greaterThan(50));
    expect(n, lessThan(600));
  });

  test('a loaded tile is served from disk when offline (after a restart)',
      () async {
    const s = CampusTileSource.base;
    expect(newCache().covers(17, 111263, 62956), isTrue);
    expect(await newCache().load(s, 17, 111263, 62956), hasLength(1000));
    expect(downloads, 1);

    online = false;
    final afterRestart = newCache(); // new instance, same folder
    expect(await afterRestart.load(s, 17, 111263, 62956), hasLength(1000));
    expect(downloads, 1);
  });

  test('warm downloads every missing tile once', () async {
    final cache = newCache();
    final r = await cache.warm(sources: const [CampusTileSource.base]);
    expect(r.downloaded, cache.allTiles().length);
    final again = await cache.warm(sources: const [CampusTileSource.base]);
    expect(again.downloaded, 0);
    expect(again.alreadySaved, cache.allTiles().length);
  });

  test('"no tile here" is remembered and not counted as a failure', () async {
    final cache = newCache();
    await cache.warm(sources: const [CampusTileSource.overlay]);
    final before = downloads;
    online = false;
    final (z, x, y) = cache.allTiles().first; // a zoom-16 tile
    await expectLater(cache.load(CampusTileSource.overlay, z, x, y),
        throwsA(isA<NoTileException>()));
    expect(downloads, before);
  });

  test('warm while offline throws so the next sync retries', () async {
    online = false;
    await expectLater(newCache().warm(), throwsException);
  });

  test('prune keeps the cache under its size cap', () async {
    final cache = newCache(maxBytes: 50 * 1000);
    await cache.warm(sources: const [CampusTileSource.base]);
    expect(await cache.sizeBytes(), lessThanOrEqualTo(50 * 1000));
  });
}
