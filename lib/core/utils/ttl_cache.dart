/// A small in-memory cache whose entries expire after [ttl].
///
/// [now] is injectable so expiry can be unit-tested without waiting.
class TtlCache<K, V> {
  final Duration ttl;
  final DateTime Function() _now;
  final Map<K, ({V value, DateTime storedAt})> _entries = {};

  TtlCache({required this.ttl, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// The cached value for [key], or null when absent or older than [ttl].
  V? get(K key) {
    final e = _entries[key];
    if (e == null) return null;
    if (_now().difference(e.storedAt) >= ttl) {
      _entries.remove(key);
      return null;
    }
    return e.value;
  }

  void put(K key, V value) =>
      _entries[key] = (value: value, storedAt: _now());

  void clear() => _entries.clear();
}
