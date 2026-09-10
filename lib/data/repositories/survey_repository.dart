import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/survey_question_model.dart';

class SurveyRepository {
  final SupabaseClient _client;
  SurveyRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  Future<List<SurveyQuestionModel>> getQuestions() async {
    try {
      final rows = await _client
          .from('survey_questions')
          .select()
          .eq('is_active', true)
          .order('question_number');
      final list = (rows as List)
          .map((e) => SurveyQuestionModel.fromMap(e as Map<String, dynamic>))
          .toList();
      return list.isEmpty ? SurveyQuestionModel.standardSus : list;
    } catch (_) {
      // Offline / failure: fall back to the canonical SUS items.
      return SurveyQuestionModel.standardSus;
    }
  }

  /// SUS scoring: odd items are positively worded, even items negatively.
  /// oddSum  = Σ(answers[0,2,4,6,8]) - 5
  /// evenSum = 25 - Σ(answers[1,3,5,7,9])
  /// score   = (oddSum + evenSum) * 2.5
  static double calculateSusScore(List<int> answers) {
    if (answers.length < 10) return 0;
    var oddSum = 0;
    var evenSum = 0;
    for (var i = 0; i < 10; i++) {
      if (i.isEven) {
        oddSum += answers[i];
      } else {
        evenSum += answers[i];
      }
    }
    oddSum -= 5;
    evenSum = 25 - evenSum;
    return (oddSum + evenSum) * 2.5;
  }

  Future<void> submitResponse({
    String? userId,
    String? visitorSessionId,
    required List<int> answers,
    required double susScore,
    required String userType,
    String? comment,
  }) async {
    final payload = <String, dynamic>{
      'user_id': userId,
      'visitor_session_id': visitorSessionId,
      'sus_score': susScore,
      'user_type': userType,
      'comment': comment,
      'submitted_at': DateTime.now().toIso8601String(),
    };
    for (var i = 0; i < answers.length && i < 10; i++) {
      payload['q${i + 1}'] = answers[i];
    }
    await _client.from('sus_responses').insert(payload);
  }
}
