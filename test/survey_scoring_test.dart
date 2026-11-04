import 'package:flutter_test/flutter_test.dart';
import 'package:um_ar_mobile_app/data/models/survey_question_model.dart';
import 'package:um_ar_mobile_app/data/repositories/survey_repository.dart';

void main() {
  group('calculateSusScore', () {
    test('scores a full set of answers', () {
      expect(SurveyRepository.calculateSusScore(List.filled(10, 3)), 50);
      expect(
        SurveyRepository.calculateSusScore([5, 1, 5, 1, 5, 1, 5, 1, 5, 1]),
        100,
      );
      expect(
        SurveyRepository.calculateSusScore([1, 5, 1, 5, 1, 5, 1, 5, 1, 5]),
        0,
      );
    });

    test('returns null (not 0) for fewer than 10 answers', () {
      expect(SurveyRepository.calculateSusScore(List.filled(9, 3)), isNull);
      expect(SurveyRepository.calculateSusScore(const []), isNull);
    });

    test('returns null when an answer is missing — no default of 3', () {
      final answers = List<int?>.filled(10, 4)..[6] = null;
      expect(SurveyRepository.calculateSusScore(answers), isNull);
    });

    test('returns null for answers outside 1–5', () {
      expect(
        SurveyRepository.calculateSusScore([0, 3, 3, 3, 3, 3, 3, 3, 3, 3]),
        isNull,
      );
      expect(
        SurveyRepository.calculateSusScore([3, 3, 3, 3, 3, 3, 3, 3, 3, 7]),
        isNull,
      );
    });
  });

  group('susSetupProblem', () {
    test('the standard 10-item SUS is fine', () {
      expect(
          SurveyRepository.susSetupProblem(SurveyQuestionModel.standardSus),
          isNull);
    });

    test('fewer than 10 active questions gives a clear message', () {
      final seven = SurveyQuestionModel.standardSus.take(7).toList();
      final message = SurveyRepository.susSetupProblem(seven);
      expect(message, isNotNull);
      expect(message, contains('10 questions'));
      expect(message, contains('only 7'));
    });
  });
}
