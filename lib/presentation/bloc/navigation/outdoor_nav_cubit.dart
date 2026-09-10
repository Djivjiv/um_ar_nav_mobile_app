import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/building_model.dart';
import '../../../data/repositories/outdoor_navigation_repository.dart';
import '../../../data/repositories/repository_exception.dart';
import '../../../domain/services/dijkstra_service.dart';
import '../../../domain/services/instruction_service.dart';

part 'outdoor_nav_state.dart';

/// Average walking speed on campus paths, metres/second (~4.8 km/h).
const double _walkSpeed = 1.33;

class OutdoorNavCubit extends Cubit<OutdoorNavState> {
  final OutdoorNavigationRepository _repo;

  OutdoorNavCubit(this._repo) : super(const OutdoorNavState.idle());

  OutdoorNavigationRepository get repo => _repo;

  Future<void> ensureGraph() async {
    if (_repo.isLoaded) {
      if (state.status == OutdoorNavStatus.idle) {
        emit(state.copyWith(status: OutdoorNavStatus.graphReady));
      }
      return;
    }
    emit(state.copyWith(status: OutdoorNavStatus.loadingGraph, error: null));
    try {
      await _repo.loadGraph();
      emit(state.copyWith(status: OutdoorNavStatus.graphReady));
    } on RepositoryException catch (e) {
      emit(state.copyWith(status: OutdoorNavStatus.error, error: e.message));
    }
  }

  void setFrom(NavEndpoint endpoint) => emit(state.copyWith(from: endpoint));

  void setTo(NavEndpoint endpoint) => emit(state.copyWith(to: endpoint));

  void swapEndpoints() {
    emit(state.copyWith(from: state.to, to: state.from));
  }

  /// Convenience: start a route to a building from the nearest graph node
  /// (or from an explicit origin node when provided).
  Future<void> routeToBuilding(BuildingModel building,
      {String? fromNodeId, LatLng? fromPoint}) async {
    await ensureGraph();
    if (state.status == OutdoorNavStatus.error) return;

    String? startId = fromNodeId;
    if (startId == null) {
      final LatLng? origin = fromPoint ?? state.from?.point;
      if (origin != null) {
        startId = _repo.nearestNode(origin.latitude, origin.longitude)?.id;
      } else if (_repo.nodes.isNotEmpty) {
        startId = _repo.nodes.first.id;
      }
    }
    if (startId == null) {
      emit(state.copyWith(
          status: OutdoorNavStatus.error,
          error: 'No starting point available.'));
      return;
    }

    final startNode = _repo.nodes.firstWhere((n) => n.id == startId,
        orElse: () => _repo.nodes.first);
    setFrom(NavEndpoint(
      label: startNode.name ?? 'Current location',
      nodeId: startNode.id,
      point: startNode.point,
    ));
    setTo(NavEndpoint(label: building.label, buildingId: building.id));

    emit(state.copyWith(status: OutdoorNavStatus.computing, error: null));
    final result = DijkstraService.findPathToBuilding(
      startNodeId: startId,
      buildingId: building.id,
      nodes: _repo.nodes,
      edges: _repo.edges,
    );
    _applyResult(result, destinationName: building.label);
  }

