import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:um_ar_mobile_app/core/network/connectivity_service.dart';
import 'package:um_ar_mobile_app/core/utils/device_utils.dart';
import 'package:um_ar_mobile_app/core/utils/server_clock.dart';
import 'package:um_ar_mobile_app/data/local/offline_cache.dart';
import 'package:um_ar_mobile_app/data/local/pending_write_queue.dart';
import 'package:um_ar_mobile_app/data/models/survey_question_model.dart';
import 'package:um_ar_mobile_app/data/models/user_profile_model.dart';
import 'package:um_ar_mobile_app/data/models/visitor_session_model.dart';
import 'package:um_ar_mobile_app/data/repositories/feedback_repository.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';
import 'package:um_ar_mobile_app/presentation/bloc/auth/auth_cubit.dart';

import 'visitor_fakes.dart';

const deviceCode = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const userA = '11111111-1111-4111-8111-111111111111';
const userB = '22222222-2222-4222-8222-222222222222';

/// `supabase/sus_once_per_person.sql` and the two tables, in miniature.
class FakeFeedbackServer {
  bool online = true;

  /// The table or function doesn't exist yet: the SQL hasn't been run.
  bool notSetUp = false;

  /// auth.uid() of the current login.
  String? signedInAs;

  final List<(String, Map<String, dynamic>)> rows = [];

  List<Map<String, dynamic>> rowsOf(String table) =>
      [for (final r in rows) if (r.$1 == table) r.$2];

  bool _hasSus({String? userId, String? device}) =>
      rowsOf(SurveyRepository.table).any((r) => userId != null
          ? r['user_id'] == userId
          : r['user_id'] == null && r['device_code'] == device);

  Future<void> send(String table, Map<String, dynamic> payload) async {
    if (!online) throw const SocketException('No route to host');
    if (notSetUp) throw const PostgrestException(message: 'no such table');
    if (table == SurveyRepository.table &&
        _hasSus(
            userId: payload['user_id'] as String?,
            device: payload['device_code'] as String?)) {
      throw const PostgrestException(
          message: 'duplicate key value',
          code: PendingWriteQueue.uniqueViolation);
    }
    rows.add((table, payload));
  }

  Future<Object?> rpc(String function, Map<String, dynamic> params) async {
    if (!online) throw const SocketException('No route to host');
    if (notSetUp) throw const PostgrestException(message: 'no such function');
    return _hasSus(
        userId: signedInAs, device: params['p_device_code'] as String?);
  }
}

/// Survey questions without a network, and everything else real.
class TestSurveyRepository extends SurveyRepository {
  TestSurveyRepository(
    SupabaseClient client,
    ConnectivityService connectivity,
    PendingWriteQueue queue,
    FakeFeedbackServer server,
  ) : super(client, OfflineCache(connectivity: connectivity), queue, server.rpc);

  @override
  Future<List<SurveyQuestionModel>> getQuestions() async =>
      SurveyQuestionModel.standardSus;
}

/// One phone: its storage, its queue and its repositories.
class FeedbackWorld {
  final FakeFeedbackServer server;
  FeedbackWorld([FakeFeedbackServer? server])
      : server = server ?? FakeFeedbackServer();

  final connectivity = ConnectivityService(probe: () async => true);
  final client = SupabaseClient('http://127.0.0.1:9', 'test-key');

  late final PendingWriteQueue queue = PendingWriteQueue(
    sender: server.send,
    connectivity: connectivity,
    sendTimeout: const Duration(seconds: 2),
  );
  late final SurveyRepository survey =
      TestSurveyRepository(client, connectivity, queue, server);
  late final FeedbackRepository feedback = FeedbackRepository(
    queue: queue,
    now: () => DateTime.utc(2026, 11, 1, 9),
  );

  /// The same phone after the app restarts: same storage, new objects.
  FeedbackWorld restarted() => FeedbackWorld(server);

  static Future<void> resetPhone() async {
    SharedPreferences.setMockInitialValues({'device_code': deviceCode});
    DeviceUtils.resetDeviceCode();
  }

  Future<bool> submitSus({String? userId}) => survey.submitResponse(
        userId: userId,
        answers: List.filled(10, 3),
        susScore: 50,
        userType: userId == null ? 'visitor' : 'student',
      );

  Future<void> pump(WidgetTester tester, AuthState state, Widget child) async {
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SurveyRepository>.value(value: survey),
        RepositoryProvider<FeedbackRepository>.value(value: feedback),
      ],
      child: BlocProvider<AuthCubit>.value(
        value: SeededAuthCubit(state: state),
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    ));
    await tester.pumpAndSettle();
  }
}

UserProfileModel student(String id) => UserProfileModel(
    id: id,
    email: 'someone@umindanao.edu.ph',
    fullName: 'Some One',
    role: 'student',
    isVerified: true);

AuthVisitor visitorState() => AuthVisitor(VisitorSessionModel(
      id: 's',
      deviceCode: deviceCode,
      startedAt: DateTime.utc(2026, 11, 1, 9),
      expiresAt: DateTime.utc(2026, 11, 1, 11),
      clock: ServerClock.fromJson({
        'server': DateTime.utc(2026, 11, 1, 10).toIso8601String(),
        'phone': DateTime.utc(2026, 11, 1, 10).toIso8601String(),
      }, source: FakeClockSource())!,
    ));
