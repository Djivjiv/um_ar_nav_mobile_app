import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/config/ar_nav_config.dart';

/// Pure geometry for the location-based AR overlay: building a dense route
/// polyline, snapping a GPS fix onto it, picking a look-ahead target and
/// smoothing GPS / compass input. No Flutter or Supabase dependencies, so it
/// is unit-testable.

const Distance _distance = Distance();

/// Metres per degree of latitude (mean Earth radius).
const double _metersPerDegree = 6371008.8 * math.pi / 180;

/// A dense route polyline with cumulative distances along it.
class DenseRoute {
  final List<LatLng> points;

  /// `cumulative[i]` = metres along the route from `points[0]` to `points[i]`.
  final List<double> cumulative;

  DenseRoute._(this.points, this.cumulative);

  factory DenseRoute.fromPoints(List<LatLng> points) {
    final cumulative = <double>[];
    var total = 0.0;
    for (var i = 0; i < points.length; i++) {
      if (i > 0) total += _distance.as(LengthUnit.Meter, points[i - 1], points[i]);
      cumulative.add(total);
    }
    return DenseRoute._(
      List.unmodifiable(points),
      List.unmodifiable(cumulative),
    );
  }

  bool get isEmpty => points.isEmpty;
  bool get isUsable => points.length >= 2;
  double get totalLength => cumulative.isEmpty ? 0 : cumulative.last;
  LatLng get end => points.last;

  /// The point [meters] along the route (clamped to the route), and the
  /// index of the segment it lies on.
  ({LatLng point, int segmentIndex}) pointAtDistance(double meters) {
    if (points.length < 2) {
      return (point: points.first, segmentIndex: 0);
    }
    final d = meters.clamp(0.0, totalLength);
    // Binary search for the last cumulative[i] <= d.
    var lo = 0, hi = points.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cumulative[mid] <= d) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final i = math.min(lo, points.length - 2);
    final segLen = cumulative[i + 1] - cumulative[i];
    final t = segLen <= 0 ? 0.0 : ((d - cumulative[i]) / segLen).clamp(0.0, 1.0);
    return (point: _lerp(points[i], points[i + 1], t), segmentIndex: i);
  }

  /// Projects [position] onto the nearest route segment.
  ///
  /// When [previousDistanceAlong] is given, segments near the previous snap
  /// are preferred (see [ArNavConfig.snapSearchBackMeters] etc.) so a route
  /// that doubles back past itself doesn't make the snap jump.
  SnapResult snap(LatLng position, {double? previousDistanceAlong}) {
    assert(isUsable, 'snap needs at least two points');

    SnapResult? globalBest;
    SnapResult? localBest;
    final windowStart = previousDistanceAlong == null
        ? null
        : previousDistanceAlong - ArNavConfig.snapSearchBackMeters;
    final windowEnd = previousDistanceAlong == null
        ? null
        : previousDistanceAlong + ArNavConfig.snapSearchAheadMeters;

    for (var i = 0; i < points.length - 1; i++) {
      final candidate = _projectOntoSegment(position, i);
      if (globalBest == null ||
          candidate.distanceFromRoute < globalBest.distanceFromRoute) {
        globalBest = candidate;
      }
      if (windowStart != null &&
          cumulative[i + 1] >= windowStart &&
          cumulative[i] <= windowEnd!) {
        if (localBest == null ||
            candidate.distanceFromRoute < localBest.distanceFromRoute) {
          localBest = candidate;
        }
      }
    }

    if (localBest != null &&
        localBest.distanceFromRoute <=
            globalBest!.distanceFromRoute + ArNavConfig.snapContinuityMeters) {
      return localBest;
    }
    return globalBest!;
  }

  /// The look-ahead target: the point [lookAheadMeters] beyond [snap] along
  /// the route (clamped to the route end).
  ({LatLng point, int segmentIndex}) lookAheadTarget(
    SnapResult snap, {
    double lookAheadMeters = ArNavConfig.lookAheadMeters,
  }) =>
      pointAtDistance(snap.distanceAlong + lookAheadMeters);

  SnapResult _projectOntoSegment(LatLng p, int i) {
    final a = points[i];
    final b = points[i + 1];
    // Local flat-earth projection centred on p (fine at campus scale).
    final cosLat = math.cos(p.latitude * math.pi / 180);
    double x(LatLng q) => (q.longitude - p.longitude) * cosLat * _metersPerDegree;
    double y(LatLng q) => (q.latitude - p.latitude) * _metersPerDegree;

    final ax = x(a), ay = y(a), bx = x(b), by = y(b);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    // p is the origin, so project (0,0) onto a→b.
    final t = len2 == 0 ? 0.0 : ((-ax * dx - ay * dy) / len2).clamp(0.0, 1.0);
    final px = ax + t * dx, py = ay + t * dy;
    final segLen = cumulative[i + 1] - cumulative[i];
    return SnapResult(
      segmentIndex: i,
      t: t,
      point: _lerp(a, b, t),
      distanceFromRoute: math.sqrt(px * px + py * py),
      distanceAlong: cumulative[i] + t * segLen,
    );
  }
}

