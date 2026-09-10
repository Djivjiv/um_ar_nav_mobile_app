part of 'building_cubit.dart';

enum BuildingStatus { initial, loading, loaded, error }

class BuildingState {
  final BuildingStatus status;
  final List<BuildingModel> buildings;
  final String? error;

  final BuildingStatus detailStatus;
  final BuildingModel? selectedBuilding;
  final List<RoomModel> selectedRooms;
  final List<FacilityModel> selectedFacilities;
  final String? selectedError;

  const BuildingState({
    required this.status,
    this.buildings = const [],
    this.error,
    this.detailStatus = BuildingStatus.initial,
    this.selectedBuilding,
    this.selectedRooms = const [],
    this.selectedFacilities = const [],
    this.selectedError,
  });

  const BuildingState.initial() : this(status: BuildingStatus.initial);

  BuildingState copyWith({
    BuildingStatus? status,
    List<BuildingModel>? buildings,
    String? error,
    BuildingStatus? detailStatus,
    BuildingModel? selectedBuilding,
    List<RoomModel>? selectedRooms,
    List<FacilityModel>? selectedFacilities,
    String? selectedError,
  }) {
    return BuildingState(
      status: status ?? this.status,
      buildings: buildings ?? this.buildings,
      error: error,
      detailStatus: detailStatus ?? this.detailStatus,
      selectedBuilding: selectedBuilding ?? this.selectedBuilding,
      selectedRooms: selectedRooms ?? this.selectedRooms,
      selectedFacilities: selectedFacilities ?? this.selectedFacilities,
      selectedError: selectedError,
    );
  }
}
