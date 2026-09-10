import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/outdoor_node_model.dart';

/// A single human-readable step in a turn-by-turn route.
class NavigationInstruction {
  /// One of: straight, left, right, slight_left, slight_right,
  /// sharp_left, sharp_right, uturn, arrive.
  final String direction;
  final double distanceMeters;
  final String landmark;
  final LatLng fromPoint;
  final LatLng toPoint;
  final IconData directionIcon;
  final String instructionText;

  /// Compass bearing (degrees, 0 = north) the traveller faces on this step.
  final double bearing;

  /// Every route point covered by this (merged) step, in order.
  final List<LatLng> segmentPoints;

  /// Index range into the full route this step spans (`fromIndex`..`toIndex`).
  final int fromIndex;
  final int toIndex;

  const NavigationInstruction({
    required this.direction,
    required this.distanceMeters,
    required this.landmark,
    required this.fromPoint,
    required this.toPoint,
    required this.directionIcon,
    required this.instructionText,
    required this.bearing,
    this.segmentPoints = const [],
    this.fromIndex = 0,
    this.toIndex = 0,
  });
}

class InstructionService {
  InstructionService._();

  static const Distance _distance = Distance();

  /// Converts a poly-line [path] into an ordered list of instructions,
  /// **merging** consecutive route points that keep the same heading into one
  /// step. A new step starts only when the heading changes (a turn), the
  /// running segment passes [_maxSegmentMeters], or the route ends. This turns
  /// a 20-point path into ~5–7 meaningful steps instead of 20 tiny ones.
  static List<NavigationInstruction> generateInstructions(
    List<LatLng> path,
    List<OutdoorNodeModel> nodes, {
    String destinationName = 'your destination',
  }) {
    if (path.length < 2) return const [];

    final instructions = <NavigationInstruction>[];

    var segmentStart = 0;
    var segmentDistance = 0.0;
    var currentDirection = 'straight';

    void flush(int endIndex, {required bool isLast}) {
      final segPoints = path.sublist(segmentStart, endIndex + 1);
      final headingRef =
          math.min(segmentStart + 1, path.length - 1);
      final landmark = _landmarkNear(path[endIndex], nodes);
      instructions.add(NavigationInstruction(
        direction: currentDirection,
        distanceMeters: segmentDistance,
        landmark: landmark,
        fromPoint: path[segmentStart],
        toPoint: path[endIndex],
        directionIcon: iconFor(currentDirection),
        instructionText: _text(currentDirection, segmentDistance, landmark),
        bearing: _bearing(path[segmentStart], path[headingRef]),
        segmentPoints: segPoints,
        fromIndex: segmentStart,
        toIndex: endIndex,
      ));
      segmentStart = endIndex;
      segmentDistance = 0;
    }

    for (var i = 1; i < path.length; i++) {
      segmentDistance +=
          _distance.as(LengthUnit.Meter, path[i - 1], path[i]);
      final isLast = i == path.length - 1;

      final turnHere = isLast
          ? 'straight'
          : _turnFromDiff(_angleDiff(
              _bearing(path[i - 1], path[i]),
              _bearing(path[i], path[i + 1]),
            ));

      final directionChanged =
          turnHere != 'straight' && turnHere != currentDirection;
      final tooLong = segmentDistance > _maxSegmentMeters;

      if (isLast) {
        flush(i, isLast: true);
      } else if (directionChanged || tooLong) {
        flush(i, isLast: false);
        currentDirection = directionChanged ? turnHere : 'straight';
      }
    }

    // Final "arrive" step.
    final last = path.last;
    instructions.add(NavigationInstruction(
      direction: 'arrive',
      distanceMeters: 0,
      landmark: destinationName,
      fromPoint: last,
      toPoint: last,
      directionIcon: iconFor('arrive'),
      instructionText: 'You have arrived at $destinationName',
      bearing: instructions.isNotEmpty ? instructions.last.bearing : 0,
      segmentPoints: [last],
      fromIndex: path.length - 1,
      toIndex: path.length - 1,
    ));

    return instructions;
  }

  /// A running straight segment longer than this is split so steps stay useful.
  static const double _maxSegmentMeters = 150;

  static IconData iconFor(String direction) {
    switch (direction) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight_left':
        return Icons.turn_slight_left;
      case 'slight_right':
        return Icons.turn_slight_right;
      case 'sharp_left':
        return Icons.turn_sharp_left;
      case 'sharp_right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      case 'arrive':
        return Icons.location_on;
      case 'straight':
      default:
        return Icons.arrow_upward;
    }
  }

  static String label(String direction) {
    switch (direction) {
      case 'left':
        return 'Turn left';
      case 'right':
        return 'Turn right';
      case 'slight_left':
        return 'Slight left';
      case 'slight_right':
        return 'Slight right';
      case 'sharp_left':
        return 'Sharp left';
      case 'sharp_right':
        return 'Sharp right';
      case 'uturn':
        return 'Make a U-turn';
      case 'arrive':
        return 'Arrive';
      case 'straight':
      default:
        return 'Go straight';
    }
  }

  // ── helpers ───────────────────────────────────────────────

  static String _turnFromDiff(double diff) {
    if (diff <= -150 || diff >= 150) return 'uturn';
    if (diff < -120) return 'sharp_left';
    if (diff < -60) return 'left';
    if (diff < -15) return 'slight_left';
    if (diff < 15) return 'straight';
    if (diff < 60) return 'slight_right';
    if (diff < 120) return 'right';
    return 'sharp_right';
  }

  static String _text(String direction, double dist, String landmark) {
    final d = dist >= 1000
        ? '${(dist / 1000).toStringAsFixed(1)}km'
        : '${dist.round()}m';
    if (direction == 'straight') {
      return landmark.isNotEmpty
          ? 'Go straight for $d toward $landmark'
          : 'Go straight for $d';
    }
    final verb = label(direction);
    if (landmark.isNotEmpty) {
      return '$verb at $landmark, continue $d';
    }
    return '$verb, continue $d';
  }

  /// Initial bearing from [a] to [b] in degrees (0–360, 0 = north).
  static double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitudeInRad;
    final lat2 = b.latitudeInRad;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final brng = math.atan2(y, x) * 180 / math.pi;
    return (brng + 360) % 360;
  }

  /// Signed smallest angle from [from] to [to], range (-180, 180].
  static double _angleDiff(double from, double to) {
    var diff = (to - from + 540) % 360 - 180;
    return diff;
  }

  static String _landmarkNear(LatLng point, List<OutdoorNodeModel> nodes) {
    OutdoorNodeModel? best;
    double bestDist = 18; // metres
    for (final n in nodes) {
      if (n.name == null || n.name!.trim().isEmpty) continue;
      final d = _distance.as(LengthUnit.Meter, point, n.point);
      if (d < bestDist) {
        bestDist = d;
        best = n;
      }
    }
    return best?.name ?? '';
  }
}
