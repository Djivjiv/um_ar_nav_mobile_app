import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/network/connectivity_service.dart';
import 'local/campus_tile_cache.dart';
import 'local/floor_plan_image_cache.dart';
import 'local/offline_cache.dart';
import 'local/pending_write_queue.dart';
import 'repositories/about_repository.dart';
import 'repositories/building_repository.dart';
import 'repositories/facility_repository.dart';
import 'repositories/floor_plan_repository.dart';
import 'repositories/indoor_navigation_repository.dart';
import 'repositories/outdoor_ar_repository.dart';
import 'repositories/outdoor_navigation_repository.dart';
import 'repositories/paging.dart';
import 'repositories/room_repository.dart';
import 'repositories/survey_repository.dart';

/// Keeps the offline copies complete and the write queue moving:
///
/// - on app start: sends queued writes, then (at most every
///   [warmUpInterval]) downloads everything navigation needs — including
///   every floor plan image — so the app works offline even for buildings
///   the user hasn't opened yet;
/// - when the connection returns: sends queued writes and refreshes every
///   copy in the background.
class OfflineSync {
  OfflineSync({
    required this.buildings,
    required this.rooms,
    required this.facilities,
    required this.floorPlans,
    required this.indoor,
    required this.outdoor,
    required this.outdoorAr,
    required this.about,
    required this.survey,
    SupabaseClient? client,
    OfflineCache? cache,
    PendingWriteQueue? queue,
    ConnectivityService? connectivity,
    CampusTileCache? tiles,
  })  : _client = client ?? Supabase.instance.client,
        _cache = cache ?? OfflineCache.instance,
        _queue = queue ?? PendingWriteQueue.instance,
        _connectivity = connectivity ?? ConnectivityService.instance,
        _tiles = tiles ?? CampusTileCache.instance;

  final BuildingRepository buildings;
  final RoomRepository rooms;
  final FacilityRepository facilities;
  final FloorPlanRepository floorPlans;
  final IndoorNavigationRepository indoor;
  final OutdoorNavigationRepository outdoor;
  final OutdoorArRepository outdoorAr;
  final AboutRepository about;
  final SurveyRepository survey;

  final SupabaseClient _client;
  final OfflineCache _cache;
  final PendingWriteQueue _queue;
  final ConnectivityService _connectivity;
  final CampusTileCache _tiles;

  static const Duration warmUpInterval = Duration(hours: 6);
  static const String _lastWarmUpKey = 'offline_last_warmup';

  bool _warming = false;

  /// Call once after Supabase is initialised. Never throws.
  void start() {
    _connectivity.addReconnectListener(_onReconnect);
    unawaited(_connectivity.start());
    // Let the splash screen's own loads go first.
    Timer(const Duration(seconds: 3), () async {
      await _flushQueue();
      await warmUp();
    });
  }

  Future<void> _onReconnect() async {
    debugPrint('🌐 Back online — sending queued writes and refreshing data');
    await _flushQueue();
    await warmUp(force: true);
  }

  Future<void> _flushQueue() async {
    try {
      final r = await _queue.flush();
      if (r.sent > 0 || r.remaining > 0) {
        debugPrint('📤 Queue: ${r.sent} sent, ${r.remaining} waiting, '
            '${r.dropped} dropped');
      }
    } catch (e) {
      debugPrint('📤 Queue flush failed: $e');
    }
  }

