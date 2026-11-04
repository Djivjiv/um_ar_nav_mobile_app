import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../data/models/building_model.dart';
import '../../data/models/facility_model.dart';
import '../../core/utils/text_utils.dart';
import '../../data/models/room_model.dart';

/// What the AR information card shows for one place. Every field is
/// already cleaned: null / empty means "don't show that line".
class ArPlaceInfo {
  final String title;

  /// True for the trip's destination, false for the nearest building.
  final bool isDestination;
  final String? description;
  final String? hours;
  final String? contact;
  final List<String> services;
  final List<String> instructions;

  /// An access restriction in friendly words ("Staff only"), or null when
  /// open to all. Never the raw `access_level` value.
  final String? access;

  const ArPlaceInfo({
    required this.title,
    required this.isDestination,
    this.description,
    this.hours,
    this.contact,
    this.services = const [],
    this.instructions = const [],
    this.access,
  });

  bool get isEmpty =>
      description == null &&
      hours == null &&
      contact == null &&
      services.isEmpty &&
      instructions.isEmpty &&
      access == null;
}

/// Max list lines on the card, so it stays compact.
const int arInfoMaxServices = 4;
const int arInfoMaxInstructions = 3;

/// The card appears this close to a place, and stays until the user is
/// [arInfoKeepMeters] away, so GPS jitter at the edge doesn't make it flicker.
const double arInfoNearMeters = 60;
const double arInfoKeepMeters = 80;

/// `access_level` values that mean "no restriction" (not shown).
const Set<String> _openAccess = {
  'public', 'open', 'all', 'everyone', 'none', 'general', 'any', 'free',
  'n/a', 'na', '-',
};

/// The stored `access_level` values and their wording on the card.
const Map<String, String> _accessLabels = {
  'students_and_faculty': 'Students and faculty only',
  'staff_only': 'Staff only',
};

/// Shown for any other stored value (older free text): it is a restriction
/// we have no wording for, and the raw text must not reach the screen.
const String arAccessRestricted = 'Restricted access';

List<String> _cleanList(Iterable<String> items, int max) {
  final seen = <String>{};
  final out = <String>[];
  for (final i in items) {
    final t = i.trim();
    if (t.isEmpty || !seen.add(t.toLowerCase())) continue;
    out.add(t);
    if (out.length == max) break;
  }
  return out;
}

String? _cleanJoined(Iterable<String> parts) =>
    cleanText(parts.map((p) => p.trim()).where((p) => p.isNotEmpty).join(' '));

/// The friendly wording of an access level, or null when it means "open to
/// all" or is missing.
String? accessRestriction(String? level) {
  final t = cleanText(level)?.toLowerCase();
  if (t == null || _openAccess.contains(t)) return null;
  return _accessLabels[t] ?? arAccessRestricted;
}

/// The card for a trip / location:
///
/// - destination is a facility ([placeType] `'facility'`, [placeId]) in
///   [facilities] → its name, description, office hours, contact, services
///   and instructions (`facility_details`) and `access_level`;
/// - destination is a room in [rooms] → its description, hours, contact,
///   services and `access_level`;
/// - otherwise the [building] → its description, opening hours and contact.
///
/// Room / facility hours and contact fall back to the building's. Returns
/// null when there is nothing to show (the card stays hidden).
ArPlaceInfo? selectArPlaceInfo({
  required BuildingModel? building,
  required bool isDestination,
  String? placeType,
  String? placeId,
  List<RoomModel> rooms = const [],
  List<FacilityModel> facilities = const [],
}) {
  final id = int.tryParse(placeId ?? '');
  final bHours = cleanText(building?.openingHours);
  final bContact = cleanText(building?.contact);

  ArPlaceInfo? info;
  if (placeType == 'facility' && id != null) {
    final f = facilities.where((f) => f.id == id).firstOrNull;
    if (f != null) {
      final d = f.details;
      info = ArPlaceInfo(
        title: f.roomName,
        isDestination: isDestination,
        description: _cleanJoined(f.description),
        hours: cleanText(d?.officeHours) ?? cleanText(f.officeHours) ?? bHours,
        contact: cleanText(d?.contactNumber) ?? bContact,
        services: _cleanList(d?.services ?? const [], arInfoMaxServices),
        instructions:
            _cleanList(d?.instructions ?? const [], arInfoMaxInstructions),
        access: accessRestriction(f.accessLevel),
      );
    }
  } else if (placeType == 'room' && id != null) {
    final r = rooms.where((r) => r.id == id).firstOrNull;
    if (r != null) {
      info = ArPlaceInfo(
        title: r.label,
        isDestination: isDestination,
        description: cleanText(r.description),
        hours: cleanText(r.openingHours) ?? bHours,
        contact: cleanText(r.contact) ?? bContact,
        services: _cleanList(r.services, arInfoMaxServices),
        access: accessRestriction(r.accessLevel),
      );
    }
  }

  if (info == null && building != null) {
    info = ArPlaceInfo(
      title: building.label,
      isDestination: isDestination,
      description: _cleanJoined(building.description),
      hours: bHours,
      contact: bContact,
    );
  }
  if (info == null || info.isEmpty || cleanText(info.title) == null) return null;
  return info;
}

/// The building the card should be about at [position], or null when none is
/// close. [currentId] is the one on the card now, kept to [arInfoKeepMeters].
/// [destinationId]'s distance is the smaller of its own centre and
/// [metersToDestination] (the end of the route), as a large building's
/// entrance can be far from its centre.
BuildingModel? arInfoBuilding({
  required List<BuildingModel> buildings,
  required LatLng position,
  int? destinationId,
  double? metersToDestination,
  int? currentId,
}) {
  const distance = Distance();
  double metersTo(BuildingModel b) {
    final d = distance.as(LengthUnit.Meter, position, b.location);
    return b.id == destinationId && metersToDestination != null
        ? math.min(d, metersToDestination)
        : d;
  }

  BuildingModel? best;
  var bestD = double.infinity;
  for (final b in buildings) {
    final d = metersTo(b);
    if (b.id == currentId && d <= arInfoKeepMeters) return b;
    if (d < bestD) {
      bestD = d;
      best = b;
    }
  }
  return bestD <= arInfoNearMeters ? best : null;
}

/// Space the direction arrow and its text take on the AR view.
const double arDirectionHeight = 130;

/// Top of the direction arrow: its usual place, or higher when the bottom
/// panel (with the information card) would reach it. Never above 36% of the
/// screen, where it would run into the target marker.
double arDirectionTop(double screenHeight, double bottomPanelHeight) {
  final clear = screenHeight - bottomPanelHeight - arDirectionHeight;
  return math.max(screenHeight * 0.36, math.min(screenHeight * 0.52, clear));
}

