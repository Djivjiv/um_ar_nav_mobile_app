/// Thrown by repositories when a Supabase call fails or returns bad data.
class RepositoryException implements Exception {
  final String message;
  RepositoryException(this.message);
  @override
  String toString() => message;
}
