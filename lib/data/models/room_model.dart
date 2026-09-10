import '../../core/utils/json_utils.dart';

class RoomModel {
  final int id;
  final int buildingId;
  final String roomName;
  final String? shortName;
  final String? floor;
  final String? type;
  final String? accessLevel;
  final String? openingHours;
  final String? contact;
  final List<String> services;
  final List<String> paymentMethods;
  final String? description;
  final List<String> imageUrls;

  const RoomModel({
    required this.id,
    required this.buildingId,
    required this.roomName,
    this.shortName,
    this.floor,
    this.type,
    this.accessLevel,
    this.openingHours,
    this.contact,
    this.services = const [],
    this.paymentMethods = const [],
    this.description,
    this.imageUrls = const [],
  });

  String get label => shortName?.isNotEmpty == true ? shortName! : roomName;

  factory RoomModel.fromMap(Map<String, dynamic> m) {
    return RoomModel(
      id: J.intOr(m['id']),
      buildingId: J.intOr(m['building_id']),
      roomName: J.strOr(m['roomname'], 'Room'),
      shortName: J.str(m['short_name']),
      floor: J.str(m['floor']),
      type: J.str(m['type']),
      accessLevel: J.str(m['access_level']),
      openingHours: J.str(m['opening_hours']),
      contact: J.str(m['contact']),
      services: J.strList(m['services']),
      paymentMethods: J.strList(m['payment_methods']),
      description: J.str(m['description']),
      imageUrls: J.strList(m['image_url']),
    );
  }
}
