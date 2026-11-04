import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/json_utils.dart';
import '../local/offline_cache.dart';
import '../models/facility_model.dart';
import 'indoor_navigation_repository.dart';
import 'paging.dart';
import 'repository_exception.dart';

class FacilityRepository {
  final SupabaseClient _client;
  final OfflineCache _offline;
  final DateTime Function() _now;
  FacilityRepository(
      [SupabaseClient? client, OfflineCache? offline, DateTime Function()? now])
      : _client = client ?? Supabase.instance.client,
        _offline = offline ?? OfflineCache.instance,
        _now = now ?? DateTime.now;

  /// How long the inactive-facility list is reused before it is reloaded —
  /// the same expiry as the indoor map.
  static const Duration inactiveIdsTtl = IndoorNavigationRepository.cacheTtl;

  static const String inactiveIdsErrorMessage =
      'Could not check which facilities are closed.';

  /// Every facility with `buildings(id, name)` and nested `facility_details`.
  static const String allCacheKey = 'facilities:all';
  static const String allSelect = '''
    *,
    buildings(id, name),
    facility_details(
      id, facility_id, office_hours, contact_number,
      services, payment_method, instructions
    )
  ''';

  /// `{'facilities': [...], 'details': [...]}` for one building.
  static String buildingCacheKey(int buildingId) =>
      'facilities:building:$buildingId';

  Future<List<FacilityModel>> getFacilitiesForBuilding(int buildingId) async {
    try {
      final data = await _offline.fetch<Map<String, dynamic>>(
        buildingCacheKey(buildingId),
        () async {
          final rows = await _client
              .from('facilities')
              .select()
              .eq('building_id', buildingId);
          if (rows.isEmpty) {
            return <String, dynamic>{'facilities': rows, 'details': const []};
          }
          final ids = rows.map((f) => f['id']).toList();
          final detailRows = await _client
              .from('facility_details')
              .select()
              .inFilter('facility_id', ids);
          return <String, dynamic>{
            'facilities': rows,
            'details': detailRows,
          };
        },
      );
      return facilitiesFromCacheEntry(data);
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load facilities: ${e.message}');
    } catch (_) {
      throw RepositoryException('Could not load facilities.');
    }
  }

  /// Builds models from a [buildingCacheKey] entry, enriched with details.
  /// Inactive facilities are left out (missing / null `is_active` counts as
  /// active), also for copies saved before the column existed.
  static List<FacilityModel> facilitiesFromCacheEntry(
      Map<String, dynamic> data) {
    final detailsById = <int, FacilityDetailsModel>{};
    for (final d in (data['details'] as List? ?? const [])) {
      final model = FacilityDetailsModel.fromMap(d as Map<String, dynamic>);
      detailsById[model.facilityId] = model;
    }
    return J.activeRows(data['facilities'] as List? ?? const []).map((m) {
      final f = FacilityModel.fromMap(m);
      return FacilityModel.fromMap(m, details: detailsById[f.id]);
    }).toList();
  }

  /// Ids of facilities marked inactive, from the last full load, and when.
  Set<int>? _inactiveIds;
  DateTime? _inactiveIdsAt;

  /// Raw rows of every **active** facility with `buildings(id, name)` and
  /// nested `facility_details`, sorted by name. Network first; offline, the
  /// last saved copy. Throws when neither works.
  Future<List<Map<String, dynamic>>> getAllFacilityRows() async {
    final rows = await _offline.fetch<List<dynamic>>(
      allCacheKey,
      () => fetchAllPages((from, to) async => await _client
          .from('facilities')
          .select(allSelect)
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

  /// Ids of inactive facilities (to hide indoor nodes linked to them),
  /// reloaded once older than [inactiveIdsTtl].
  ///
  /// When a reload fails (no server and no saved copy) the previous list is
  /// kept and the failure logged; with no list at all it throws
  /// [RepositoryException] — it never pretends that nothing is closed.
  Future<Set<int>> inactiveFacilityIds() async {
    final at = _inactiveIdsAt;
    final last = _inactiveIds;
    if (last != null && at != null && _now().difference(at) < inactiveIdsTtl) {
      return last;
    }
    try {
      await getAllFacilityRows();
      return _inactiveIds!;
    } catch (e) {
      if (last != null) {
        debugPrint('⚠️ Could not refresh the closed-facility list ($e) — '
            'using the one from $at');
        return last;
      }
      debugPrint('❌ Could not load the closed-facility list: $e');
      throw RepositoryException(inactiveIdsErrorMessage);
    }
  }
}
