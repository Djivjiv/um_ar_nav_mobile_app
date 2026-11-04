import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/device_utils.dart';
import '../local/offline_cache.dart';
import '../local/pending_write_queue.dart';
import '../models/survey_question_model.dart';

class SurveyRepository {
  final SupabaseClient _client;
  final OfflineCache _offline;
  final PendingWriteQueue _queue;
  final Future<Object?> Function(String function, Map<String, dynamic> params)?
      _rpc;
  SurveyRepository([
    SupabaseClient? client,
    OfflineCache? offline,
    PendingWriteQueue? queue,
    Future<Object?> Function(String function, Map<String, dynamic> params)? rpc,
  ])  : _client = client ?? Supabase.instance.client,
        _offline = offline ?? OfflineCache.instance,
        _queue = queue ?? PendingWriteQueue.instance,
        _rpc = rpc;

  static const String questionsCacheKey = 'survey_questions';

  static const String table = 'sus_responses';

  /// Keeps an arrival screen from waiting long on a slow connection.
  static const Duration serverCheckTimeout = Duration(seconds: 4);

  /// The device flag for this person: `user_id` when signed in, else
  /// `device_code`. It stays after sign-out and when a visitor session ends,
  /// so nobody is asked twice.
  static String? _submittedFlag(String? userId, String? deviceCode) {
    if (userId != null) return 'sus_submitted.user.$userId';
    return deviceCode == null ? null : 'sus_submitted.device.$deviceCode';
  }

  Future<String?> _deviceCodeOrNull() async {
    try {
      return await DeviceUtils.getDeviceCode();
    } catch (e) {
      debugPrint('Device code unavailable: $e');
      return null;
    }
  }

  /// Whether this person already answered the SUS, here or on another phone.
  /// The device is asked first, so this also works offline. When neither the
  /// device nor the server can say, the answer is no: asking once more is
  /// better than never asking, and the server keeps only one response.
  Future<bool> hasSubmitted({String? userId}) async {
    final deviceCode = await _deviceCodeOrNull();
    final flag = _submittedFlag(userId, deviceCode);
    if (flag == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(flag) == true) return true;
      final answered = await _isQueued(userId, deviceCode) ||
          await _serverHas(deviceCode);
      if (answered) await prefs.setBool(flag, true);
      return answered;
    } catch (e) {
      debugPrint('SUS check failed: $e');
      return false;
    }
  }

  /// A response saved by a version of the app that had no flag can still be
  /// waiting in the queue.
  Future<bool> _isQueued(String? userId, String? deviceCode) async {
    final waiting = await _queue.pending();
    return waiting.any((w) =>
        w.table == table &&
        w.payload['user_id'] == userId &&
        (userId != null || w.payload['device_code'] == deviceCode));
  }

  /// See `supabase/sus_once_per_person.sql`. False when the server can't be
  /// reached or that file hasn't been run.
  Future<bool> _serverHas(String? deviceCode) async {
    const function = 'has_submitted_sus';
    final params = {'p_device_code': deviceCode};
    final rpc = _rpc;
    try {
      final answer = await (rpc != null
              ? rpc(function, params)
              : _callServer(function, params))
          .timeout(serverCheckTimeout);
      return answer == true;
    } catch (e) {
      debugPrint('SUS server check failed: $e');
      return false;
    }
  }

  Future<Object?> _callServer(
          String function, Map<String, dynamic> params) async =>
      await _client.rpc(function, params: params);

  /// Network first; offline, the last saved questions; with neither, the
  /// canonical SUS items.
  Future<List<SurveyQuestionModel>> getQuestions() async {
    try {
      final rows = await _offline.fetch<List<dynamic>>(
        questionsCacheKey,
        () async => await _client
            .from('survey_questions')
            .select()
            .eq('is_active', true)
            .order('question_number'),
      );
      final list = rows
          .map((e) => SurveyQuestionModel.fromMap(e as Map<String, dynamic>))
          .toList();
      return list.isEmpty ? SurveyQuestionModel.standardSus : list;
    } catch (_) {
      return SurveyQuestionModel.standardSus;
    }
  }

  /// The System Usability Scale has exactly this many items.
  static const int susItemCount = 10;

  /// Why [questions] cannot produce a SUS score, or null when they can.
  static String? susSetupProblem(List<SurveyQuestionModel> questions) {
    if (questions.length >= susItemCount) return null;
    return 'The feedback survey is not set up yet: it needs '
        '$susItemCount questions but only ${questions.length} '
        '${questions.length == 1 ? 'is' : 'are'} active. '
        'Please try again later.';
  }

  /// SUS scoring: odd items are positively worded, even items negatively.
  /// oddSum  = Σ(answers[0,2,4,6,8]) - 5
  /// evenSum = 25 - Σ(answers[1,3,5,7,9])
  /// score   = (oddSum + evenSum) * 2.5
  ///
  /// Returns null — never a made-up score — when fewer than 10 answers are
  /// given, or any of the first 10 is missing or outside 1–5.
  static double? calculateSusScore(List<int?> answers) {
    if (answers.length < susItemCount) return null;
    var oddSum = 0;
    var evenSum = 0;
    for (var i = 0; i < susItemCount; i++) {
      final a = answers[i];
      if (a == null || a < 1 || a > 5) return null;
      if (i.isEven) {
        oddSum += a;
      } else {
        evenSum += a;
      }
    }
    oddSum -= 5;
    evenSum = 25 - evenSum;
    return (oddSum + evenSum) * 2.5;
  }

  /// Stores the response on the device, then tries to send it.
  ///
  /// Returns true when it reached the server, false when it is queued and
  /// will be sent automatically once the connection returns. Throws only if
  /// the device storage itself fails (nothing was saved).
  Future<bool> submitResponse({
    String? userId,
    String? visitorSessionId,
    required List<int> answers,
    required double susScore,
    required String userType,
    String? navigationSessionId,
  }) async {
    final deviceCode = await _deviceCodeOrNull();
    final payload = <String, dynamic>{
      'user_id': userId,
      'visitor_session_id': visitorSessionId,
      'device_code': ?deviceCode,
      // The trip this survey follows (navigation_sessions.trip_id). Dropped
      // automatically if the column doesn't exist yet.
      'navigation_session_id': ?navigationSessionId,
      'sus_score': susScore,
      'user_type': userType,
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
    };
    for (var i = 0; i < answers.length && i < 10; i++) {
      payload['q${i + 1}'] = answers[i];
    }
    // Saved on the device first, so an answer is never lost; then sent.
    final id = await _queue.enqueue(table, payload, keepForever: true);
    await _rememberSubmitted(userId, deviceCode);
    try {
      await _queue.flush();
    } catch (_) {}
    return !await _queue.isPending(id);
  }

  /// A failure here costs nothing: the queued row answers [hasSubmitted] until
  /// it is sent, and the server after that.
  Future<void> _rememberSubmitted(String? userId, String? deviceCode) async {
    final flag = _submittedFlag(userId, deviceCode);
    if (flag == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(flag, true);
    } catch (e) {
      debugPrint('SUS flag not saved: $e');
    }
  }
}
