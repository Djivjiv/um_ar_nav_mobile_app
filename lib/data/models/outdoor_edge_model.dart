import '../../core/utils/json_utils.dart';

class OutdoorEdgeModel {
  final String id;
  final String fromNode;
  final String toNode;
  final double weight;
  final bool isTwoWay;
  final bool isActive;

  const OutdoorEdgeModel({
    required this.id,
    required this.fromNode,
    required this.toNode,
    this.weight = 1,
    this.isTwoWay = true,
    this.isActive = true,
  });

  factory OutdoorEdgeModel.fromMap(Map<String, dynamic> m) {
    return OutdoorEdgeModel(
      id: J.strOr(m['id']),
      fromNode: J.strOr(m['from_node']),
      toNode: J.strOr(m['to_node']),
      weight: J.dblOr(m['weight'], 1),
      isTwoWay: J.boolOr(m['is_two_way'], true),
      isActive: J.boolOr(m['is_active'], true),
    );
  }
}
