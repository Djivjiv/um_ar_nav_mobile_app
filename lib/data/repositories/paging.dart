/// Supabase returns at most 1000 rows per request by default — fetch every
/// page of a query. [page] must apply a stable `.order(...)` and
/// `.range(from, to)`.
Future<List<dynamic>> fetchAllPages(
  Future<List<dynamic>> Function(int from, int to) page, {
  int pageSize = 1000,
}) async {
  final out = <dynamic>[];
  var from = 0;
  while (true) {
    final rows = await page(from, from + pageSize - 1);
    out.addAll(rows);
    if (rows.length < pageSize) return out;
    from += pageSize;
  }
}
