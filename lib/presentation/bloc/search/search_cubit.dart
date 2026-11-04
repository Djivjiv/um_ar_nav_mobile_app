import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/utils/indoor_route_helpers.dart';
import '../../../data/models/building_model.dart';
import '../../../data/models/indoor_node_model.dart';
import '../../../data/models/room_model.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/facility_repository.dart';
import '../../../data/repositories/indoor_navigation_repository.dart';
import '../../../data/repositories/room_repository.dart';

part 'search_state.dart';

/// Unified search across buildings, rooms and indoor nodes.
class SearchCubit extends Cubit<SearchState> {
  final BuildingRepository _buildings;
  final RoomRepository _rooms;
  final IndoorNavigationRepository _indoor;

  /// Used to hide indoor nodes linked to inactive facilities.
  final FacilityRepository? _facilities;

  Timer? _debounce;

  /// Bumped by every new query / clear. A search only emits while its own
  /// number is still the latest, so a slow older query that finishes after
  /// a newer one can't overwrite the newer results.
  int _generation = 0;

  /// Debounce before a query runs.
  final Duration debounce;

  SearchCubit(this._buildings, this._rooms, this._indoor,
      [this._facilities, this.debounce = const Duration(milliseconds: 300)])
      : super(const SearchState.initial());

  /// Shown above the results when closed rooms / facilities could not be
  /// checked, so some listed indoor places may be closed.
  static const String closedCheckNotice =
      'Could not check which rooms and facilities are closed — some '
      'indoor places listed may be unavailable.';

  /// Shown when the search failed, so it can't be read as "nothing found".
  static const String failedMessage =
      'Could not search. Check your connection.';

  /// Runs the failed search again.
  void retry() => queryChanged(state.query);

  void queryChanged(String raw) {
    final query = raw.trim();
    _debounce?.cancel();
    final generation = ++_generation;
    if (query.isEmpty) {
      emit(const SearchState.initial());
      return;
    }
    emit(state.copyWith(status: SearchStatus.loading, query: query));
    _debounce = Timer(debounce, () => _run(query, generation));
  }

  bool _stale(int generation) => isClosed || generation != _generation;

  Future<void> _run(String query, int generation) async {
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
      if (_stale(generation)) return;

      // Hide nodes linked to inactive rooms / facilities. If either list
      // can't be loaded the results still show, with a visible notice.
      String? notice;
      var inactiveRooms = const <int>{};
      var inactiveFacilities = const <int>{};
      try {
        inactiveRooms = await _rooms.inactiveRoomIds();
        inactiveFacilities =
            await _facilities?.inactiveFacilityIds() ?? const <int>{};
      } catch (e) {
        debugPrint('🔎 Search: $e');
        notice = closedCheckNotice;
      }
      final nodeHits = (await _indoor.searchNodes(query))
          .where((n) => isLinkedPlaceActive(n,
              inactiveRoomIds: inactiveRooms,
              inactiveFacilityIds: inactiveFacilities))
          .toList();
      if (_stale(generation)) return;

      emit(SearchState(
        status: SearchStatus.loaded,
        query: query,
        buildings: buildingHits,
        rooms: roomHits.take(10).toList(),
        indoorNodes: nodeHits.take(10).toList(),
        notice: notice,
      ));
    } catch (_) {
      if (_stale(generation)) return;
      emit(state.copyWith(status: SearchStatus.error));
    }
  }

  void clear() {
    _debounce?.cancel();
    _generation++;
    emit(const SearchState.initial());
  }

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
