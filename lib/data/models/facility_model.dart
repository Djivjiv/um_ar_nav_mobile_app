import '../../core/utils/json_utils.dart';

class FacilityModel {
  final int id;
  final int buildingId;
  final String roomName;
  final String? roomNumber;
  final String? floor;
  final String? facilityCategories;
  final List<String> description;
  final String? location;
  final String? officeHours;
  final FacilityDetailsModel? details;

  const FacilityModel({
    required this.id,
    required this.buildingId,
    required this.roomName,
    this.roomNumber,
    this.floor,
    this.facilityCategories,
    this.description = const [],
    this.location,
    this.officeHours,
    this.details,
  });

  factory FacilityModel.fromMap(Map<String, dynamic> m,
      {FacilityDetailsModel? details}) {
    return FacilityModel(
      id: J.intOr(m['id']),
      buildingId: J.intOr(m['building_id']),
      roomName: J.strOr(m['roomname'], 'Facility'),
      roomNumber: J.str(m['room_number']),
      floor: J.str(m['floor']),
      facilityCategories: J.str(m['facility_categories']),
      description: J.strList(m['description']),
      location: J.str(m['location']),
      officeHours: J.str(m['office_hours']),
      details: details,
    );
  }
}

class FacilityDetailsModel {
  final int id;
  final int facilityId;
  final String? contactNumber;
  final List<String> services;
  final List<String> paymentMethods;
  final List<String> instructions;
  final String? officeHours;

  const FacilityDetailsModel({
    required this.id,
    required this.facilityId,
    this.contactNumber,
    this.services = const [],
    this.paymentMethods = const [],
    this.instructions = const [],
    this.officeHours,
  });

  factory FacilityDetailsModel.fromMap(Map<String, dynamic> m) {
    return FacilityDetailsModel(
      id: J.intOr(m['id']),
      facilityId: J.intOr(m['facility_id']),
      contactNumber: J.str(m['contact_number']),
      services: J.strList(m['services']),
      paymentMethods: J.strList(m['payment_method']),
      instructions: J.strList(m['instructions']),
      officeHours: J.str(m['office_hours']),
    );
  }
}
