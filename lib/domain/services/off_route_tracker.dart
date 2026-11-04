import '../../core/config/ar_nav_config.dart';

/// Turns a stream of "distance from the route" readings into off-route
/// state and a count of separate off-route events (navigation errors).
///
/// Hysteresis: the user goes off route above [enterMeters] and is back on
/// route only below [exitMeters], so GPS jitter around the limit counts as
/// one deviation, not many. Readings with worse than [maxAccuracyMeters]
/// GPS accuracy are ignored (a poor fix is not a user error).
class OffRouteTracker {
  final double enterMeters;
  final double exitMeters;
  final double maxAccuracyMeters;

  OffRouteTracker({
    this.enterMeters = ArNavConfig.offRouteMeters,
    this.exitMeters =
        ArNavConfig.offRouteMeters - ArNavConfig.offRouteHysteresisMeters,
    this.maxAccuracyMeters = ArNavConfig.offRouteMaxAccuracyMeters,
  }) : assert(exitMeters <= enterMeters);

  bool _offRoute = false;
  int _events = 0;
  bool _tracked = false;

  bool get offRoute => _offRoute;

  /// Separate times the user left the route.
  int get events => _events;

  /// True once at least one usable reading was processed — false means
  /// off-route errors were never measured on this trip.
  bool get tracked => _tracked;

  /// Feeds one reading. Returns true when it starts a NEW off-route event.
  bool update(double distanceFromRoute, {double? accuracyMeters}) {
    if (accuracyMeters != null && accuracyMeters > maxAccuracyMeters) {
      return false;
    }
    _tracked = true;
    if (_offRoute) {
      if (distanceFromRoute < exitMeters) _offRoute = false;
      return false;
    }
    if (distanceFromRoute > enterMeters) {
      _offRoute = true;
      _events++;
      return true;
    }
    return false;
  }

  /// Back on a (new) route — after a re-route or on arrival. Keeps the count.
  void reset() => _offRoute = false;
}
