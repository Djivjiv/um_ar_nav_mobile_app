import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:um_ar_mobile_app/data/repositories/feedback_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/outdoor_navigation_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:um_ar_mobile_app/presentation/screens/ar/unity_ar_screen.dart';
import 'package:um_ar_mobile_app/presentation/widgets/feedback_comment_card.dart';
import 'package:um_ar_mobile_app/services/unity_bridge_service.dart';

import 'support/feedback_fakes.dart';
import 'support/visitor_fakes.dart';

/// Stands in for the native Unity player, which isn't in this repo.
class FakeUnity implements UnityBridgeService {
  FakeUnity({this.available = true});

  final bool available;
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  int starts = 0;
  int stops = 0;

  void send(Map<String, dynamic> event) => controller.add(event);

  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> startOutdoorNavigation(Map<String, dynamic> data) async {
    starts++;
    return true;
  }

  @override
  Future<bool> startIndoorNavigation(Map<String, dynamic> data) async {
    starts++;
    return true;
  }

  @override
  Future<bool> stopNavigation() async {
    stops++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RowRecorder implements OutdoorNavigationRepository {
  final rows = <Map<String, dynamic>>[];
  @override
  Future<void> logNavigationRow(Map<String, dynamic> row) async => rows.add(row);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const rate = 'Rate your experience';
const arrived = 'You have arrived';
const openUnity = 'open';

void main() {
  late FeedbackWorld world;
  late RowRecorder trips;
  late Object? surveyExtra;
  late GoRouter router;

  setUp(() async {
    await FeedbackWorld.resetPhone();
    world = FeedbackWorld();
    trips = RowRecorder();
    surveyExtra = null;
  });

  /// A small app with the routes the arrival leaves through, and the Unity
  /// screen pushed on the root navigator as the map and AR tabs do it.
  Future<void> pumpTrip(WidgetTester tester, FakeUnity unity,
      {AuthState? auth}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(unity.controller.close);

    router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                builder: (_) => UnityArScreen(
                  bridge: unity,
                  routePoints: const [
                    LatLng(7.066, 125.594),
                    LatLng(7.067, 125.595),
                  ],
                  buildingId: '1',
                  destinationName: 'Library',
                ),
              ),
            ),
            child: const Text(openUnity),
          ),
        ),
      ),
      GoRoute(
        path: '/survey',
        builder: (_, state) {
          surveyExtra = state.extra;
          return const Text('survey');
        },
      ),
      GoRoute(path: '/map', builder: (_, _) => const Text('map')),
    ]);

    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SurveyRepository>.value(value: world.survey),
        RepositoryProvider<FeedbackRepository>.value(value: world.feedback),
        RepositoryProvider<OutdoorNavigationRepository>.value(value: trips),
      ],
      child: BlocProvider<AuthCubit>.value(
        value: SeededAuthCubit(state: auth ?? visitorState()),
        child: MaterialApp.router(routerConfig: router),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(openUnity));
    await tester.pumpAndSettle();
  }

  Future<void> arrive(WidgetTester tester, FakeUnity unity) async {
    unity.send({'event': 'arrived', 'destination': 'Library'});
    await tester.pumpAndSettle();
  }

  group('with Unity available', () {
    testWidgets('arrival shows the panel, not the old dialog', (tester) async {
      final unity = FakeUnity();
      await pumpTrip(tester, unity);

      await arrive(tester, unity);

      expect(find.text(arrived), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(unity.stops, 1);
    });

    testWidgets('someone without a SUS is asked for it, with the trip id',
        (tester) async {
      final unity = FakeUnity();
      await pumpTrip(tester, unity);
      await arrive(tester, unity);
      expect(find.byType(FeedbackCommentCard), findsNothing);

      await tester.tap(find.text(rate));
      await tester.pumpAndSettle();

      expect(find.text('survey'), findsOneWidget);
      expect(surveyExtra, {'navigation_session_id': trips.rows.first['trip_id']});
    });

    testWidgets('someone who answered it sees the optional comment instead',
        (tester) async {
      await world.submitSus();
      final unity = FakeUnity();
      await pumpTrip(tester, unity);

      await arrive(tester, unity);

      expect(find.text(rate), findsNothing);
      expect(find.byType(FeedbackCommentCard), findsOneWidget);
    });

    testWidgets('the once-per-person check is by signed-in user',
        (tester) async {
      await world.submitSus(userId: userA);
      final unity = FakeUnity();
      await pumpTrip(tester, unity, auth: AuthAuthenticated(student(userB)));

      await arrive(tester, unity);

      expect(find.text(rate), findsOneWidget);
    });

    testWidgets('the trip is logged as completed, once', (tester) async {
      final unity = FakeUnity();
      await pumpTrip(tester, unity);

      await arrive(tester, unity);
      await arrive(tester, unity);

      expect(trips.rows.map((r) => r['row_type']), ['start', 'end']);
      expect(trips.rows.last['completed'], isTrue);
      expect(trips.rows.last['mode'], 'ar');
      expect(unity.stops, 1);
    });

    testWidgets('leaving after arrival is not an abandoned trip',
        (tester) async {
      final unity = FakeUnity();
      await pumpTrip(tester, unity);
      await arrive(tester, unity);

      await tester.tap(find.text('Return to Map'));
      await tester.pumpAndSettle();

      expect(find.text('map'), findsOneWidget);
      expect(trips.rows.where((r) => r['row_type'] == 'end'), hasLength(1));
      expect(unity.stops, 1);
    });

    testWidgets('leaving before arrival still stops Unity and logs it',
        (tester) async {
      final unity = FakeUnity();
      await pumpTrip(tester, unity);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(trips.rows.last['row_type'], 'end');
      expect(trips.rows.last['completed'], isFalse);
      expect(unity.stops, 1);
    });
  });

  group('with Unity unavailable', () {
    testWidgets('no trip starts and the fallback is offered', (tester) async {
      final unity = FakeUnity(available: false);
      await pumpTrip(tester, unity);

      expect(unity.starts, 0);
      expect(trips.rows, isEmpty);
      expect(find.text('Continue in Camera AR'), findsOneWidget);
    });

    testWidgets('an arrival event does nothing', (tester) async {
      final unity = FakeUnity(available: false);
      await pumpTrip(tester, unity);

      await arrive(tester, unity);

      expect(find.text(arrived), findsNothing);
      expect(find.text(rate), findsNothing);
      expect(trips.rows, isEmpty);
    });
  });

  testWidgets('the real bridge reports unavailable without a Unity player',
      (tester) async {
    const channel = MethodChannel('com.um.arnav/unity');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(await UnityBridgeService.instance.isAvailable(), isFalse);
  });
}
