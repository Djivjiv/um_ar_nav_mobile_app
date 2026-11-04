import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/data/local/pending_write_queue.dart';
import 'package:um_ar_mobile_app/data/models/feedback_person.dart';
import 'package:um_ar_mobile_app/data/models/user_profile_model.dart';
import 'package:um_ar_mobile_app/data/repositories/feedback_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:um_ar_mobile_app/presentation/widgets/arrival_feedback.dart';
import 'package:um_ar_mobile_app/presentation/widgets/feedback_comment_card.dart';

import 'support/feedback_fakes.dart';

void main() {
  late FeedbackWorld world;

  setUp(() async {
    await FeedbackWorld.resetPhone();
    world = FeedbackWorld();
  });

  List<Map<String, dynamic>> comments() =>
      world.server.rowsOf(FeedbackRepository.table);

  Future<bool> submit({
    String comment = 'More signs near the gym',
    String context = FeedbackRepository.afterArrival,
    FeedbackPerson person = const FeedbackPerson.visitor(),
  }) =>
      world.feedback.submitComment(
          comment: comment, ratingContext: context, person: person);

  Widget arrival(String tripId) => ArrivalFeedback(
        key: ValueKey(tripId),
        tripId: tripId,
        onRate: () async {},
        rateButton: (_) => const Text('rate'),
      );

  Future<void> tapSend(WidgetTester tester) async {
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
  }

  group('the row', () {
    test('a visitor: exactly the agreed columns, user_id null', () async {
      expect(await submit(), isTrue);

      expect(comments().single, {
        'comment': 'More signs near the gym',
        'rating_context': 'arrival',
        'role': 'visitor',
        'device_code': deviceCode,
        'user_id': null,
        'created_at': '2026-11-01T09:00:00.000Z',
      });
    });

    test('a signed-in user: their role and user_id, no name or email',
        () async {
      await submit(
        context: FeedbackRepository.fromProfile,
        person: FeedbackPerson.user(student(userA)),
      );

      final row = comments().single;
      expect(row['rating_context'], 'profile');
      expect(row['role'], 'student');
      expect(row['user_id'], userA);
      expect(row['device_code'], deviceCode);
      expect(row.keys.toSet(), {
        'comment',
        'rating_context',
        'role',
        'device_code',
        'user_id',
        'created_at',
      });
      expect('$row', isNot(contains('Some One')));
      expect('$row', isNot(contains('umindanao.edu.ph')));
    });

    test('a capitalised role is written the way the admin app reads it',
        () async {
      await submit(
        person: FeedbackPerson.user(
            const UserProfileModel(id: userA, role: 'Faculty')),
      );
      expect(comments().single['role'], 'faculty');
    });

    test('a device code that cannot be read does not lose the comment',
        () async {
      final feedback = FeedbackRepository(
        queue: world.queue,
        deviceCode: () => throw const FileSystemException('no storage'),
      );

      await feedback.submitComment(
        comment: 'still here',
        ratingContext: FeedbackRepository.afterSus,
        person: const FeedbackPerson.visitor(),
      );

      expect(comments().single['comment'], 'still here');
      expect(comments().single.containsKey('device_code'), isFalse);
    });
  });

  group('500 character limit', () {
    test('text is trimmed', () {
      expect(FeedbackRepository.cleanComment('  hello \n'), 'hello');
    });

    test('longer text is cut to 500', () async {
      await submit(comment: 'x' * 900);
      expect(comments().single['comment'], 'x' * 500);
    });

    test('exactly 500 is kept', () {
      expect(FeedbackRepository.cleanComment('x' * 500), 'x' * 500);
    });

    test('the limit is counted after trimming', () {
      final text = '${' ' * 20}${'x' * 500}${' ' * 20}';
      expect(FeedbackRepository.cleanComment(text), 'x' * 500);
    });

    test('a cut never splits an emoji or leaves a trailing space', () {
      expect(FeedbackRepository.cleanComment('😀' * 501), '😀' * 500);
      final cut = FeedbackRepository.cleanComment('${'x' * 499} yy');
      expect(cut, 'x' * 499);
    });

    test('a blank comment is refused and nothing is queued', () async {
      expect(() => submit(comment: '   '), throwsArgumentError);
      expect(await world.queue.pending(), isEmpty);
    });

    testWidgets('the box stops at 500 characters', (tester) async {
      await world.pump(
        tester,
        visitorState(),
        const FeedbackCommentCard(
          ratingContext: FeedbackRepository.afterArrival,
          person: FeedbackPerson.visitor(),
        ),
      );

      await tester.enterText(find.byType(TextField), 'x' * 600);
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 500);
      expect(find.text('500/500'), findsOneWidget);
    });

    testWidgets('Send stays off for an empty or blank comment',
        (tester) async {
      await world.pump(
        tester,
        visitorState(),
        const FeedbackCommentCard(
          ratingContext: FeedbackRepository.afterArrival,
          person: FeedbackPerson.visitor(),
        ),
      );
      ElevatedButton send() =>
          tester.widget<ElevatedButton>(find.byType(ElevatedButton));

      expect(send().onPressed, isNull);
      await tester.enterText(find.byType(TextField), '    ');
      await tester.pump();
      expect(send().onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'ok');
      await tester.pump();
      expect(send().onPressed, isNotNull);
    });
  });

  group('offline queue', () {
    test('kept on the device, sent when back online, in order', () async {
      world.server.online = false;
      expect(await submit(comment: 'first'), isFalse);
      expect(await submit(comment: 'second'), isFalse);

      final waiting = await world.queue.pending();
      expect(waiting.map((w) => w.table).toSet(), {FeedbackRepository.table});
      expect(waiting.every((w) => w.keepForever), isTrue);
      expect(comments(), isEmpty);

      world.server.online = true;
      await world.queue.flush();

      expect(comments().map((c) => c['comment']), ['first', 'second']);
      expect(await world.queue.pending(), isEmpty);
    });

    test('survives an app restart', () async {
      world.server.online = false;
      await submit();

      world.server.online = true;
      final restarted = world.restarted();
      await restarted.queue.flush();

      expect(comments(), hasLength(1));
    });

    test('many failed retries lose nothing', () async {
      world.server.online = false;
      await submit();

      for (var i = 0; i < PendingWriteQueue.maxRejections * 3; i++) {
        await world.queue.flush();
      }

      expect((await world.queue.pending()).single.table,
          FeedbackRepository.table);
    });

    test('waits for the table when the SQL has not been run', () async {
      world.server.notSetUp = true;
      await submit();

      for (var i = 0; i < PendingWriteQueue.maxRejections + 3; i++) {
        await world.queue.flush();
      }
      expect(await world.queue.pending(), hasLength(1));

      world.server.notSetUp = false;
      await world.queue.flush();

      expect(comments(), hasLength(1));
      expect(await world.queue.pending(), isEmpty);
    });

    test('a comment is never treated as a duplicate of an earlier one',
        () async {
      await submit(comment: 'same words');
      await submit(comment: 'same words');

      expect(comments(), hasLength(2));
    });
  });

  group('the card on an arrival', () {
    testWidgets('Skip closes it and sends nothing', (tester) async {
      await world.submitSus();
      await world.pump(tester, visitorState(), arrival('trip-1'));
      await tester.enterText(find.byType(TextField), 'changed my mind');

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(comments(), isEmpty);
      expect(await world.queue.pending(), isEmpty);
    });

    testWidgets('Skip is not asked again for that trip, but is for the next',
        (tester) async {
      await world.submitSus();
      await world.pump(tester, visitorState(), arrival('trip-1'));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // The same trip's arrival screen, built again.
      await world.pump(tester, visitorState(), const SizedBox());
      await world.pump(tester, visitorState(), arrival('trip-1'));
      expect(find.byType(TextField), findsNothing);

      await world.pump(tester, visitorState(), arrival('trip-2'));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Send writes the comment and closes the card',
        (tester) async {
      await world.submitSus(userId: userA);
      await world.pump(
          tester, AuthAuthenticated(student(userA)), arrival('trip-1'));
      await tester.enterText(find.byType(TextField), '  Great app  ');
      await tester.pump();

      await tapSend(tester);

      final row = comments().single;
      expect(row['comment'], 'Great app');
      expect(row['rating_context'], 'arrival');
      expect(row['user_id'], userA);
      expect(row['role'], 'student');
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Thanks for your comment.'), findsOneWidget);
      expect(world.feedback.isTripClosed('trip-1'), isTrue);
    });

    testWidgets('Send while offline keeps it and says so', (tester) async {
      await world.submitSus();
      world.server.online = false;
      await world.pump(tester, visitorState(), arrival('trip-1'));
      await tester.enterText(find.byType(TextField), 'From a dead zone');
      await tester.pump();

      await tapSend(tester);

      expect(comments(), isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('saved'), findsOneWidget);
      final waiting = await world.queue.pending();
      expect(waiting.single.payload['comment'], 'From a dead zone');
    });

    testWidgets('a trip with no log id can still be skipped', (tester) async {
      await world.submitSus();
      await world.pump(
        tester,
        visitorState(),
        ArrivalFeedback(
          tripId: null,
          onRate: () async {},
          rateButton: (_) => const Text('rate'),
        ),
      );

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });
  });

  group('the profile entry', () {
    Widget entry() =>
        ProfileCommentEntry(person: FeedbackPerson.user(student(userA)));

    testWidgets('opens the card, and Skip closes it', (tester) async {
      await world.pump(tester, AuthAuthenticated(student(userA)), entry());
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Send a suggestion or comment'));
      await tester.pumpAndSettle();
      expect(find.text('Any suggestion or comment? (optional)'),
          findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Send a suggestion or comment'), findsOneWidget);
      expect(comments(), isEmpty);
    });

    testWidgets('sends with the profile context and can be used again',
        (tester) async {
      await world.pump(tester, AuthAuthenticated(student(userA)), entry());
      await tester.tap(find.text('Send a suggestion or comment'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Add the new annex');
      await tester.pump();

      await tapSend(tester);

      expect(comments().single['rating_context'], 'profile');
      expect(comments().single['user_id'], userA);
      expect(find.text('Send a suggestion or comment'), findsOneWidget);
    });
  });
}
