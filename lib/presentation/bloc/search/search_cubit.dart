import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/building_model.dart';
import '../../../data/models/indoor_node_model.dart';
import '../../../data/models/room_model.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/indoor_navigation_repository.dart';
import '../../../data/repositories/room_repository.dart';

part 'search_state.dart';

/// Unified search across buildings, rooms and indoor nodes.
class SearchCubit extends Cubit<SearchState> {
  final BuildingRepository _buildings;
  final RoomRepository _rooms;
  final IndoorNavigationRepository _indoor;

  Timer? _debounce;

  SearchCubit(this._buildings, this._rooms, this._indoor)
      : super(const SearchState.initial());

  void queryChanged(String raw) {
    final query = raw.trim();
    _debounce?.cancel();
    if (query.isEmpty) {
      emit(const SearchState.initial());
      return;
    }
    emit(state.copyWith(status: SearchStatus.loading, query: query));
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(query));
  }

  Future<void> _run(String query) async {
    try {
      final allBuildings = await _buildings.getBuildings();
      final lower = query.toLowerCase();
      final buildingHits = allBuildings
          .where((b) =>
              b.name.toLowerCase().contains(lower) ||
              (b.shortName ?? '').toLowerCase().contains(lower) ||
              (b.displayName ?? '').toLowerCase().contains(lower))
          .take(8)
          .toList();

      final roomHits = await _rooms.searchRooms(query);
      final nodeHits = await _indoor.searchNodes(query);

      emit(SearchState(
        status: SearchStatus.loaded,
        query: query,
        buildings: buildingHits,
        rooms: roomHits.take(10).toList(),
        indoorNodes: nodeHits.take(10).toList(),
      ));
    } catch (_) {
      emit(state.copyWith(status: SearchStatus.error));
    }
  }

  void clear() => emit(const SearchState.initial());

  /// A result was tapped in the search overlay — hand it to the map to pin.
  void pickPlace(Map<String, dynamic> place) =>
      emit(state.copyWith(pickedPlace: place));

  /// The map has handled the picked place.
  void consumePickedPlace() =>
      emit(state.copyWith(clearPickedPlace: true));

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