/// Result of snapping a position onto a [DenseRoute].
class SnapResult {
  final int segmentIndex;

  /// 0–1 position within the segment.
  final double t;
  final LatLng point;
  final double distanceFromRoute;
  final double distanceAlong;

  const SnapResult({
    required this.segmentIndex,
    required this.t,
    required this.point,
    required this.distanceFromRoute,
    required this.distanceAlong,
  });
}

/// Densifies an arbitrary polyline with points every [spacingMeters] — the
/// AR fallback when the AR path network has no path for the trip.
DenseRoute densifyPolyline(
  List<LatLng> points, {
  double spacingMeters = ArNavConfig.fallbackPointSpacingMeters,
}) {
  if (points.length < 2) return DenseRoute.fromPoints(points);
  final out = <LatLng>[points.first];
  for (var i = 0; i < points.length - 1; i++) {
    out.addAll(interpolateSegment(points[i], points[i + 1], spacingMeters));
    out.add(points[i + 1]);
  }
  return DenseRoute.fromPoints(out);
}

/// Points strictly between [a] and [b], every [spacingMeters].
List<LatLng> interpolateSegment(LatLng a, LatLng b, double spacingMeters) {
  final length = _distance.as(LengthUnit.Meter, a, b);
  if (spacingMeters <= 0 || length <= spacingMeters) return const [];
  final count = (length / spacingMeters).floor();
  final out = <LatLng>[];
  for (var k = 1; k <= count; k++) {
    final t = k * spacingMeters / length;
    if (t >= 1) break;
    out.add(_lerp(a, b, t));
  }
  return out;
}

LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );

// ───────────────────────── angles ─────────────────────────

/// Initial compass bearing from [from] to [to], 0–360 (0 = north).
double bearingBetween(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLng = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Wraps an angle to (-180, 180].
double normalizeAngle180(double degrees) {
  final a = degrees % 360; // Dart's % is non-negative for a positive divisor.
  return a > 180 ? a - 360 : a;
}

/// Horizontal screen position of something at [relativeBearingDeg] (0 =
/// straight ahead, positive = right) for a pinhole camera with
/// [horizontalFovDeg]. Returns null when it is outside the field of view.
double? screenXForRelativeBearing(
  double relativeBearingDeg,
  double screenWidth, {
  double horizontalFovDeg = ArNavConfig.cameraHorizontalFovDeg,
}) {
  final half = horizontalFovDeg / 2;
  if (relativeBearingDeg.abs() > half) return null;
  final f = (screenWidth / 2) / math.tan(half * math.pi / 180);
  return screenWidth / 2 + f * math.tan(relativeBearingDeg * math.pi / 180);
}

// ───────────────────────── smoothing ─────────────────────────

/// Low-pass filter for compass headings using the unit-circle (sin/cos)
/// representation, so 359° → 1° is a 2° change, not 358°.
class HeadingSmoother {
  final double alpha;
  double? _sin;
  double? _cos;

  HeadingSmoother({this.alpha = ArNavConfig.headingSmoothingAlpha})
      : assert(alpha > 0 && alpha <= 1);

  /// Current smoothed heading, 0–360, or null before the first sample.
  double? get value {
    final s = _sin, c = _cos;
    if (s == null || c == null) return null;
    return (math.atan2(s, c) * 180 / math.pi + 360) % 360;
  }

  /// Feeds a raw heading (degrees) and returns the smoothed heading.
  double add(double headingDeg) {
    final r = headingDeg * math.pi / 180;
    final s = math.sin(r), c = math.cos(r);
    if (_sin == null || _cos == null) {
      _sin = s;
      _cos = c;
    } else {
      _sin = _sin! + alpha * (s - _sin!);
      _cos = _cos! + alpha * (c - _cos!);
    }
    return value!;
  }

  void reset() {
    _sin = null;
    _cos = null;
  }
}

/// Moving average of the last [window] GPS positions.
class PositionSmoother {
  final int window;
  final List<LatLng> _recent = [];

  PositionSmoother({this.window = ArNavConfig.gpsSmoothingWindow})
      : assert(window > 0);

  int get sampleCount => _recent.length;

  LatLng? get value {
    if (_recent.isEmpty) return null;
    var lat = 0.0, lng = 0.0;
    for (final p in _recent) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / _recent.length, lng / _recent.length);
  }

  LatLng add(LatLng position) {
    _recent.add(position);
    if (_recent.length > window) _recent.removeAt(0);
    return value!;
  }

  void reset() => _recent.clear();
}