  /// Explicit node-to-node routing (used by the map's Plan-a-Route sheet).
  /// Both ids must be real `outdoor_nodes` ids; the caller snaps buildings /
  /// rooms / facilities to their nearest graph node first.
  Future<void> findRouteBetween({
    required String fromNodeId,
    required String toNodeId,
    String? fromName,
    String? toName,
  }) async {
    await ensureGraph();

    // Check the repository directly — never gate on a transient error status
    // left by a previous attempt (that made retries silently no-op).
    if (!_repo.isLoaded || _repo.nodes.isEmpty || _repo.edges.isEmpty) {
      emit(state.copyWith(
          status: OutdoorNavStatus.error,
          error: 'Campus map data is not available yet.'));
      return;
    }
    if (fromNodeId == toNodeId) {
      emit(state.copyWith(
          status: OutdoorNavStatus.error,
          error: 'Start and destination are the same point.'));
      return;
    }

    debugPrint('🔍 Dijkstra: $fromNodeId → $toNodeId '
        '(${_repo.nodes.length} nodes / ${_repo.edges.length} edges)');

    emit(state.copyWith(
      from: NavEndpoint(label: fromName ?? 'Start', nodeId: fromNodeId),
      to: NavEndpoint(label: toName ?? 'Destination', nodeId: toNodeId),
      status: OutdoorNavStatus.computing,
      error: null,
    ));

    final result = DijkstraService.findShortestPath(
      startNodeId: fromNodeId,
      endNodeId: toNodeId,
      nodes: _repo.nodes,
      edges: _repo.edges,
    );

    if (result == null) {
      final reachable = _reachableFrom(fromNodeId);
      debugPrint('❌ Dijkstra: no path. $fromNodeId reaches '
          '${reachable.length}/${_repo.nodes.length} nodes; '
          'target $toNodeId reachable = ${reachable.contains(toNodeId)}');
      emit(state.copyWith(
        status: OutdoorNavStatus.error,
        error: reachable.contains(toNodeId)
            ? 'No route found between those points.'
            : 'These two points are not connected on the campus path network.',
      ));
      return;
    }

    debugPrint('✅ Dijkstra: ${result.nodeIds.length} nodes, '
        '${result.distanceMeters.toStringAsFixed(0)} m');
    _applyResult(result, destinationName: toName ?? 'your destination');
  }

  /// BFS over the active edge graph (respecting `is_two_way`) — diagnostic
  /// helper used when Dijkstra returns no path.
  Set<String> _reachableFrom(String startId) {
    final adjacency = <String, List<String>>{};
    for (final e in _repo.edges) {
      if (!e.isActive) continue;
      adjacency.putIfAbsent(e.fromNode, () => []).add(e.toNode);
      if (e.isTwoWay) {
        adjacency.putIfAbsent(e.toNode, () => []).add(e.fromNode);
      }
    }
    final seen = <String>{startId};
    final queue = <String>[startId];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final next in adjacency[cur] ?? const <String>[]) {
        if (seen.add(next)) queue.add(next);
      }
    }
    return seen;
  }

  Future<void> findRoute() async {
    final from = state.from;
    final to = state.to;
    if (from == null || to == null) {
      emit(state.copyWith(
          status: OutdoorNavStatus.error,
          error: 'Choose both a start and a destination.'));
      return;
    }
    await ensureGraph();
    if (state.status == OutdoorNavStatus.error) return;

    if (from.nodeId == null) {
      emit(state.copyWith(
          status: OutdoorNavStatus.error,
          error: 'Starting point is not on the path network.'));
      return;
    }

    emit(state.copyWith(status: OutdoorNavStatus.computing, error: null));

    PathResult? result;
    if (to.isBuilding) {
      result = DijkstraService.findPathToBuilding(
        startNodeId: from.nodeId!,
        buildingId: to.buildingId,
        nodes: _repo.nodes,
        edges: _repo.edges,
      );
    } else if (to.nodeId != null) {
      result = DijkstraService.findShortestPath(
        startNodeId: from.nodeId!,
        endNodeId: to.nodeId!,
        nodes: _repo.nodes,
        edges: _repo.edges,
      );
    }
    _applyResult(result, destinationName: to.label);
  }

  void _applyResult(PathResult? result, {required String destinationName}) {
    if (result == null || result.points.length < 2) {
      emit(state.copyWith(
          status: OutdoorNavStatus.error,
          error: 'No route found between those points.'));
      return;
    }
    final instructions = InstructionService.generateInstructions(
      result.points,
      _repo.nodes,
      destinationName: destinationName,
    );
    emit(state.copyWith(
      status: OutdoorNavStatus.routeReady,
      path: result.points,
      instructions: instructions,
      distanceMeters: result.distanceMeters,
      walkMinutes: (result.distanceMeters / _walkSpeed / 60).ceil(),
      waypointCount: result.nodeIds.length,
      currentStep: 0,
      error: null,
    ));
  }

  void nextStep() {
    if (state.currentStep < state.instructions.length - 1) {
      emit(state.copyWith(currentStep: state.currentStep + 1));
    }
  }

  void previousStep() {
    if (state.currentStep > 0) {
      emit(state.copyWith(currentStep: state.currentStep - 1));
    }
  }

  void goToStep(int index) {
    if (index >= 0 && index < state.instructions.length) {
      emit(state.copyWith(currentStep: index));
    }
  }

  void clearRoute() {
    emit(const OutdoorNavState(status: OutdoorNavStatus.graphReady));
  }
}
