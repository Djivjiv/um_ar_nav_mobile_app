import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/building_model.dart';
import '../../../data/models/facility_model.dart';
import '../../../data/models/room_model.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/facility_repository.dart';
import '../../../data/repositories/repository_exception.dart';
import '../../../data/repositories/room_repository.dart';

part 'building_state.dart';

class BuildingCubit extends Cubit<BuildingState> {
  final BuildingRepository _buildings;
  final RoomRepository _rooms;
  final FacilityRepository _facilities;

  BuildingCubit(this._buildings, this._rooms, this._facilities)
      : super(const BuildingState.initial());

  Future<void> loadBuildings({bool forceRefresh = false}) async {
    emit(state.copyWith(status: BuildingStatus.loading, error: null));
    try {
      final list = await _buildings.getBuildings(forceRefresh: forceRefresh);
      emit(state.copyWith(
        status: BuildingStatus.loaded,
        buildings: list,
      ));
    } on RepositoryException catch (e) {
      emit(state.copyWith(status: BuildingStatus.error, error: e.message));
    } catch (_) {
      emit(state.copyWith(
          status: BuildingStatus.error, error: 'Failed to load buildings.'));
    }
  }

  Future<void> selectBuilding(int buildingId) async {
    emit(state.copyWith(
      detailStatus: BuildingStatus.loading,
      selectedError: null,
    ));
    try {
      final building = await _buildings.getBuildingById(buildingId);
      final rooms = await _rooms.getRoomsForBuilding(buildingId);
      List<FacilityModel> facilities = const [];
      try {
        facilities = await _facilities.getFacilitiesForBuilding(buildingId);
      } catch (_) {}
      emit(state.copyWith(
        detailStatus: BuildingStatus.loaded,
        selectedBuilding: building,
        selectedRooms: rooms,
        selectedFacilities: facilities,
      ));
    } on RepositoryException catch (e) {
      emit(state.copyWith(
          detailStatus: BuildingStatus.error, selectedError: e.message));
    } catch (_) {
      emit(state.copyWith(
          detailStatus: BuildingStatus.error,
          selectedError: 'Failed to load building details.'));
    }
  }

  BuildingModel? buildingById(int id) {
    for (final b in state.buildings) {
      if (b.id == id) return b;
    }
    return null;
  }
}
