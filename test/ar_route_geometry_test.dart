import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:um_ar_mobile_app/domain/services/ar_route_geometry.dart';

/// Campus-area origin; test geometry is laid out in metres from here.
const _origin = LatLng(7.0673, 125.5951);
const _mPerDeg = 6371008.8 * math.pi / 180;
const _distance = Distance();

LatLng at(double eastM, double northM) {
  final lat = _origin.latitude + northM / _mPerDeg;
  final lng = _origin.longitude +
      eastM / (_mPerDeg * math.cos(_origin.latitude * math.pi / 180));
  return LatLng(lat, lng);
}

double metersBetween(LatLng a, LatLng b) =>
    _distance.as(LengthUnit.Meter, a, b);

/// Smallest absolute angle between two headings, degrees.
double angularGap(double a, double b) => normalizeAngle180(a - b).abs();

void main() {
  group('snapping', () {
    final straight = DenseRoute.fromPoints([at(0, 0), at(50, 0), at(100, 0)]);

    test('projects a point beside the route onto it', () {
      final s = straight.snap(at(30, 5));
      expect(s.distanceFromRoute, closeTo(5, 0.2));
      expect(s.distanceAlong, closeTo(30, 0.2));
      expect(s.segmentIndex, 0);
      expect(metersBetween(s.point, at(30, 0)), lessThan(0.2));
    });

    test('clamps to the route start when the user is behind it', () {
      final s = straight.snap(at(-10, 0));
      expect(s.distanceAlong, closeTo(0, 0.01));
      expect(s.distanceFromRoute, closeTo(10, 0.2));
    });

    test('picks the nearest leg of an L-shaped route', () {
      final l = DenseRoute.fromPoints([at(0, 0), at(50, 0), at(50, 50)]);
      final s = l.snap(at(52, 20));
      expect(s.segmentIndex, 1);
      expect(s.distanceFromRoute, closeTo(2, 0.2));
      expect(s.distanceAlong, closeTo(70, 0.3));
    });

    test('prefers the stretch near the previous snap on a route that '
        'doubles back past itself', () {
      // Out east along y=0, step north 4 m, back west along y=4.
      final loop = DenseRoute.fromPoints(
          [at(0, 0), at(100, 0), at(100, 4), at(0, 4)]);
      final user = at(30, 2); // 2 m from both legs

      final outbound = loop.snap(user, previousDistanceAlong: 28);
      expect(outbound.segmentIndex, 0);
      expect(outbound.distanceAlong, closeTo(30, 0.3));

      final inbound = loop.snap(user, previousDistanceAlong: 172);
      expect(inbound.segmentIndex, 2);
      expect(inbound.distanceAlong, closeTo(174, 0.3));
    });
  });

  group('look-ahead target', () {
    test('sits lookAhead metres further along a straight route', () {
      final r = DenseRoute.fromPoints([at(0, 0), at(100, 0)]);
      final t = r.lookAheadTarget(r.snap(at(30, 3)), lookAheadMeters: 12);
      expect(metersBetween(t.point, at(42, 0)), lessThan(0.3));
    });

    test('follows the route around a corner instead of cutting it', () {
      final r = DenseRoute.fromPoints([at(0, 0), at(50, 0), at(50, 50)]);
      final t = r.lookAheadTarget(r.snap(at(45, 0)), lookAheadMeters: 12);
      // 5 m to the corner, then 7 m north along the second leg.
      expect(t.segmentIndex, 1);
      expect(metersBetween(t.point, at(50, 7)), lessThan(0.3));
    });

    test('clamps to the route end', () {
      final r = DenseRoute.fromPoints([at(0, 0), at(100, 0)]);
      final t = r.lookAheadTarget(r.snap(at(95, 0)), lookAheadMeters: 12);
      expect(metersBetween(t.point, at(100, 0)), lessThan(0.05));
    });

    test('advances as the user moves', () {
      final r = DenseRoute.fromPoints([at(0, 0), at(50, 0), at(50, 50)]);
      var prev = -1.0;
      for (var x = 0.0; x <= 50; x += 5) {
        final s = r.snap(at(x, 1));
        final t = r.lookAheadTarget(s, lookAheadMeters: 12);
        final along = s.distanceAlong + 12;
        expect(along, greaterThan(prev));
        prev = along;
        expect(r.snap(t.point).distanceFromRoute, lessThan(0.05));
      }
    });
  });

  group('route points with 6 m fill-in (AR fallback)', () {
    test('fills a straight hop every 6 m', () {
      final r = densifyPolyline([at(0, 0), at(30, 0)], spacingMeters: 6);
      // 0, 6, 12, 18, 24, 30
      expect(r.points.length, 6);
      for (var i = 1; i < r.points.length; i++) {
        expect(metersBetween(r.points[i - 1], r.points[i]), closeTo(6, 0.05));
      }
      expect(r.totalLength, closeTo(30, 0.1));
    });

    test('keeps every original corner', () {
      final corner = at(30, 0);
      final r = densifyPolyline([at(0, 0), corner, at(30, 18)]);
      expect(r.points.any((p) => metersBetween(p, corner) < 0.01), isTrue);
      expect(metersBetween(r.points.last, at(30, 18)), lessThan(0.01));
      expect(r.totalLength, closeTo(48, 0.2));
    });

    test('short hops get no extra points', () {
      final r = densifyPolyline([at(0, 0), at(4, 0)]);
      expect(r.points.length, 2);
    });
  });

  group('heading smoothing', () {
    test('the first sample passes through unchanged', () {
      expect(HeadingSmoother(alpha: 0.2).add(123), closeTo(123, 1e-9));
    });

    test('averaging 350° and 10° gives 0°, not 180°', () {
      final s = HeadingSmoother(alpha: 0.5)..add(350);
      final v = s.add(10);
      expect(angularGap(v, 0), lessThan(0.5));
    });

    test('crossing north stays on the short arc and converges', () {
      final s = HeadingSmoother(alpha: 0.2)..add(350);
      double v = 350;
      for (var i = 0; i < 60; i++) {
        v = s.add(10);
        // Never swings the long way round through south.
        expect(angularGap(v, 0), lessThanOrEqualTo(10.0001));
      }
      expect(angularGap(v, 10), lessThan(0.1));
    });

    test('jitter around 0/360 stays near north', () {
      final s = HeadingSmoother(alpha: 0.3);
      for (final h in [358.0, 2.0, 359.0, 1.0, 357.0, 3.0]) {
        expect(angularGap(s.add(h), 0), lessThan(3.5));
      }
    });

    test('normalizeAngle180 wraps into (-180, 180]', () {
      expect(normalizeAngle180(190), closeTo(-170, 1e-9));
      expect(normalizeAngle180(-190), closeTo(170, 1e-9));
      expect(normalizeAngle180(360), closeTo(0, 1e-9));
      expect(normalizeAngle180(180), closeTo(180, 1e-9));
      expect(normalizeAngle180(-180), closeTo(180, 1e-9));
    });
  });

  group('position smoothing and FOV projection', () {
    test('averages only the last N fixes', () {
      final s = PositionSmoother(window: 2)
        ..add(at(0, 0))
        ..add(at(10, 0));
      expect(metersBetween(s.value!, at(5, 0)), lessThan(0.05));
      s.add(at(20, 0)); // drops the first fix
      expect(metersBetween(s.value!, at(15, 0)), lessThan(0.05));
      expect(s.sampleCount, 2);
    });

    test('maps relative bearing to screen x inside the FOV only', () {
      expect(screenXForRelativeBearing(0, 400, horizontalFovDeg: 60), 200);
      expect(screenXForRelativeBearing(30, 400, horizontalFovDeg: 60),
          closeTo(400, 1e-6));
      expect(screenXForRelativeBearing(-30, 400, horizontalFovDeg: 60),
          closeTo(0, 1e-6));
      expect(screenXForRelativeBearing(31, 400, horizontalFovDeg: 60), isNull);
      expect(
          screenXForRelativeBearing(-45, 400, horizontalFovDeg: 60), isNull);
    });

    test('bearingBetween points east for an eastward hop', () {
      expect(angularGap(bearingBetween(at(0, 0), at(10, 0)), 90),
          lessThan(0.1));
    });
  });
}
