import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/device_utils.dart';
import '../../../core/utils/uuid.dart';
import '../../../data/repositories/outdoor_navigation_repository.dart';
import '../auth/auth_cubit.dart';

/// How a trip was guided.
abstract final class TripMode {
  static const String twoD = '2d';
  static const String ar = 'ar';
}

/// Evaluation metrics derived from stored trip data.
abstract final class NavigationMetrics {
  /// Navigation error rate = errors (off-route events + reroutes) ÷ total
  /// route steps. Null when the trip had no steps (rate undefined).
  static double? errorRate(int errorCount, int totalSteps) =>
      totalSteps <= 0 ? null : errorCount / totalSteps;
}

/// Writes `navigation_sessions` rows for one trip, all sharing [tripId]:
///
/// - [start] inserts a `row_type = 'start'` row;
/// - [complete] / [abandon] insert ONE `row_type = 'end'` row with the
///   outcome, `duration_seconds`, `error_count` (off-route events +
///   reroutes), `reroute_count`, `total_steps` and `completed_manually`.
///
/// Both rows carry the install's random `device_code`.
///
/// Insert-only on purpose (no update of the start row), so it works with an
/// insert-only RLS policy. A trip with a start row but no end row was cut
/// off (app killed). See `supabase/navigation_evaluation.sql` for the
/// per-trip view that computes the error rate.
///
/// Analytics must never break navigation: every failure is swallowed.
class NavigationSessionLogger {
  /// The trip id of the most recently COMPLETED trip in this app run — used
  /// to link a SUS response when the survey is opened without one.
  static String? lastCompletedTripId;

  /// Where rows go (the write queue); null logs nothing.
  final Future<void> Function(Map<String, dynamic> row)? sink;

  /// The install's `device_code`; a row is still sent if this fails.
  final Future<String> Function()? deviceCode;
  final DateTime Function() _now;
  final String? userId;
  final String? visitorSessionId;

  /// Client-generated UUID shared by this trip's rows (and the SUS link).
  final String tripId;

  /// [TripMode.twoD] or [TripMode.ar].
  final String mode;
  final String fromNode;
  final String toNode;
  final String fromName;
  final String toName;
  final double distanceMeters;

  /// Turn-by-turn steps of the route as planned (the error-rate
  /// denominator). Can be raised once later legs (indoor floors) are known.
  int totalSteps;

  DateTime? _startedAt;
  bool _ended = false;
  int _errorCount = 0;
  int _rerouteCount = 0;
  bool _offRouteTracked = false;

  NavigationSessionLogger({
    required this.sink,
    required this.mode,
    required this.fromNode,
    required this.toNode,
    required this.fromName,
    required this.toName,
    this.distanceMeters = 0,
    this.totalSteps = 0,
    this.userId,
    this.visitorSessionId,
    this.deviceCode,
    String? tripId,
    DateTime Function()? now,
  })  : tripId = tripId ?? uuidV4(),
        _now = now ?? DateTime.now;

  /// Builds a logger from the signed-in user / visitor in [context]. Never
  /// throws — with no repository available it simply logs nothing.
  factory NavigationSessionLogger.of(
    BuildContext context, {
    required String mode,
    required String fromNode,
    required String toNode,
    required String fromName,
    required String toName,
    double? distanceMeters,
    int totalSteps = 0,
  }) {
    OutdoorNavigationRepository? repo;
    String? userId;
    String? visitorId;
    try {
      repo = context.read<OutdoorNavigationRepository>();
      final auth = context.read<AuthCubit>().state;
      if (auth is AuthAuthenticated) {
        userId = Supabase.instance.client.auth.currentUser?.id;
      } else if (auth is AuthVisitor && !auth.session.id.startsWith('local-')) {
        visitorId = auth.session.id;
      }
    } catch (e) {
      debugPrint('NavigationSessionLogger setup: $e');
    }
    return NavigationSessionLogger(
      sink: repo?.logNavigationRow,
      deviceCode: DeviceUtils.getDeviceCode,
      mode: mode,
      userId: userId,
      visitorSessionId: visitorId,
      fromNode: fromNode,
      toNode: toNode,
      fromName: fromName,
      toName: toName,
      distanceMeters: distanceMeters ?? 0,
      totalSteps: totalSteps,
    );
  }

