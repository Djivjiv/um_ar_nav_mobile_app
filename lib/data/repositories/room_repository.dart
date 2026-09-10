import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/room_model.dart';
import 'repository_exception.dart';

class RoomRepository {
  final SupabaseClient _client;
  RoomRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  Future<List<RoomModel>> getRoomsForBuilding(int buildingId) async {
    try {
      final rows = await _client
          .from('rooms')
          .select()
          .eq('building_id', buildingId)
          .order('floor');
      return (rows as List)
          .map((e) => RoomModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw RepositoryException('Could not load rooms: ${e.message}');
    } catch (_) {
      throw RepositoryException('Could not load rooms.');
    }
  }

  Future<List<RoomModel>> searchRooms(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      final rows = await _client
          .from('rooms')
          .select()
          .or('roomname.ilike.%$query%,short_name.ilike.%$query%')
          .limit(30);
      return (rows as List)
          .map((e) => RoomModel.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<RoomModel?> getRoomById(int id) async {
    try {
      final row =
          await _client.from('rooms').select().eq('id', id).maybeSingle();
      return row == null ? null : RoomModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }
}
