part of 'indoor_nav_cubit.dart';

enum IndoorNavStatus { initial, loading, ready, computing, routeReady, error }

class IndoorNavState {
  final IndoorNavStatus status;
  final String? floorPlanId;
  final List<IndoorNodeModel> nodes;
  final List<IndoorEdgeModel> edges;
  final IndoorNodeModel? fromNode;
  final IndoorNodeModel? toNode;

  /// Path points as pixel coords packed LatLng(y, x).
  final List<LatLng> pathPixels;
  final List<String> pathNodeIds;
  final String? error;

  const IndoorNavState({
    required this.status,
    this.floorPlanId,
    this.nodes = const [],
    this.edges = const [],
    this.fromNode,
    this.toNode,
    this.pathPixels = const [],
    this.pathNodeIds = const [],
    this.error,
  });

  const IndoorNavState.initial() : this(status: IndoorNavStatus.initial);

  bool get hasRoute => pathPixels.length >= 2;

  IndoorNavState copyWith({
    IndoorNavStatus? status,
    String? floorPlanId,
    List<IndoorNodeModel>? nodes,
    List<IndoorEdgeModel>? edges,
    IndoorNodeModel? fromNode,
    IndoorNodeModel? toNode,
    List<LatLng>? pathPixels,
    List<String>? pathNodeIds,
    String? error,
    bool clearRoute = false,
    bool clearSelection = false,
  }) {
    return IndoorNavState(
      status: status ?? this.status,
      floorPlanId: floorPlanId ?? this.floorPlanId,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      fromNode: clearSelection ? null : (fromNode ?? this.fromNode),
      toNode: clearSelection ? null : (toNode ?? this.toNode),
      pathPixels: clearRoute ? const [] : (pathPixels ?? this.pathPixels),
      pathNodeIds: clearRoute ? const [] : (pathNodeIds ?? this.pathNodeIds),
      error: error,
    );
  }
}
