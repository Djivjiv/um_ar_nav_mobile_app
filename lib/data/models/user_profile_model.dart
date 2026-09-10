import '../../core/utils/json_utils.dart';

class UserProfileModel {
  final String id;
  final String? email;
  final String? fullName;

  /// Null until the user picks a role on the role-selection screen.
  final String? role;
  final bool isVerified;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? lastSeen;

  const UserProfileModel({
    required this.id,
    this.email,
    this.fullName,
    this.role,
    this.isVerified = false,
    this.isActive = true,
    this.createdAt,
    this.lastSeen,
  });

  String get roleLabel => (role ?? '').trim();

  bool get hasRole => roleLabel.isNotEmpty;

  bool get isAdmin => roleLabel.toLowerCase() == 'admin';

  /// Roles allowed to use the app once selected.
  bool get isAllowed {
    final r = roleLabel.toLowerCase();
    return r == 'student' || r == 'faculty' || r == 'employee';
  }

  String get displayName =>
      (fullName?.trim().isNotEmpty == true) ? fullName! : (email ?? 'User');

  factory UserProfileModel.fromMap(Map<String, dynamic> m) {
    return UserProfileModel(
      id: J.strOr(m['id']),
      email: J.str(m['email']),
      fullName: J.str(m['full_name']),
      role: J.str(m['role']),
      isVerified: J.boolOr(m['is_verified']),
      isActive: J.boolOr(m['is_active'], true),
      createdAt: J.date(m['created_at']),
      lastSeen: J.date(m['last_seen']),
    );
  }

  Map<String, dynamic> toInsert() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'role': role,
        'is_verified': isVerified,
        'is_active': isActive,
      };
}

class VisitorSessionModel {
  final String id;
  final String deviceId;
  final DateTime startedAt;
  final DateTime expiresAt;
  final bool isExpired;

  const VisitorSessionModel({
    required this.id,
    required this.deviceId,
    required this.startedAt,
    required this.expiresAt,
    this.isExpired = false,
  });

  Duration get remaining => expiresAt.difference(DateTime.now());

  bool get isStillValid => !isExpired && remaining > Duration.zero;

  factory VisitorSessionModel.fromMap(Map<String, dynamic> m) {
    return VisitorSessionModel(
      id: J.strOr(m['id']),
      deviceId: J.strOr(m['device_id']),
      startedAt: J.date(m['started_at']) ?? DateTime.now(),
      expiresAt: J.date(m['expires_at']) ??
          DateTime.now().add(const Duration(hours: 2)),
      isExpired: J.boolOr(m['is_expired']),
    );
  }
}
