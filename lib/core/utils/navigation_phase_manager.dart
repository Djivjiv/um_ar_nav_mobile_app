import 'package:latlong2/latlong.dart';

/// Ordered stages a full journey can pass through.
enum NavigationPhase {
  exitOriginBuilding, // Phase 1 — leave the room's building (text screen)
  outdoorNavigation, // Phase 2 — campus turn-by-turn
  elevatorOrStairs, // Phase 3A — pick vertical transport
  indoorNavigation, // Phase 3B — floor-plan navigation
  arrived, // Final — success screen
}

/// Everything the multi-phase navigation screen needs for one journey.
class NavigationRoute {
  final Map<String, dynamic> from;
  final Map<String, dynamic> to;
  final List<NavigationPhase> phases;
  int currentPhaseIndex;

  // Origin building info (when `from` is a room / facility).
  final String? originBuildingId;
  final String? originBuildingName;
  final String? originRoomName;
  final String? originEntranceLabel;
  final int? originFloor;

  /// Room → room in the same building: open the indoor phase in "top view"
  /// (whole route) first so the user can preview it.
  final bool startInTopView;

  // Destination building info.
  final String? destBuildingId;
  final String? destBuildingName;
  final String? destRoomName;
  final int? destFloor;

  // Outdoor path.
  final List<LatLng> outdoorPath;

  /// The last `outdoor_nodes` id of the outdoor route — the entrance the user
  /// arrives at. Null when the trip has no outdoor leg.
  final String? arrivalOutdoorNodeId;
  final String? fromName;
  final String? toName;
  final double? distanceMeters;
  final int? estimatedMinutes;

  // Indoor.
  final bool hasElevator;
  String? selectedTransport; // 'stairs' | 'elevator'

  NavigationRoute({
    required this.from,
    required this.to,
    required this.phases,
    this.currentPhaseIndex = 0,
    this.originFloor,
    this.startInTopView = false,
    this.originBuildingId,
    this.originBuildingName,
    this.originRoomName,
    this.originEntranceLabel,
    this.destBuildingId,
    this.destBuildingName,
    this.destRoomName,
    this.destFloor,
    this.outdoorPath = const [],
    this.arrivalOutdoorNodeId,
    this.fromName,
    this.toName,
    this.distanceMeters,
    this.estimatedMinutes,
    this.hasElevator = false,
    this.selectedTransport,
  });

  NavigationPhase get currentPhase =>
      phases[currentPhaseIndex.clamp(0, phases.length - 1)];

  bool get isLastPhase => currentPhaseIndex >= phases.length - 1;

  void advancePhase() {
    if (!isLastPhase) currentPhaseIndex++;
  }

  static bool _isIndoor(String? type) => type == 'room' || type == 'facility';

  static int? _floorOf(Map<String, dynamic> m) {
    final raw = m['floor'];
    if (raw is int) return raw;
    if (raw != null) return int.tryParse(raw.toString());
    return null;
  }

  /// Picks the phase sequence from the endpoint types + whether the two
  /// endpoints are in the same building.
  static List<NavigationPhase> determinePhases({
    required Map<String, dynamic> from,
    required Map<String, dynamic> to,
  }) {
    final fromType = (from['type'] ?? 'building').toString();
    final toType = (to['type'] ?? 'building').toString();

    final fromBuildingId = from['building_id']?.toString() ??
        (fromType == 'building' ? from['id']?.toString() : null);
    final toBuildingId = to['building_id']?.toString() ??
        (toType == 'building' ? to['id']?.toString() : null);

    final sameBuilding = fromBuildingId != null &&
        toBuildingId != null &&
        fromBuildingId == toBuildingId;

    // Indoor → indoor, same building — never go outside.
    if (_isIndoor(fromType) && _isIndoor(toType) && sameBuilding) {
      final fromFloor = _floorOf(from);
      final toFloor = _floorOf(to);
      if (fromFloor != null && toFloor != null && fromFloor != toFloor) {
        return const [
          NavigationPhase.elevatorOrStairs,
          NavigationPhase.indoorNavigation,
          NavigationPhase.arrived,
        ];
      }
      return const [
        NavigationPhase.indoorNavigation,
        NavigationPhase.arrived,
      ];
    }

    // Building/Gate → Building/Gate.
    if (fromType == 'building' && toType == 'building') {
      return const [
        NavigationPhase.outdoorNavigation,
        NavigationPhase.arrived,
      ];
    }

    // Indoor → Building.
    if (_isIndoor(fromType) && toType == 'building') {
      return const [
        NavigationPhase.exitOriginBuilding,
        NavigationPhase.outdoorNavigation,
        NavigationPhase.arrived,
      ];
    }

    // Building → room in that same building: already there, no outdoor leg.
    // The stairs / elevator step is skipped once the entrance's floor is
    // known to be the destination floor.
    if (fromType == 'building' && _isIndoor(toType) && sameBuilding) {
      return const [
        NavigationPhase.elevatorOrStairs,
        NavigationPhase.indoorNavigation,
        NavigationPhase.arrived,
      ];
    }

    // Building/Gate → Indoor.
    if (fromType == 'building' && _isIndoor(toType)) {
      return const [
        NavigationPhase.outdoorNavigation,
        NavigationPhase.elevatorOrStairs,
        NavigationPhase.indoorNavigation,
        NavigationPhase.arrived,
      ];
    }

    // Indoor → Indoor, different building.
    if (_isIndoor(fromType) && _isIndoor(toType) && !sameBuilding) {
      return const [
        NavigationPhase.exitOriginBuilding,
        NavigationPhase.outdoorNavigation,
        NavigationPhase.elevatorOrStairs,
        NavigationPhase.indoorNavigation,
        NavigationPhase.arrived,
      ];
    }

    // Default — outdoor only.
    return const [
      NavigationPhase.outdoorNavigation,
      NavigationPhase.arrived,
    ];
  }
}
