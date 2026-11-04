import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/domain/services/indoor_text_steps.dart';

void main() {
  group('indoorTextSteps', () {
    test('the last walk replaces "you have arrived", then the finish', () {
      expect(
        indoorTextSteps(
          steps: ['Go straight for 20m', 'Turn left, continue 5m', 'You have arrived!'],
          lastWalk: 'Turn right, continue 8m',
          finish: 'You have arrived at Room 7',
        ),
        [
          'Go straight for 20m',
          'Turn left, continue 5m',
          'Turn right, continue 8m',
          'You have arrived at Room 7',
        ],
      );
    });

    test('a walk too short to mention is left out', () {
      expect(
        indoorTextSteps(
          steps: ['Go straight for 20m', 'You have arrived!'],
          finish: 'You have arrived!',
        ),
        ['Go straight for 20m', 'You have arrived!'],
      );
    });

    test('a turn at a named place says so', () {
      expect(
        indoorTextSteps(
          steps: ['Go straight for 20m', 'Turn left, continue 5m', 'x'],
          landmarks: ['Lobby', 'Room 201', 'Room 301'],
          lastWalk: 'Bear right, continue 2m',
          finish: 'done',
        ),
        [
          'Go straight for 20m', // not a turn
          'Turn left at Room 201, continue 5m',
          'Bear right at Room 301, continue 2m',
          'done',
        ],
      );
    });

    test('no steps, nothing to list', () {
      expect(indoorTextSteps(steps: const [], finish: 'done'), isEmpty);
    });
  });

  test('closing steps', () {
    expect(changeFloorStep('stairs', 2), 'Take the stairs to Floor 2');
    expect(changeFloorStep('elevator', 3), 'Take the elevator to Floor 3');
    expect(arrivalStep('Room 7'), 'You have arrived at Room 7');
    expect(arrivalStep(null), 'You have arrived!');
    expect(arrivalStep('  '), 'You have arrived!');
  });
}
