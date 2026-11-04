import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:um_ar_mobile_app/data/models/building_model.dart';
import 'package:um_ar_mobile_app/data/models/facility_model.dart';
import 'package:um_ar_mobile_app/data/models/room_model.dart';
import 'package:um_ar_mobile_app/domain/services/ar_info_overlay.dart';
import 'package:um_ar_mobile_app/presentation/widgets/ar_info_card.dart';

const building = BuildingModel(
  id: 5,
  name: 'BE Building',
  lat: 7.0670,
  lng: 125.5950,
  openingHours: '7:00 AM – 9:00 PM',
  contact: '082 123 4567',
);

final cashier = FacilityModel(
  id: 11,
  buildingId: 5,
  roomName: 'Cashier',
  description: ['Tuition and fees.', ' ', 'Second window.'],
  officeHours: '8–5',
  accessLevel: 'students_and_faculty',
  details: const FacilityDetailsModel(
    id: 1,
    facilityId: 11,
    officeHours: '8:00 AM – 4:00 PM',
    contactNumber: 'local 201',
    services: ['Tuition', ' ', 'Tuition', 'Clearance', 'IDs', 'Refunds', 'Extra'],
    instructions: ['Bring your study load', 'Queue at window 2', 'No food',
        'Fourth'],
  ),
);

const lab = RoomModel(
  id: 21,
  buildingId: 5,
  roomName: 'Computer Lab 3',
  accessLevel: 'staff_only',
  services: ['Printing'],
  description: 'Forty workstations.',
);

const lobby = RoomModel(
  id: 22,
  buildingId: 5,
  roomName: 'Lobby',
  accessLevel: 'Public',
  openingHours: '  ',
);

