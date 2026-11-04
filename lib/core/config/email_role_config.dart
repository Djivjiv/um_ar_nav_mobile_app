/// What a school email address says about its owner.
enum SchoolEmailKind { student, faculty, other }

/// The school email formats, in one place.
class EmailRoleConfig {
  EmailRoleConfig._();

  /// `first initial.lastname.idnumber@umindanao.edu.ph`. The database has the
  /// same rule in `is_student_email()` (admin app, db/user_roles.sql): change
  /// both together.
  static final RegExp studentPattern = RegExp(
      r'^[a-z]\.[a-z]+(-[a-z]+)*\.[0-9]+@umindanao\.edu\.ph$');

  /// The faculty format. STILL TO BE CONFIRMED, so null: nothing is treated
  /// as faculty yet. Once set, a matching email is never an automatic student
  /// and the role picker starts on Faculty; the account is still approved by
  /// an admin. If it overlaps [studentPattern], `is_student_email()` needs
  /// the same exclusion.
  static final RegExp? facultyPattern = null;

  /// The faculty format wins, so it can carve addresses out of the student
  /// one. [faculty] replaces [facultyPattern] in tests.
  static SchoolEmailKind classify(String? email, {RegExp? faculty}) {
    final e = (email ?? '').trim().toLowerCase();
    if ((faculty ?? facultyPattern)?.hasMatch(e) ?? false) {
      return SchoolEmailKind.faculty;
    }
    return studentPattern.hasMatch(e)
        ? SchoolEmailKind.student
        : SchoolEmailKind.other;
  }
}
