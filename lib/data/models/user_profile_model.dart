import '../../core/utils/json_utils.dart';

/// Whether an account may use the app. The admin app rejects an account by
/// clearing both `is_verified` and `is_active`, and deactivates one by
/// clearing `is_active` alone.
enum AccountAccess { allowed, needsRole, pending, rejected, inactive }

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

  AccountAccess get access {
    if (!isActive) {
      return isVerified ? AccountAccess.inactive : AccountAccess.rejected;
    }
    if (!hasRole) return AccountAccess.needsRole;
    return isVerified || isAdmin
        ? AccountAccess.allowed
        : AccountAccess.pending;
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