void main() {
  group('selectArPlaceInfo', () {
    test('facility destination: facility_details first, lists trimmed', () {
      final i = selectArPlaceInfo(
        building: building,
        isDestination: true,
        placeType: 'facility',
        placeId: '11',
        facilities: [cashier],
      )!;
      expect(i.title, 'Cashier');
      expect(i.hours, '8:00 AM – 4:00 PM', reason: 'details beat facility');
      expect(i.contact, 'local 201');
      expect(i.services, ['Tuition', 'Clearance', 'IDs', 'Refunds'],
          reason: 'blank + duplicate removed, max 4');
      expect(i.instructions, hasLength(arInfoMaxInstructions));
      expect(i.description, 'Tuition and fees. Second window.');
      expect(i.access, 'Students and faculty only');
      expect(i.isDestination, isTrue);
    });

    test('room destination: access level, building hours as fallback', () {
      final i = selectArPlaceInfo(
        building: building,
        isDestination: true,
        placeType: 'room',
        placeId: '21',
        rooms: const [lab, lobby],
      )!;
      expect(i.title, 'Computer Lab 3');
      expect(i.description, 'Forty workstations.');
      expect(i.access, 'Staff only');
      expect(i.hours, building.openingHours);
      expect(i.contact, building.contact);
      expect(i.services, ['Printing']);
    });

    test('"Public" access is not shown as a restriction', () {
      final i = selectArPlaceInfo(
        building: building,
        isDestination: true,
        placeType: 'room',
        placeId: '22',
        rooms: const [lobby],
      )!;
      expect(i.access, isNull);
      expect(i.hours, building.openingHours, reason: 'blank room hours');
    });

    test('unknown place or building destination → building card', () {
      for (final type in ['facility', 'room', 'building', null]) {
        final i = selectArPlaceInfo(
          building: building,
          isDestination: false,
          placeType: type,
          placeId: '999',
        )!;
        expect(i.title, 'BE Building');
        expect(i.isDestination, isFalse);
        expect(i.services, isEmpty);
        expect(i.access, isNull);
      }
    });

    test('nothing to show → null (card hidden)', () {
      const bare = BuildingModel(id: 1, name: 'Shed', lat: 7, lng: 125);
      expect(selectArPlaceInfo(building: bare, isDestination: true), isNull);
      expect(selectArPlaceInfo(building: null, isDestination: true), isNull);
    });

    test('a building card carries its description', () {
      const b = BuildingModel(
          id: 2, name: 'Library', lat: 7, lng: 125, description: ['Books.']);
      final i = selectArPlaceInfo(building: b, isDestination: false)!;
      expect(i.description, 'Books.');
      expect(i.hours, isNull);
      expect(i.contact, isNull);
      expect(ArInfoCard.summary(i), 'Books.');
    });

    test('blank details and a blank name → null, never an error', () {
      const blanks = BuildingModel(
        id: 1,
        name: 'Shed',
        lat: 7,
        lng: 125,
        openingHours: '  ',
        contact: '',
        description: [' ', ''],
      );
      expect(selectArPlaceInfo(building: blanks, isDestination: true), isNull);

      const noName = BuildingModel(
          id: 1, name: ' ', lat: 7, lng: 125, openingHours: '8–5');
      expect(selectArPlaceInfo(building: noName, isDestination: true), isNull);
    });

    test('a room with nothing filled in falls back to the building', () {
      const bare = RoomModel(id: 30, buildingId: 5, roomName: 'Store');
      final i = selectArPlaceInfo(
        building: const BuildingModel(id: 5, name: 'BE', lat: 7, lng: 125),
        isDestination: true,
        placeType: 'room',
        placeId: '30',
        rooms: const [bare],
      );
      expect(i, isNull, reason: 'only a name: nothing to tell the user');
    });
  });

  group('friendly access wording', () {
    test('the stored levels', () {
      expect(accessRestriction('public'), isNull);
      expect(accessRestriction('students_and_faculty'),
          'Students and faculty only');
      expect(accessRestriction('staff_only'), 'Staff only');
      expect(accessRestriction(' STAFF_ONLY '), 'Staff only');
    });

    test('open or missing values get no label', () {
      for (final v in ['public', 'Open', ' ALL ', 'none', '', '  ', null]) {
        expect(accessRestriction(v), isNull, reason: '$v');
      }
    });

    test('anything else is never shown raw', () {
      for (final v in ['Faculty only', 'dean_office', 'Restricted']) {
        expect(accessRestriction(v), arAccessRestricted, reason: v);
      }
    });

    testWidgets('the card never prints the raw value', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ArInfoCard(
            info: selectArPlaceInfo(
              building: building,
              isDestination: true,
              placeType: 'room',
              placeId: '21',
              rooms: const [lab],
            )!,
            expanded: true,
            onToggle: () {},
            onClose: () {},
          ),
        ),
      ));

      expect(find.text('Staff only'), findsOneWidget);
      expect(find.textContaining('staff_only'), findsNothing);
      expect(find.textContaining('Access:'), findsNothing);
    });
  });

  group('arInfoBuilding: the card appears near a place', () {
    const library =
        BuildingModel(id: 7, name: 'Library', lat: 7.0700, lng: 125.5950);

    BuildingModel? near(
      LatLng here, {
      int? destinationId,
      double? metersToDestination,
      int? currentId,
    }) =>
        arInfoBuilding(
          buildings: const [building, library],
          position: here,
          destinationId: destinationId,
          metersToDestination: metersToDestination,
          currentId: currentId,
        );

    test('nothing nearby → no card, even for the destination', () {
      expect(near(const LatLng(7.0685, 125.5950), destinationId: 5), isNull);
    });

    test('a building passed on the way', () {
      expect(near(const LatLng(7.0701, 125.5950), destinationId: 5)?.id, 7);
    });

    test('the destination, by the end of the route', () {
      final b = near(const LatLng(7.0685, 125.5950),
          destinationId: 5, metersToDestination: 20);
      expect(b?.id, 5);
    });

    test('kept a little past the limit, so it does not flicker', () {
      const edge = LatLng(7.06765, 125.5950); // about 72 m from BE Building
      expect(near(edge), isNull);
      expect(near(edge, currentId: 5)?.id, 5);
      expect(near(const LatLng(7.0685, 125.5950), currentId: 5), isNull);
    });
  });

  group('arDirectionTop: the arrow stays clear of the bottom panel', () {
    test('its usual place when there is room', () {
      expect(arDirectionTop(900, 212), 900 * 0.52);
    });

    test('moves up when the card makes the panel taller', () {
      const h = 700.0, panel = 276.0;
      final top = arDirectionTop(h, panel);
      expect(top, lessThan(h * 0.52));
      expect(top + arDirectionHeight, lessThanOrEqualTo(h - panel));
    });

    test('an open card still clears the arrow on a 700 px phone', () {
      const h = 700.0, panel = 288.0;
      expect(arDirectionTop(h, panel) + arDirectionHeight,
          lessThanOrEqualTo(h - panel));
    });

    test('never climbs into the target marker', () {
      expect(arDirectionTop(700, 600), 700 * 0.36);
    });
  });

  test('facilities.access_level is read defensively', () {
    expect(FacilityModel.fromMap({'id': 1}).accessLevel, isNull);
    expect(FacilityModel.fromMap({'id': 1, 'access_level': 'Staff'}).accessLevel,
        'Staff');
  });


  testWidgets('card: collapsed summary, expand, close', (tester) async {
    var expanded = false;
    var closed = false;
    final info = selectArPlaceInfo(
      building: building,
      isDestination: true,
      placeType: 'facility',
      placeId: '11',
      facilities: [cashier],
    )!;
    Future<void> pump() => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ArInfoCard(
              info: info,
              expanded: expanded,
              onToggle: () => expanded = !expanded,
              onClose: () => closed = true,
            ),
          ),
        ));

    await pump();
    expect(find.textContaining('Cashier'), findsOneWidget);
    expect(find.textContaining('Students and faculty only'), findsOneWidget);
    expect(find.text('local 201'), findsNothing, reason: 'collapsed');

    await tester.tap(find.textContaining('Cashier'));
    await pump();
    expect(find.text('local 201'), findsOneWidget);
    expect(find.text('Queue at window 2'), findsOneWidget);
    expect(find.text('Tuition and fees. Second window.'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide information'));
    expect(closed, isTrue);
  });
}
