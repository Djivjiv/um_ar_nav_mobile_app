/// Characters with meaning inside a PostgREST `.or('a.ilike.%x%,b...')`
/// filter string: commas separate conditions, parentheses group them, and
/// double quotes / backslashes quote and escape values.
final RegExp _reserved = RegExp(r'[,()"\\]+');

/// Makes free text safe to embed in an `ilike` pattern inside a PostgREST
/// `.or(...)` filter. Reserved characters become `%` wildcards, so
/// "Room 101 (Lab)" still matches that room instead of breaking the filter.
/// Returns '' when nothing searchable is left.
String sanitizeIlikeTerm(String input) {
  final cleaned = input
      .trim()
      .replaceAll(_reserved, '%')
      .replaceAll(RegExp('%+'), '%');
  return cleaned.replaceAll('%', '').trim().isEmpty ? '' : cleaned;
}
