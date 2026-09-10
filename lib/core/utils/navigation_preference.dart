/// A one-shot hand-off for a route destination selected on one screen
/// (e.g. the Places tab) and consumed on the Map screen when it opens.
class NavigationPreference {
  NavigationPreference._();

  static Map<String, dynamic>? _pendingDestination;

  static void setDestination(Map<String, dynamic> destination) {
    _pendingDestination = destination;
  }

  /// Returns the pending destination once, then clears it.
  static Map<String, dynamic>? getAndClear() {
    final dest = _pendingDestination;
    _pendingDestination = null;
    return dest;
  }

  static bool get hasPendingDestination => _pendingDestination != null;
}
