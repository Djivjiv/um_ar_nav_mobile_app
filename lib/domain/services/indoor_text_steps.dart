/// The 2D screen's step text, without its map: for those who get written
/// directions only.
///
/// [steps] are the steps of one floor, in order. The last of them only says
/// "you have arrived", because on the map the last stretch is plain to see, so
/// [lastWalk] is listed in its place and [finish] (arrival, or the stairs to
/// the next floor) after it. [landmarks] are the named places where each step
/// begins, if any.
List<String> indoorTextSteps({
  required List<String> steps,
  required String finish,
  String? lastWalk,
  List<String?> landmarks = const [],
}) {
  if (steps.isEmpty) return const [];
  return [
    for (var i = 0; i < steps.length - 1; i++)
      _atLandmark(steps[i], i < landmarks.length ? landmarks[i] : null),
    ?lastWalk == null
        ? null
        : _atLandmark(
            lastWalk,
            steps.length - 1 < landmarks.length
                ? landmarks[steps.length - 1]
                : null),
    finish,
  ];
}

final RegExp _turn = RegExp(r'^((?:Turn|Bear|Sharp) (?:left|right))(,.*)$');

/// "Turn left, continue 5m" → "Turn left at Room 201, continue 5m".
String _atLandmark(String step, String? landmark) {
  if (landmark == null || landmark.isEmpty) return step;
  return step.replaceFirstMapped(
      _turn, (m) => '${m[1]} at $landmark${m[2]}');
}

/// The closing step of a floor when the trip continues on another one.
String changeFloorStep(String transport, int? floor) =>
    'Take the $transport to Floor ${floor ?? ''}'.trim();

/// The closing step of the trip.
String arrivalStep(String? place) =>
    place == null || place.trim().isEmpty
        ? 'You have arrived!'
        : 'You have arrived at $place';
