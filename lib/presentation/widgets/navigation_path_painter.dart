import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';

/// Darker, higher-contrast Google-Maps route blue used for polylines.
const Color kRouteBlue = Color(0xFF1A73E8);

/// Builds the flutter_map [Polyline]s for a route, colouring completed /
/// active / upcoming segments differently.
///
/// [activeSegment] is the index of the segment (point i → i+1) the user is
/// currently walking. Pass `0` on the map screen (whole route is "upcoming"
/// plus first segment active) or the live step index in turn-by-turn mode.
class NavigationPathPainter {
  NavigationPathPainter._();

  static List<Polyline> build(
    List<LatLng> path, {
    int activeSegment = 0,
    // When false, the bright active segment is omitted so a caller can draw
    // its own animated overlay for it (turn-by-turn marching ants).
    bool includeActive = true,
  }) {
    if (path.length < 2) return const [];

    final completed = <LatLng>[];
    final active = <LatLng>[];
    final upcoming = <LatLng>[];

    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i];
      final b = path[i + 1];
      if (i < activeSegment) {
        completed
          ..add(a)
          ..add(b);
      } else if (i == activeSegment) {
        active
          ..add(a)
          ..add(b);
      } else {
        upcoming
          ..add(a)
          ..add(b);
      }
    }

    return [
      if (upcoming.isNotEmpty)
        Polyline(
          points: _dedupe(path.sublist(
              (activeSegment + 1).clamp(0, path.length - 1), path.length)),
          strokeWidth: 4,
          color: kRouteBlue.withValues(alpha: 0.55),
          borderStrokeWidth: 1.5,
          borderColor: Colors.white.withValues(alpha: 0.7),
        ),
      if (completed.isNotEmpty)
        Polyline(
          points: path.sublist(0, (activeSegment + 1).clamp(0, path.length)),
          strokeWidth: 5,
          color: Colors.grey.withValues(alpha: 0.8),
          borderStrokeWidth: 1.5,
          borderColor: Colors.white,
        ),
      if (includeActive && active.isNotEmpty)
        Polyline(
          points: active,
          strokeWidth: 6,
          color: kRouteBlue,
          borderStrokeWidth: 2.5,
          borderColor: Colors.white,
        ),
    ];
  }

  static List<LatLng> _dedupe(List<LatLng> pts) => pts;

  /// Start (green pulsing) and end (maroon pin) markers.
  static List<Marker> endpointMarkers(List<LatLng> path) {
    if (path.isEmpty) return const [];
    return [
      Marker(
        point: path.first,
        width: 28,
        height: 28,
        child: const _PulsingDot(),
      ),
      Marker(
        point: path.last,
        width: 40,
        height: 40,
        alignment: Alignment.topCenter,
        child: const Icon(Icons.location_on,
            color: AppColors.primaryMaroon, size: 40),
      ),
    ];
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 28 * _c.value,
              height: 28 * _c.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.successGreen
                    .withValues(alpha: (1 - _c.value) * 0.5),
              ),
            ),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.successGreen,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ],
        );
      },
    );
  }
}
