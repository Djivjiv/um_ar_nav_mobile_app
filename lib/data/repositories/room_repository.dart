import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/json_utils.dart';
import '../../core/utils/postgrest_filter.dart';
import '../local/offline_cache.dart';
import '../models/room_model.dart';
import 'indoor_navigation_repository.dart';
import 'paging.dart';
import 'repository_exception.dart';

class RoomRepository {
  final SupabaseClient _client;
  final OfflineCache _offline;
  final DateTime Function() _now;
  RoomRepository(
      [SupabaseClient? client, OfflineCache? offline, DateTime Function()? now])
      : _client = client ?? Supabase.instance.client,
        _offline = offline ?? OfflineCache.instance,
        _now = now ?? DateTime.now;

  /// How long the inactive-room list is reused before it is reloaded — the
  /// same expiry as the indoor map, so admin changes reach a running app.
  static const Duration inactiveIdsTtl = IndoorNavigationRepository.cacheTtl;

  /// Every room with its building's name (search / destinations).
  static const String allCacheKey = 'rooms:all';
  static String buildingCacheKey(int buildingId) => 'rooms:building:$buildingId';

  /// Active rooms of a building (missing / null `is_active` counts as
  /// active). Network first; offline, the last saved copy.
  Future<List<RoomModel>> getRoomsForBuilding(int buildingId) async {
    try {
      final rows = await _offline.fetch<List<dynamic>>(
        buildingCacheKey(buildingId),
        () async => await _client
            .from('rooms')
            .select()
            .eq('building_id', buildingId)
            .order('floor'),
      );
      return J.activeRows(rows).map(RoomModel.fromMap).toList();
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load rooms: ${e.message}');
    } catch (_) {
      throw RepositoryException('Could not load rooms.');
    }
  }

  /// Ids of rooms marked inactive, from the last full load, and when.
  Set<int>? _inactiveIds;
  DateTime? _inactiveIdsAt;

  /// Raw rows of every **active** room plus `buildings(name)`, sorted by
  /// room name. Network first; offline, the last saved copy. Throws when
  /// neither works.
  Future<List<Map<String, dynamic>>> getAllRoomRows() async {
    final rows = await _offline.fetch<List<dynamic>>(
      allCacheKey,
      () => fetchAllPages((from, to) async => await _client
          .from('rooms')
          .select('*, buildings(name)')
          .order('id')
          .range(from, to)),
    );
    _inactiveIds = J.inactiveIds(rows);
    _inactiveIdsAt = _now();
    return J.activeRows(rows)
      ..sort((a, b) => (a['roomname'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['roomname'] ?? '').toString().toLowerCase()));
  }

  /// Ids of inactive rooms (to hide indoor nodes linked to them), reloaded
  /// once older than [inactiveIdsTtl].
  ///
  /// When a reload fails (no server and no saved copy) the previous list is
  /// kept and the failure logged; with no list at all it throws
  /// [RepositoryException] — it never pretends that no room is closed.
  Future<Set<int>> inactiveRoomIds() async {
    final at = _inactiveIdsAt;
    final last = _inactiveIds;
    if (last != null && at != null && _now().difference(at) < inactiveIdsTtl) {
      return last;
    }
    try {
      await getAllRoomRows();
      return _inactiveIds!;
    } catch (e) {
      if (last != null) {
        debugPrint('⚠️ Could not refresh the closed-room list ($e) — '
            'using the one from $at');
        return last;
      }
      debugPrint('❌ Could not load the closed-room list: $e');
      throw RepositoryException(inactiveIdsErrorMessage);
    }
  }

  static const String inactiveIdsErrorMessage =
      'Could not check which rooms are closed.';

  Future<List<RoomModel>> searchRooms(String query) async {
    final term = sanitizeIlikeTerm(query);
    if (term.isEmpty) return const [];
    try {
      final rows = await _client
          .from('rooms')
          .select()
          .or('roomname.ilike.%$term%,short_name.ilike.%$term%')
          .limit(30)
          .timeout(_offline.networkTimeout);
      return J.activeRows(rows).map(RoomModel.fromMap).toList();
    } catch (_) {
      final saved = await _searchCached(query);
      if (saved == null) rethrow;
      return saved;
    }
  }

  /// Offline search over the saved room list, or null when none is saved.
  Future<List<RoomModel>?> _searchCached(String query) async {
    final entry = await _offline.get(allCacheKey);
    final rows = entry?.data;
    if (rows is! List) return null;
    final q = query.trim().toLowerCase();
    return J
        .activeRows(rows)
        .where((r) =>
            (r['roomname'] ?? '').toString().toLowerCase().contains(q) ||
            (r['short_name'] ?? '').toString().toLowerCase().contains(q))
        .take(30)
        .map(RoomModel.fromMap)
        .toList();
  }
}
