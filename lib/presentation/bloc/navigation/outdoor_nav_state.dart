part of 'outdoor_nav_cubit.dart';

enum OutdoorNavStatus { idle, loadingGraph, graphReady, computing, routeReady, error }

/// Endpoint of a route: either a building or a raw graph node.
class NavEndpoint {
  final String label;
  final String? nodeId;
  final int? buildingId;
  final LatLng? point;

  const NavEndpoint({
    required this.label,
    this.nodeId,
    this.buildingId,
    this.point,
  });

  bool get isBuilding => buildingId != null;
}

class OutdoorNavState {
  final OutdoorNavStatus status;
  final NavEndpoint? from;
  final NavEndpoint? to;
  final List<LatLng> path;
  final List<NavigationInstruction> instructions;
  final double distanceMeters;
  final int walkMinutes;
  final int waypointCount;
  final String? error;

  /// Index of the current step in turn-by-turn mode.
  final int currentStep;

  const OutdoorNavState({
    required this.status,
    this.from,
    this.to,
    this.path = const [],
    this.instructions = const [],
    this.distanceMeters = 0,
    this.walkMinutes = 0,
    this.waypointCount = 0,
    this.error,
    this.currentStep = 0,
  });

  const OutdoorNavState.idle() : this(status: OutdoorNavStatus.idle);

  bool get hasRoute =>
      status == OutdoorNavStatus.routeReady && path.length >= 2;

  OutdoorNavState copyWith({
    OutdoorNavStatus? status,
    NavEndpoint? from,
    NavEndpoint? to,
    List<LatLng>? path,
    List<NavigationInstruction>? instructions,
    double? distanceMeters,
    int? walkMinutes,
    int? waypointCount,
    String? error,
    int? currentStep,
    bool clearRoute = false,
  }) {
    return OutdoorNavState(
      status: status ?? this.status,
      from: from ?? this.from,
      to: to ?? this.to,
      path: clearRoute ? const [] : (path ?? this.path),
      instructions:
          clearRoute ? const [] : (instructions ?? this.instructions),
      distanceMeters: clearRoute ? 0 : (distanceMeters ?? this.distanceMeters),
      walkMinutes: clearRoute ? 0 : (walkMinutes ?? this.walkMinutes),
      waypointCount: clearRoute ? 0 : (waypointCount ?? this.waypointCount),
      error: error,
      currentStep: currentStep ?? this.currentStep,
    );
  }
}
