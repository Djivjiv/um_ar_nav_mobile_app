import '../../core/utils/json_utils.dart';

class IndoorEdgeModel {
  final String id;
  final String fromNode;
  final String toNode;
  final String? floorPlanId;
  final double weight;
  final bool isTwoWay;
  final bool isActive;

  const IndoorEdgeModel({
    required this.id,
    required this.fromNode,
    required this.toNode,
    this.floorPlanId,
    this.weight = 1,
    this.isTwoWay = true,
    this.isActive = true,
  });

  factory IndoorEdgeModel.fromMap(Map<String, dynamic> m) {
    return IndoorEdgeModel(
      id: J.strOr(m['id']),
      fromNode: J.strOr(m['from_node']),
      toNode: J.strOr(m['to_node']),
      floorPlanId: J.str(m['floor_plan_id']),
      weight: J.dblOr(m['weight'], 1),
      isTwoWay: J.boolOr(m['is_two_way'], true),
      isActive: J.boolOr(m['is_active'], true),
    );
  }
}
