import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/core/utils/indoor_route_helpers.dart';
import 'package:um_ar_mobile_app/data/models/floor_plan_model.dart';

FloorPlanModel plan(int floor) =>
    FloorPlanModel(id: floor * 10, buildingId: 1, floorNumber: floor);

void main() {
  group('pickIndoorFloorPlans', () {
    test('uses the exact origin and destination floors', () {
      final r = pickIndoorFloorPlans(
        floors: [plan(1), plan(2), plan(3)],
        originFloor: 1,
        destFloor: 3,
      );
      expect(r.error, isNull);
      expect(r.start!.floorNumber, 1);
      expect(r.dest!.floorNumber, 3);
    });

    test('a missing destination floor is an error, not the top floor', () {
      final r = pickIndoorFloorPlans(
        floors: [plan(1), plan(2), plan(4)],
        originFloor: 1,
        destFloor: 3,
      );
      expect(r.dest, isNull);
      expect(r.error, contains('Floor 3'));
    });

    test('a missing destination floor is an error even on a same-floor trip',
        () {
      final r = pickIndoorFloorPlans(
        floors: [plan(1), plan(2)],
        originFloor: 3,
        destFloor: 3,
      );
      expect(r.dest, isNull);
      expect(r.error, isNotNull);
    });

    test('the ground floor maps to the lowest plan (floor 0 buildings)', () {
      final r = pickIndoorFloorPlans(
        floors: [plan(0), plan(2)],
        originFloor: 1,
        destFloor: 1,
      );
      expect(r.error, isNull);
      expect(r.start!.floorNumber, 0);
      expect(r.dest!.floorNumber, 0);
    });

    test('coming in from outside starts on the lowest floor', () {
      final r = pickIndoorFloorPlans(
        floors: [plan(2), plan(1)],
        originFloor: 1,
        destFloor: 2,
      );
      expect(r.start!.floorNumber, 1);
      expect(r.dest!.floorNumber, 2);
    });

    test('no floor plans at all is an error', () {
      final r = pickIndoorFloorPlans(
        floors: const [],
        originFloor: 1,
        destFloor: 2,
      );
      expect(r.start, isNull);
      expect(r.error, 'No floor plan is available for this building.');
    });
  });
}
