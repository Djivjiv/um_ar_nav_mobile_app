part of 'search_cubit.dart';

enum SearchStatus { initial, loading, loaded, error }

class SearchState {
  final SearchStatus status;
  final String query;
  final List<BuildingModel> buildings;
  final List<RoomModel> rooms;
  final List<IndoorNodeModel> indoorNodes;

  /// A result the user tapped from the search overlay, for the map to pin.
  /// Consumed (cleared) by the map once handled.
  final Map<String, dynamic>? pickedPlace;

  const SearchState({
    required this.status,
    this.query = '',
    this.buildings = const [],
    this.rooms = const [],
    this.indoorNodes = const [],
    this.pickedPlace,
  });

  const SearchState.initial() : this(status: SearchStatus.initial);

  bool get isEmpty =>
      buildings.isEmpty && rooms.isEmpty && indoorNodes.isEmpty;

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    List<BuildingModel>? buildings,
    List<RoomModel>? rooms,
    List<IndoorNodeModel>? indoorNodes,
    Map<String, dynamic>? pickedPlace,
    bool clearPickedPlace = false,
  }) {
    return SearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      buildings: buildings ?? this.buildings,
      rooms: rooms ?? this.rooms,
      indoorNodes: indoorNodes ?? this.indoorNodes,
      pickedPlace:
          clearPickedPlace ? null : (pickedPlace ?? this.pickedPlace),
    );
  }
}
