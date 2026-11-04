import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/core/utils/ttl_cache.dart';
import 'package:um_ar_mobile_app/data/repositories/indoor_navigation_repository.dart';

void main() {
  group('TtlCache (indoor nodes / edges cache)', () {
    late DateTime now;
    late TtlCache<String, List<int>> cache;

    setUp(() {
      now = DateTime(2026, 10, 28, 9);
      cache = TtlCache(
        ttl: IndoorNavigationRepository.cacheTtl,
        now: () => now,
      );
    });

    test('indoor data is cached for 10 minutes', () {
      expect(IndoorNavigationRepository.cacheTtl, const Duration(minutes: 10));
    });

    test('returns the value while fresh', () {
      cache.put('floor-1', [1, 2]);
      now = now.add(const Duration(minutes: 9, seconds: 59));
      expect(cache.get('floor-1'), [1, 2]);
    });

    test('expires after the TTL so the next load re-fetches', () {
      cache.put('floor-1', [1, 2]);
      now = now.add(const Duration(minutes: 10));
      expect(cache.get('floor-1'), isNull);
    });

    test('a re-put restarts the clock', () {
      cache.put('floor-1', [1]);
      now = now.add(const Duration(minutes: 8));
      cache.put('floor-1', [2]);
      now = now.add(const Duration(minutes: 8));
      expect(cache.get('floor-1'), [2]);
    });

    test('clear() drops everything (Retry / forced refresh)', () {
      cache.put('a', [1]);
      cache.put('b', [2]);
      cache.clear();
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNull);
    });

    test('missing keys return null', () {
      expect(cache.get('nope'), isNull);
    });
  });
}
