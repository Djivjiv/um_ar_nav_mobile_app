/// Small helpers for defensively parsing Supabase JSON rows.
class J {
  J._();

  static String? str(dynamic v) => v?.toString();

  static String strOr(dynamic v, [String fallback = '']) =>
      v?.toString() ?? fallback;

  static int? intN(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static int intOr(dynamic v, [int fallback = 0]) => intN(v) ?? fallback;

  static double? dbl(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static double dblOr(dynamic v, [double fallback = 0]) => dbl(v) ?? fallback;

  static bool boolOr(dynamic v, [bool fallback = false]) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
    return fallback;
  }

  /// Parses a Postgres/JSON array (or a comma / brace string) into `List<String>`.
  static List<String> strList(dynamic v) {
    if (v == null) return const [];
    if (v is List) {
      return v.where((e) => e != null).map((e) => e.toString()).toList();
    }
    var s = v.toString().trim();
    if (s.isEmpty) return const [];
    if (s.startsWith('{') && s.endsWith('}')) {
      s = s.substring(1, s.length - 1);
    }
    if (s.startsWith('[') && s.endsWith(']')) {
      s = s.substring(1, s.length - 1);
    }
    if (s.isEmpty) return const [];
    return s
        .split(',')
        .map((e) => e.trim().replaceAll('"', '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static DateTime? date(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
