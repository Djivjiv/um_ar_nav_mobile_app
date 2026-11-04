import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:um_ar_mobile_app/core/config/app_config.dart';
import 'package:um_ar_mobile_app/core/utils/screen_capture.dart';
import 'package:um_ar_mobile_app/presentation/screens/ar/ar_navigation_screen.dart';
import 'package:um_ar_mobile_app/presentation/widgets/dev_coordinate_panel.dart';

const clockChannel = MethodChannel('com.um.arnav/clock');

Position fix({double lat = 7.065123, double lng = 125.597654}) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026, 11, 1),
      accuracy: 4.2,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('screen capture block', () {
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(clockChannel, (call) async {
        calls.add(call);
        return null;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(clockChannel, null));

    test('is off by default', () {
      expect(kBlockScreenCapture, isFalse);
    });

    test('the constant is what Android receives', () async {
      await ScreenCapture.apply();

      expect(calls.single.method, 'setBlockScreenCapture');
      expect(calls.single.arguments, kBlockScreenCapture);
    });

    test('true reaches Android as true', () async {
      await ScreenCapture.apply(block: true);

      expect(calls.single.arguments, isTrue);
    });

    test('a platform without it, like iOS, does not stop the app', () async {
      messenger.setMockMethodCallHandler(clockChannel, null);

      await expectLater(ScreenCapture.apply(block: true), completes);
    });

    test('a failure on the Android side does not stop the app', () async {
      messenger.setMockMethodCallHandler(
          clockChannel, (_) async => throw PlatformException(code: 'no'));

      await expectLater(ScreenCapture.apply(block: true), completes);
    });

    test('Android listens for it on the same channel and sets FLAG_SECURE',
        () {
      final kotlin = File('android/app/src/main/kotlin/com/example/'
              'um_ar_mobile_app/MainActivity.kt')
          .readAsStringSync();

      expect(kotlin, contains('"com.um.arnav/clock"'));
      expect(kotlin, contains('"${ScreenCapture.method}"'));
      expect(kotlin, contains('FLAG_SECURE'));
    });

    test('the constant keeps its note', () {
      final config = File('lib/core/config/app_config.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');

      expect(
        config,
        contains('// Set to true right before deployment. Set back to false '
            'while gathering data and finishing the paper.\n'
            'const bool kBlockScreenCapture'),
      );
    });
  });

  group('coordinates panel', () {
    final copied = <String>[];

    setUp(() {
      copied.clear();
      DevCoordinatePanel.marks.value = const [];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    });
    tearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    Widget panel({double? lat = 7.065123, double? lng = 125.597654}) =>
        MaterialApp(
          home: Scaffold(
            body: DevCoordinatePanel(
              latitude: lat,
              longitude: lng,
              accuracy: lat == null ? null : 4.2,
              heading: lat == null ? null : 271.6,
            ),
          ),
        );

    test('is on in a debug build, off in a release build', () {
      expect(kDevCoordinateTools, kDebugMode);
      expect(kReleaseMode && kDevCoordinateTools, isFalse);
    });

    testWidgets('shows latitude, longitude, accuracy and heading',
        (tester) async {
      await tester.pumpWidget(panel());

      final text = find.textContaining('lat').evaluate().single.widget as Text;
      expect(text.data, contains('7.065123'));
      expect(text.data, contains('125.597654'));
      expect(text.data, contains('±4.2 m'));
      expect(text.data, contains('272°'));
    });

    testWidgets('Copy puts the coordinates on the clipboard', (tester) async {
      await tester.pumpWidget(panel());

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(copied, ['7.065123, 125.597654']);
    });

    testWidgets('with no fix yet there is nothing to copy or mark',
        (tester) async {
      await tester.pumpWidget(panel(lat: null, lng: null));

      for (final label in ['Copy', 'Mark point']) {
        await tester.tap(find.text(label), warnIfMissed: false);
      }
      await tester.pump();

      expect(copied, isEmpty);
      expect(DevCoordinatePanel.marks.value, isEmpty);
    });

    testWidgets('Mark point copies and keeps the point on screen',
        (tester) async {
      await tester.pumpWidget(panel());

      await tester.tap(find.text('Mark point'));
      await tester.pump();

      expect(copied, ['7.065123, 125.597654']);
      expect(find.text('7.065123, 125.597654'), findsOneWidget);

      await tester.tap(find.text('7.065123, 125.597654'));
      await tester.pump();
      expect(copied, hasLength(2));

      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(find.text('7.065123, 125.597654'), findsNothing);
    });

    testWidgets('the list stays short, newest first', (tester) async {
      for (var i = 0; i < DevCoordinatePanel.maxMarks + 3; i++) {
        await tester.pumpWidget(panel(lat: 7.0 + i / 1000));
        await tester.tap(find.text('Mark point'));
        await tester.pump();
      }

      final marks = DevCoordinatePanel.marks.value;
      expect(marks, hasLength(DevCoordinatePanel.maxMarks));
      expect(marks.first, startsWith('7.008000'));
    });

    testWidgets('marks survive leaving the screen', (tester) async {
      await tester.pumpWidget(panel());
      await tester.tap(find.text('Mark point'));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(panel(lat: 8, lng: 126));

      expect(find.text('7.065123, 125.597654'), findsOneWidget);
    });

    group('on a screen with no GPS of its own', () {
      testWidgets('reads the position on a timer and shows the compass',
          (tester) async {
        var reads = 0;
        final headings = StreamController<double?>.broadcast();
        addTearDown(headings.close);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: DevLiveCoordinatePanel(
              readPosition: () async {
                reads++;
                return fix(lat: 7 + reads / 1000);
              },
              headings: headings.stream,
            ),
          ),
        ));
        await tester.pump();
        expect(reads, 1);
        expect(find.textContaining('7.001000'), findsOneWidget);

        headings.add(90);
        await tester.pump();
        expect(find.textContaining('90°'), findsOneWidget);

        await tester.pump(DevLiveCoordinatePanel.interval);
        expect(reads, 2);
        expect(find.textContaining('7.002000'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('stops while another screen covers it, then resumes',
          (tester) async {
        var reads = 0;
        final headings = StreamController<double?>.broadcast();
        addTearDown(headings.close);
        final navigator = GlobalKey<NavigatorState>();

        await tester.pumpWidget(MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: DevLiveCoordinatePanel(
              readPosition: () async {
                reads++;
                return fix();
              },
              headings: headings.stream,
            ),
          ),
        ));
        await tester.pump();

        navigator.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('AR'))));
        await tester.pumpAndSettle();
        final covered = reads;

        await tester.pump(DevLiveCoordinatePanel.interval * 5);
        expect(reads, covered);
        expect(headings.hasListener, isFalse);

        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(reads, greaterThan(covered));
        expect(headings.hasListener, isTrue);

        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('a failed reading leaves the panel up', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: DevLiveCoordinatePanel(
              readPosition: () async => throw const PermissionDeniedException(
                  'denied'),
              headings: const Stream.empty(),
            ),
          ),
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.textContaining('lat  —'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      });
    });
  });

  group('the real AR screen', () {
    const compass = EventChannel('hemanthraj/flutter_compass');
    const accelerometer =
        EventChannel('dev.fluttercommunity.plus/sensors/accelerometer');
    const gpsUpdates = EventChannel('flutter.baseflow.com/geolocator_updates_android');

    setUp(() {
      for (final channel in [compass, accelerometer, gpsUpdates]) {
        messenger.setMockStreamHandler(
            channel, MockStreamHandler.inline(onListen: (_, _) {}));
      }
    });
    tearDown(() {
      for (final channel in [compass, accelerometer, gpsUpdates]) {
        messenger.setMockStreamHandler(channel, null);
      }
    });

    Future<void> pumpAr(WidgetTester tester, {required bool devTools}) async {
      await tester.pumpWidget(MaterialApp(
        home: ARNavigationScreen(
          routePoints: const <LatLng>[],
          fromName: 'Gate',
          toName: 'Library',
          distanceMeters: 0,
          destinationLatLng: const LatLng(7.06, 125.59),
          devTools: devTools,
        ),
      ));
      await tester.pump();
    }

    testWidgets('flag on: the panel shows and long-press opens tuning',
        (tester) async {
      await pumpAr(tester, devTools: true);

      expect(find.byType(DevCoordinatePanel), findsOneWidget);

      await tester.longPress(find.text('Library').first);
      await tester.pump();
      expect(find.textContaining('GPS acc'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('flag off: no panel, and long-press does nothing',
        (tester) async {
      await pumpAr(tester, devTools: false);

      expect(find.byType(DevCoordinatePanel), findsNothing);

      await tester.longPress(find.text('Library').first, warnIfMissed: false);
      await tester.pump();
      expect(find.textContaining('GPS acc'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
