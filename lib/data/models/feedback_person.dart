import 'user_profile_model.dart';

/// Who is giving feedback: a signed-in user, known by [userId], or a visitor,
/// known by the install's `device_code`. Holds no name, email or location.
class FeedbackPerson {
  static const String visitorRole = 'visitor';

  /// Null for a visitor.
  final String? userId;

  /// student, faculty, employee or visitor.
  final String role;

  const FeedbackPerson.visitor()
      : userId = null,
        role = visitorRole;

  FeedbackPerson.user(UserProfileModel user)
      : userId = user.id,
        role = user.roleLabel.toLowerCase();
}
