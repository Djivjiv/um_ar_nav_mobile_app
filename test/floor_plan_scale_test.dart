import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/data/models/floor_plan_model.dart';

void main() {
  group('metres per pixel', () {
    test('meters_per_pixel wins over scale_factor', () {
      expect(
        FloorPlanModel.resolveMetersPerPixel(
            metersPerPixel: 0.08, scaleFactor: 0.02),
        0.08,
      );
    });

    test('falls back to a metres-like scale_factor', () {
      expect(
        FloorPlanModel.resolveMetersPerPixel(scaleFactor: 0.03),
        0.03,
      );
      expect(
        FloorPlanModel.resolveMetersPerPixel(
            metersPerPixel: 0, scaleFactor: 0.03),
        0.03,
      );
    });

    test('ignores a legacy 1.0 scale_factor and uses the default', () {
      expect(
        FloorPlanModel.resolveMetersPerPixel(scaleFactor: 1),
        FloorPlanModel.defaultMetersPerPixel,
      );
      expect(FloorPlanModel.resolveMetersPerPixel(),
          FloorPlanModel.defaultMetersPerPixel);
    });

    test('rejects non-positive or non-finite meters_per_pixel', () {
      for (final bad in [-1.0, 0.0, double.nan, double.infinity]) {
        expect(
          FloorPlanModel.resolveMetersPerPixel(metersPerPixel: bad),
          FloorPlanModel.defaultMetersPerPixel,
          reason: '$bad',
        );
      }
    });

    test('a row without the meters_per_pixel column still parses', () {
      final row = <String, dynamic>{
        'id': 1,
        'building_id': 2,
        'floor_number': 1,
        'scale_factor': 1.0,
      };
      expect(FloorPlanModel.metersPerPixelFromRow(row),
          FloorPlanModel.defaultMetersPerPixel);
      final plan = FloorPlanModel.fromMap(row);
      expect(plan.metersPerPixel, isNull);
      expect(plan.effectiveMetersPerPixel,
          FloorPlanModel.defaultMetersPerPixel);
    });

    test('a row with meters_per_pixel uses it (numeric or string)', () {
      final row = <String, dynamic>{
        'id': 1,
        'building_id': 2,
        'floor_number': 3,
        'scale_factor': 1.0,
        'meters_per_pixel': '0.042',
      };
      expect(FloorPlanModel.metersPerPixelFromRow(row), 0.042);
      expect(FloorPlanModel.fromMap(row).effectiveMetersPerPixel, 0.042);
    });
  });
}
