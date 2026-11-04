/// [s] trimmed, or null when nothing is left.
String? cleanText(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}
