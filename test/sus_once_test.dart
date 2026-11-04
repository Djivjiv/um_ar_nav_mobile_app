import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:um_ar_mobile_app/presentation/screens/survey/survey_screen.dart';
import 'package:um_ar_mobile_app/presentation/widgets/arrival_feedback.dart';
import 'package:um_ar_mobile_app/presentation/widgets/feedback_comment_card.dart';

import 'support/feedback_fakes.dart';

const rate = 'Rate Your Experience';

void main() {
  late FeedbackWorld world;

  setUp(() async {
    await FeedbackWorld.resetPhone();
    world = FeedbackWorld();
  });

  Widget arrival({String? tripId = 'trip-1', void Function()? onRate}) =>
      ArrivalFeedback(
        key: ValueKey(tripId),
        tripId: tripId,
        onRate: () async => onRate?.call(),
        rateButton: (onPressed) =>
            ElevatedButton(onPressed: onPressed, child: const Text(rate)),
      );

  group('who has answered', () {
    test('a visitor is known by device_code, across app restarts', () async {
      expect(await world.survey.hasSubmitted(), isFalse);

      await world.submitSus();

      expect(await world.survey.hasSubmitted(), isTrue);
      expect(await world.restarted().survey.hasSubmitted(), isTrue);
      expect(world.server.rowsOf(SurveyRepository.table).single['device_code'],
          deviceCode);
    });

    test('a signed-in user is known by user_id', () async {
      expect(await world.survey.hasSubmitted(userId: userA), isFalse);

      await world.submitSus(userId: userA);

      expect(await world.survey.hasSubmitted(userId: userA), isTrue);
    });

    test('people sharing a phone are each asked once', () async {
      await world.submitSus(userId: userA);

      world.server.signedInAs = userB;
      expect(await world.survey.hasSubmitted(userId: userB), isFalse);

      world.server.signedInAs = null;
      expect(await world.survey.hasSubmitted(), isFalse);
      await world.submitSus();
      expect(await world.survey.hasSubmitted(), isTrue);

      world.server.signedInAs = userB;
      expect(await world.survey.hasSubmitted(userId: userB), isFalse);
    });

    test('the server knows about an answer given on another phone', () async {
      world.server.rows.add((
        SurveyRepository.table,
        {'user_id': userA, 'device_code': 'another-phone'}
      ));
      world.server.signedInAs = userA;

      expect(await world.survey.hasSubmitted(userId: userA), isTrue);

      // Remembered from then on, so this also holds offline.
      world.server.online = false;
      expect(await world.survey.hasSubmitted(userId: userA), isTrue);
    });

    test('the server finds a visitor by the device_code sent', () async {
      world.server.rows.add((
        SurveyRepository.table,
        {'user_id': null, 'device_code': deviceCode}
      ));

      expect(await world.survey.hasSubmitted(), isTrue);
    });

    test('a row an older app left in the queue counts as answered', () async {
      world.server.online = false;
      await world.queue.enqueue(SurveyRepository.table,
          {'user_id': userA, 'device_code': deviceCode}, keepForever: true);

      expect(await world.survey.hasSubmitted(userId: userA), isTrue);
      expect(await world.survey.hasSubmitted(userId: userB), isFalse);
    });

    test('before the SQL is run the phone still remembers its own', () async {
      world.server.notSetUp = true;
      expect(await world.survey.hasSubmitted(), isFalse);

      await world.submitSus();
      expect(await world.survey.hasSubmitted(), isTrue);
    });
  });

  group('offline', () {
    setUp(() => world.server.online = false);

    test('an answer counts at once, and syncs when back online', () async {
      expect(await world.submitSus(), isFalse);

      expect(await world.survey.hasSubmitted(), isTrue);
      expect(await world.restarted().survey.hasSubmitted(), isTrue);
      expect(world.server.rows, isEmpty);

      world.server.online = true;
      await world.queue.flush();
      expect(world.server.rowsOf(SurveyRepository.table), hasLength(1));
      expect(await world.survey.hasSubmitted(), isTrue);
    });

    test('with nothing known, the person is asked', () async {
      expect(await world.survey.hasSubmitted(), isFalse);
    });

    testWidgets('second arrival shows no survey', (tester) async {
      await world.submitSus();

      await world.pump(tester, visitorState(), arrival());

      expect(find.text(rate), findsNothing);
      expect(find.byType(FeedbackCommentCard), findsOneWidget);
    });
  });

  group('a second answer from one person', () {
    test('is removed from the queue when the server refuses it', () async {
      // Asked on two phones while offline: the first to sync wins.
      await world.submitSus();
      world.server.online = false;
      await world.submitSus();
      expect(await world.queue.pending(), hasLength(1));

      world.server.online = true;
      await world.queue.flush();

      expect(await world.queue.pending(), isEmpty);
      expect(world.server.rowsOf(SurveyRepository.table), hasLength(1));
    });
  });

  group('arrival screens', () {
    Future<void> firstThenSecond(
      WidgetTester tester,
      AuthState state,
      Future<void> Function() answer,
    ) async {
      await world.pump(tester, state, arrival(tripId: 'trip-1'));
      expect(find.text(rate), findsOneWidget);
      expect(find.byType(FeedbackCommentCard), findsNothing);

      await answer();

      await world.pump(tester, state, arrival(tripId: 'trip-2'));
      expect(find.text(rate), findsNothing);
      expect(find.byType(FeedbackCommentCard), findsOneWidget);
    }

    testWidgets('visitor: first arrival asks, second does not',
        (tester) async {
      await firstThenSecond(tester, visitorState(), world.submitSus);
    });

    testWidgets('signed-in user: first arrival asks, second does not',
        (tester) async {
      await firstThenSecond(
        tester,
        AuthAuthenticated(student(userA)),
        () => world.submitSus(userId: userA),
      );
    });

    testWidgets('another signed-in user on the phone is still asked',
        (tester) async {
      await world.submitSus(userId: userA);

      await world.pump(tester, AuthAuthenticated(student(userB)), arrival());

      expect(find.text(rate), findsOneWidget);
    });

    testWidgets('someone who skipped the survey is asked on the next arrival',
        (tester) async {
      await world.pump(tester, visitorState(), arrival(tripId: 'trip-1'));
      await tester.tap(find.text(rate));
      await tester.pumpAndSettle();

      await world.pump(tester, visitorState(), arrival(tripId: 'trip-2'));

      expect(find.text(rate), findsOneWidget);
    });

    testWidgets('back from answering: no comment card on the same trip',
        (tester) async {
      await world.pump(
        tester,
        visitorState(),
        ArrivalFeedback(
          tripId: 'trip-1',
          onRate: world.submitSus,
          rateButton: (onPressed) =>
              ElevatedButton(onPressed: onPressed, child: const Text(rate)),
        ),
      );

      await tester.tap(find.text(rate));
      await tester.pumpAndSettle();

      expect(find.text(rate), findsNothing);
      expect(find.byType(FeedbackCommentCard), findsNothing);
      expect(world.feedback.isTripClosed('trip-1'), isTrue);
    });
  });

  group('survey screen', () {
    Future<void> answerAll(WidgetTester tester) async {
      for (var i = 0; i < SurveyRepository.susItemCount; i++) {
        await tester.tap(find.text('3'));
        await tester.pump();
        final last = i == SurveyRepository.susItemCount - 1;
        final button = find.text(last ? 'Submit Survey' : 'Next');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
    }

    testWidgets('answering saves the person and offers the comment card',
        (tester) async {
      await world.pump(
          tester, AuthAuthenticated(student(userA)), const SurveyScreen());

      await answerAll(tester);

      expect(find.text('Thank you!'), findsOneWidget);
      expect(find.byType(FeedbackCommentCard), findsOneWidget);
      expect(
          tester
              .widget<FeedbackCommentCard>(find.byType(FeedbackCommentCard))
              .ratingContext,
          'sus');
      final row = world.server.rowsOf(SurveyRepository.table).single;
      expect(row['user_id'], userA);
      expect(row['device_code'], deviceCode);
      expect(row.containsKey('comment'), isFalse);
    });

    testWidgets('has no comment box of its own', (tester) async {
      await world.pump(tester, visitorState(), const SurveyScreen());

      for (var i = 0; i < SurveyRepository.susItemCount - 1; i++) {
        await tester.tap(find.text('3'));
        await tester.pump();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('someone who already answered is not asked again',
        (tester) async {
      await world.submitSus();

      await world.pump(tester, visitorState(), const SurveyScreen());

      expect(find.textContaining('already answered'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });
  });
}
