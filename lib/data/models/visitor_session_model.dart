import '../../core/utils/server_clock.dart';

/// A visitor's 2-hour session. [startedAt] and [expiresAt] are the server's
/// times, and [clock] is the server's time now, so the phone's clock plays no
/// part in whether it is still valid.
class VisitorSessionModel {
  final String id;
  final String deviceCode;
  final DateTime startedAt;
  final DateTime expiresAt;
  final bool isExpired;
  final ServerClock clock;

  const VisitorSessionModel({
    required this.id,
    required this.deviceCode,
    required this.startedAt,
    required this.expiresAt,
    required this.clock,
    this.isExpired = false,
  });

  Duration get remaining => expiresAt.difference(clock.now);

  bool get isStillValid => !isExpired && remaining > Duration.zero;

  VisitorSessionModel copyWith({DateTime? expiresAt, bool? isExpired}) =>
      VisitorSessionModel(
        id: id,
        deviceCode: deviceCode,
        startedAt: startedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        clock: clock,
        isExpired: isExpired ?? this.isExpired,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'device_code': deviceCode,
        'started_at': startedAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'is_expired': isExpired,
        'clock': clock.toJson(),
      };

  /// Rebuilds a saved session, or null when [json] is unusable.
  static VisitorSessionModel? fromJson(
    Map<String, dynamic> json, {
    ClockSource source = const ClockSource(),
  }) {
    final started = DateTime.tryParse(json['started_at']?.toString() ?? '');
    final expires = DateTime.tryParse(json['expires_at']?.toString() ?? '');
    final rawClock = json['clock'];
    final clock = rawClock is Map
        ? ServerClock.fromJson(rawClock.cast<String, dynamic>(), source: source)
        : null;
    final id = json['id']?.toString();
    final code = json['device_code']?.toString();
    if (started == null ||
        expires == null ||
        clock == null ||
        id == null ||
        code == null) {
      return null;
    }
    return VisitorSessionModel(
      id: id,
      deviceCode: code,
      startedAt: started.toUtc(),
      expiresAt: expires.toUtc(),
      clock: clock,
      isExpired: json['is_expired'] == true,
    );
  }
}