  int get errorCount => _errorCount;
  int get rerouteCount => _rerouteCount;
  bool get ended => _ended;

  /// Off-route detection ran on this trip (GPS readings were usable).
  void markOffRouteTracked() => _offRouteTracked = true;

  /// One error: a deviation from the route (a new off-route event).
  void recordOffRoute() {
    if (_ended) return;
    _offRouteTracked = true;
    _errorCount++;
  }

  /// One error: the route was recalculated. A reroute that follows an
  /// off-route event counts as well; `reroute_count` keeps them apart.
  void recordReroute() {
    if (_ended) return;
    _rerouteCount++;
    _errorCount++;
  }

  Future<void> start() async {
    if (_startedAt != null) return;
    _startedAt = _now();
    await _send(buildRow(rowType: 'start', completed: false));
  }

  /// The user arrived. [manual] = they confirmed it themselves ("I have
  /// arrived") because GPS never reached the arrival radius. At most once.
  Future<void> complete({bool manual = false}) async {
    if (_ended) return;
    _ended = true;
    lastCompletedTripId = tripId;
    await _send(buildRow(rowType: 'end', completed: true, manual: manual));
  }

  /// The trip was left without arriving. Ignored after [complete] or when
  /// the trip never started.
  Future<void> abandon() async {
    if (_ended || _startedAt == null) return;
    _ended = true;
    await _send(buildRow(rowType: 'end', completed: false));
  }

  /// One `navigation_sessions` row. Timestamps are taken now, not when a
  /// queued row is finally sent.
  @visibleForTesting
  Map<String, dynamic> buildRow({
    required String rowType,
    required bool completed,
    bool manual = false,
  }) {
    final now = _now();
    final started = _startedAt ?? now;
    final isEnd = rowType == 'end';
    return {
      'trip_id': tripId,
      'row_type': rowType,
      'mode': mode,
      'user_id': userId,
      'visitor_session_id': visitorSessionId,
      'from_node': fromNode,
      'to_node': toNode,
      'from_name': fromName,
      'to_name': toName,
      'distance_meters': distanceMeters,
      'total_steps': totalSteps,
      'started_at': started.toUtc().toIso8601String(),
      'completed': completed,
      if (isEnd) ...{
        'duration_seconds': now.difference(started).inSeconds,
        'completed_manually': completed && manual,
        'error_count': _errorCount,
        'reroute_count': _rerouteCount,
        'off_route_tracked': _offRouteTracked,
      },
      if (completed) 'completed_at': now.toUtc().toIso8601String(),
    };
  }

  Future<void> _send(Map<String, dynamic> row) async {
    final sink = this.sink;
    if (sink == null) return;
    try {
      final code = await _loadDeviceCode();
      await sink({...row, 'device_code': ?code});
    } catch (e) {
      debugPrint('Navigation analytics failed: $e');
    }
  }

  Future<String?> _loadDeviceCode() async {
    try {
      return await deviceCode?.call();
    } catch (e) {
      debugPrint('Device code unavailable: $e');
      return null;
    }
  }

  /// A node id for an endpoint map (`indoor_node_id`, else `type:id`).
  static String endpointId(Map<String, dynamic> endpoint) {
    final indoor = endpoint['indoor_node_id']?.toString();
    if (indoor != null && indoor.isNotEmpty) return indoor;
    final type = endpoint['type']?.toString() ?? 'place';
    return '$type:${endpoint['id'] ?? 'unknown'}';
  }

  /// The trip id handed to the survey route (`extra`), read defensively:
  /// a UUID string, or a map with `navigation_session_id`. Anything else
  /// falls back to [lastCompletedTripId].
  static String? tripIdFromRouteExtra(Object? extra) {
    final value = extra is Map ? extra['navigation_session_id'] : extra;
    if (isUuid(value)) return value as String;
    return isUuid(lastCompletedTripId) ? lastCompletedTripId : null;
  }
}
