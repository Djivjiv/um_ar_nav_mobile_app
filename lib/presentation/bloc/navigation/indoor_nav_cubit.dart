import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

import '../../../data/models/indoor_edge_model.dart';
import '../../../data/models/indoor_node_model.dart';
import '../../../data/repositories/indoor_navigation_repository.dart';
import '../../../data/repositories/repository_exception.dart';
import '../../../domain/services/dijkstra_service.dart';

part 'indoor_nav_state.dart';

class IndoorNavCubit extends Cubit<IndoorNavState> {
  final IndoorNavigationRepository _repo;

  IndoorNavCubit(this._repo) : super(const IndoorNavState.initial());

  Future<void> loadFloor(String floorPlanId) async {
    emit(state.copyWith(
      status: IndoorNavStatus.loading,
      floorPlanId: floorPlanId,
      clearRoute: true,
      clearSelection: true,
      error: null,
    ));
    try {
      final nodes = await _repo.getNodesForFloor(floorPlanId);
      final edges = await _repo.getEdgesForFloor(floorPlanId);
      emit(state.copyWith(
        status: IndoorNavStatus.ready,
        nodes: nodes,
        edges: edges,
      ));
    } on RepositoryException catch (e) {
      emit(state.copyWith(status: IndoorNavStatus.error, error: e.message));
    } catch (_) {
      emit(state.copyWith(
          status: IndoorNavStatus.error,
          error: 'Failed to load the floor plan.'));
    }
  }

  void setFrom(IndoorNodeModel node) =>
      emit(state.copyWith(fromNode: node, clearRoute: true));

  void setTo(IndoorNodeModel node) =>
      emit(state.copyWith(toNode: node, clearRoute: true));

  void computeRoute() {
    final from = state.fromNode;
    final to = state.toNode;
    if (from == null || to == null) {
      emit(state.copyWith(
          status: IndoorNavStatus.error,
          error: 'Pick a start and destination room.'));
      return;
    }
    emit(state.copyWith(status: IndoorNavStatus.computing, error: null));
    final result = DijkstraService.findIndoorPath(
      startNodeId: from.id,
      endNodeId: to.id,
      nodes: state.nodes,
      edges: state.edges,
    );
    if (result == null || result.points.length < 2) {
      emit(state.copyWith(
          status: IndoorNavStatus.error,
          error: 'No indoor path found between those rooms.'));
      return;
    }
    emit(state.copyWith(
      status: IndoorNavStatus.routeReady,
      pathPixels: result.points,
      pathNodeIds: result.nodeIds,
      error: null,
    ));
  }

  void clearRoute() => emit(state.copyWith(
        status: IndoorNavStatus.ready,
        clearRoute: true,
        clearSelection: true,
      ));
}
