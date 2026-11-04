/// What visitors can do, in one place, so every screen says the same.
class VisitorText {
  VisitorText._();

  /// Shown wherever a visitor is told about their access.
  static const String access =
      'Visitor access is limited: there is no 2D indoor map, and each session '
      'lasts 2 hours. You still get the outdoor map, AR, and written indoor '
      'directions.';

  /// Shown in the indoor part of a route instead of the map.
  static const String indoorMessage =
      'For the full 2D map and easier directions, log in with your UM '
      'account, or use a campus kiosk for a detailed directory.';
}
