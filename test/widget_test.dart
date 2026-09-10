import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_mobile_app/core/theme/app_theme.dart';
import 'package:um_ar_mobile_app/core/utils/geofence_service.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';

void main() {
  test('SUS score is computed from the standard formula', () {
    // All "3" answers => neutral => SUS 50.
    final neutral = List<int>.filled(10, 3);
    expect(SurveyRepository.calculateSusScore(neutral), 50);

    // Best possible: odd=5, even=1 => 100.
    final best = [5, 1, 5, 1, 5, 1, 5, 1, 5, 1];
    expect(SurveyRepository.calculateSusScore(best), 100);
  });

  test('geofence: campus center is inside, distant point is outside', () {
    // Matina campus center.
    expect(GeofenceService.isInsideCampus(7.0673125, 125.5951125), isTrue);
    // Downtown Davao, ~5 km away.
    expect(GeofenceService.isInsideCampus(7.0731, 125.6128), isFalse);
    // Far outside the bounding box.
    expect(GeofenceService.isInsideCampus(0, 0), isFalse);
  });

  testWidgets('app theme builds a MaterialApp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Center(child: Text('UM-AR Nav'))),
      ),
    );
    expect(find.text('UM-AR Nav'), findsOneWidget);
  });
}
