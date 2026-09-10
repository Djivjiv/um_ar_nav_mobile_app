import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/facility_model.dart';
import 'repository_exception.dart';

class FacilityRepository {
  final SupabaseClient _client;
  FacilityRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  Future<List<FacilityModel>> getFacilitiesForBuilding(int buildingId) async {
    try {
      final rows = await _client
          .from('facilities')
          .select()
          .eq('building_id', buildingId);
      final facilities = (rows as List)
          .map((e) => FacilityModel.fromMap(e as Map<String, dynamic>))
          .toList();

      // Enrich with facility_details where available.
      if (facilities.isEmpty) return facilities;
      final ids = facilities.map((f) => f.id).toList();
      final detailRows = await _client
          .from('facility_details')
          .select()
          .inFilter('facility_id', ids);
      final detailsById = <int, FacilityDetailsModel>{};
      for (final d in (detailRows as List)) {
        final model =
            FacilityDetailsModel.fromMap(d as Map<String, dynamic>);
        detailsById[model.facilityId] = model;
      }

      return facilities
          .map((f) => FacilityModel(
                id: f.id,
                buildingId: f.buildingId,
                roomName: f.roomName,
                roomNumber: f.roomNumber,
                floor: f.floor,
                facilityCategories: f.facilityCategories,
                description: f.description,
                location: f.location,
                officeHours: f.officeHours,
                details: detailsById[f.id],
              ))
          .toList();
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load facilities: ${e.message}');
    } catch (_) {
      throw RepositoryException('Could not load facilities.');
    }
  }

  Future<List<FacilityModel>> searchFacilities(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final rows = await _client
          .from('facilities')
          .select()
          .ilike('roomname', '%$query%')
          .limit(30);
      return (rows as List)
          .map((e) => FacilityModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