  /// Refreshes every offline copy. Skipped when one ran less than
  /// [warmUpInterval] ago (unless [force]) or while offline.
  Future<void> warmUp({bool force = false}) async {
    if (_warming) return;
    _warming = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = DateTime.tryParse(prefs.getString(_lastWarmUpKey) ?? '');
      if (!force &&
          last != null &&
          DateTime.now().difference(last) < warmUpInterval) {
        return;
      }
      await _connectivity.checkNow();
      if (!_connectivity.isOnline) return;

      debugPrint('📦 Saving campus data for offline use…');
      var ok = true;
      Future<void> step(String name, Future<void> Function() run) async {
        try {
          await run();
        } catch (e) {
          ok = false;
          debugPrint('📦 Offline warm-up "$name" failed: $e');
        }
      }

      // Repository loads save their own copies on success.
      await step('buildings', () => buildings.getBuildings(forceRefresh: true));
      await step('outdoor graph', () => outdoor.loadGraph(forceRefresh: true));
      await step('AR network', () => outdoorAr.getNetwork(forceRefresh: true));
      await step('about', about.getAbout);
      await step('survey questions', survey.getQuestions);
      // Grouped copies are saved only from live data, never re-stamped from
      // an older offline copy.
      await step('rooms', _warmRooms);
      await step('facilities', _warmFacilities);
      await step('floors + indoor graph', _warmFloorsAndIndoor);
      // Campus map tiles (zoom 16–19), last — only missing ones download.
      await step('map tiles', _tiles.warm);

      if (ok) {
        await prefs.setString(_lastWarmUpKey, DateTime.now().toIso8601String());
      }
      debugPrint('📦 Offline warm-up ${ok ? 'complete' : 'partly failed'}');
    } catch (e) {
      debugPrint('📦 Offline warm-up failed: $e');
    } finally {
      _warming = false;
    }
  }

  Future<List<Map<String, dynamic>>> _all(
    String table, {
    String columns = '*',
    bool activeOnly = false,
  }) async {
    final rows = await fetchAllPages((from, to) async {
      var q = _client.from(table).select(columns);
      if (activeOnly) q = q.eq('is_active', true);
      return await q.order('id').range(from, to);
    }).timeout(const Duration(seconds: 60));
    return rows.cast<Map<String, dynamic>>();
  }

  static Map<String, List<Map<String, dynamic>>> _groupBy(
      List<Map<String, dynamic>> rows, String column) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final k = r[column]?.toString();
      if (k == null) continue;
      out.putIfAbsent(k, () => []).add(r);
    }
    return out;
  }

  static int _num(Object? v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;

  Future<void> _warmRooms() async {
    final rows = await _all('rooms', columns: '*, buildings(name)');
    await _cache.save(RoomRepository.allCacheKey, rows);
    for (final e in _groupBy(rows, 'building_id').entries) {
      final id = int.tryParse(e.key);
      if (id == null) continue;
      e.value.sort((a, b) => _num(a['floor']).compareTo(_num(b['floor'])));
      await _cache.save(RoomRepository.buildingCacheKey(id), e.value);
    }
  }

  Future<void> _warmFacilities() async {
    final rows =
        await _all('facilities', columns: FacilityRepository.allSelect);
    await _cache.save(FacilityRepository.allCacheKey, rows);
    for (final e in _groupBy(rows, 'building_id').entries) {
      final id = int.tryParse(e.key);
      if (id == null) continue;
      final details = <Map<String, dynamic>>[];
      for (final f in e.value) {
        final d = f['facility_details'];
        if (d is List) details.addAll(d.whereType<Map<String, dynamic>>());
        if (d is Map<String, dynamic>) details.add(d);
      }
      await _cache.save(FacilityRepository.buildingCacheKey(id), {
        'facilities': e.value,
        'details': details,
      });
    }
  }

  Future<void> _warmFloorsAndIndoor() async {
    final floors = await _all('building_floors', activeOnly: true);
    for (final e in _groupBy(floors, 'building_id').entries) {
      final id = int.tryParse(e.key);
      if (id == null) continue;
      e.value.sort(
          (a, b) => _num(a['floor_number']).compareTo(_num(b['floor_number'])));
      await _cache.save(FloorPlanRepository.buildingCacheKey(id), e.value);
    }

    final nodesByFloor = _groupBy(await _all('indoor_nodes'), 'floor_plan_id');
    final edgesByFloor = _groupBy(
        await _all('indoor_edges', activeOnly: true), 'floor_plan_id');
    // Every active floor gets an entry, even an empty one, so an unmapped
    // floor reads as "no nodes" offline rather than "no connection".
    final floorIds = {
      for (final f in floors) f['id']?.toString(),
      ...nodesByFloor.keys,
      ...edgesByFloor.keys,
    }.whereType<String>();
    for (final id in floorIds) {
      await _cache.save(IndoorNavigationRepository.nodesCacheKey(id),
          nodesByFloor[id] ?? const []);
      await _cache.save(IndoorNavigationRepository.edgesCacheKey(id),
          edgesByFloor[id] ?? const []);
    }
    indoor.clearCache();

    // Floor plan images, last — the largest downloads.
    await FloorPlanImageCache.instance
        .prefetch(floors.map((f) => f['image_url']?.toString()));
  }
}
