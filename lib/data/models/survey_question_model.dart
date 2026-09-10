import '../../core/utils/json_utils.dart';

class SurveyQuestionModel {
  final String id;
  final int questionNumber;
  final String questionText;
  final int scale;
  final bool isActive;

  const SurveyQuestionModel({
    required this.id,
    required this.questionNumber,
    required this.questionText,
    this.scale = 5,
    this.isActive = true,
  });

  factory SurveyQuestionModel.fromMap(Map<String, dynamic> m) {
    return SurveyQuestionModel(
      id: J.strOr(m['id']),
      questionNumber: J.intOr(m['question_number'], 1),
      questionText: J.strOr(m['question_text'], ''),
      scale: J.intOr(m['scale'], 5),
      isActive: J.boolOr(m['is_active'], true),
    );
  }

  /// Standard 10-item System Usability Scale, used as an offline fallback.
  static List<SurveyQuestionModel> get standardSus => const [
        SurveyQuestionModel(
            id: 'sus1',
            questionNumber: 1,
            questionText:
                'I think that I would like to use this app frequently.'),
        SurveyQuestionModel(
            id: 'sus2',
            questionNumber: 2,
            questionText: 'I found the app unnecessarily complex.'),
        SurveyQuestionModel(
            id: 'sus3',
            questionNumber: 3,
            questionText: 'I thought the app was easy to use.'),
        SurveyQuestionModel(
            id: 'sus4',
            questionNumber: 4,
            questionText:
                'I think that I would need the support of a technical person to use this app.'),
        SurveyQuestionModel(
            id: 'sus5',
            questionNumber: 5,
            questionText:
                'I found the various functions in this app were well integrated.'),
        SurveyQuestionModel(
            id: 'sus6',
            questionNumber: 6,
            questionText:
                'I thought there was too much inconsistency in this app.'),
        SurveyQuestionModel(
            id: 'sus7',
            questionNumber: 7,
            questionText:
                'I would imagine that most people would learn to use this app very quickly.'),
        SurveyQuestionModel(
            id: 'sus8',
            questionNumber: 8,
            questionText: 'I found the app very cumbersome to use.'),
        SurveyQuestionModel(
            id: 'sus9',
            questionNumber: 9,
            questionText: 'I felt very confident using the app.'),
        SurveyQuestionModel(
            id: 'sus10',
            questionNumber: 10,
            questionText:
                'I needed to learn a lot of things before I could get going with this app.'),
      ];
}
