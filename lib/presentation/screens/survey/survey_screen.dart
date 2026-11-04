import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/feedback_person.dart';
import '../../../data/models/survey_question_model.dart';
import '../../../data/repositories/feedback_repository.dart';
import '../../../data/repositories/survey_repository.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../widgets/feedback_comment_card.dart';
import '../../widgets/loading_skeleton.dart';

class SurveyScreen extends StatefulWidget {
  /// `navigation_sessions.trip_id` of the trip this survey follows, if any.
  final String? navigationSessionId;

  const SurveyScreen({super.key, this.navigationSessionId});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  late final SurveyRepository _repo = context.read<SurveyRepository>();
  late final FeedbackPerson _person =
      feedbackPerson(context.read<AuthCubit>().state);

  List<SurveyQuestionModel> _questions = const [];
  bool _loading = true;
  String? _error;
  int _index = 0;
  final Map<int, int> _answers = {};
  bool _submitting = false;
  double? _score;

  /// Answered before this screen opened: never asked twice.
  bool _alreadyAnswered = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final answered = await _repo.hasSubmitted(userId: _person.userId);
      final q = answered ? _questions : await _repo.getQuestions();
      if (!mounted) return;
      setState(() {
        _alreadyAnswered = answered;
        _questions = q;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the survey.';
        _loading = false;
      });
    }
  }

  bool get _isLast => _index == _questions.length - 1;

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _submit() async {
    // Every question must be answered — never fill gaps with a default.
    final ordered = List<int?>.generate(_questions.length, (i) => _answers[i]);
    final firstMissing = ordered.indexOf(null);
    if (firstMissing != -1) {
      setState(() => _index = firstMissing);
      _showMessage('Please answer question ${firstMissing + 1} first.');
      return;
    }
    final score = SurveyRepository.calculateSusScore(ordered);
    if (score == null) {
      _showMessage('Your answers could not be scored, so the survey was '
          'not submitted.');
      return;
    }
    setState(() => _submitting = true);

    final auth = context.read<AuthCubit>().state;
    String? userId;
    String? visitorId;
    String userType = 'visitor';
    if (auth is AuthAuthenticated) {
      userId = auth.user.id;
      userType = auth.user.roleLabel.isEmpty ? 'student' : auth.user.roleLabel;
    } else if (auth is AuthVisitor) {
      visitorId = auth.session.id.startsWith('local-') ? null : auth.session.id;
    }

    bool sent;
    try {
      sent = await _repo.submitResponse(
        userId: userId,
        visitorSessionId: visitorId,
        answers: ordered.cast<int>(),
        susScore: score,
        userType: userType,
        navigationSessionId: widget.navigationSessionId,
      );
    } catch (e) {
      // Not even saved on the device — keep the answers on screen so the
      // user can retry, and don't show a score as if it had been submitted.
      debugPrint('Survey submit failed: $e');
      if (mounted) {
        setState(() => _submitting = false);
        _showMessage('Your feedback could not be saved. '
            'Tap Submit to try again.');
      }
      return;
    }
    if (mounted) {
      setState(() {
        _submitting = false;
        _score = score;
        _queued = !sent;
      });
    }
  }

  /// True when the response is saved on the device but not yet sent.
  bool _queued = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback Survey')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Column(children: [
          LoadingSkeleton(height: 10),
          SizedBox(height: 30),
          LoadingSkeleton(height: 24),
          SizedBox(height: 40),
          LoadingSkeleton(height: 48),
        ]),
      );
    }
    if (_error != null) {
      return ErrorRetry(message: _error!, onRetry: _load);
    }
    if (_alreadyAnswered) return const _AlreadyAnswered();
    if (_questions.isEmpty) {
      return const EmptyState(message: 'No survey questions available.');
    }
    final setupProblem = SurveyRepository.susSetupProblem(_questions);
    if (setupProblem != null) return EmptyState(message: setupProblem);
    if (_score != null) {
      return _ThankYou(score: _score!, queued: _queued, person: _person);
    }

    final q = _questions[_index];
    final selected = _answers[_index];
    final scale = q.scale <= 1 ? 5 : q.scale;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: (_index + 1) / _questions.length,
            backgroundColor: AppColors.backgroundGray,
          ),
          const SizedBox(height: 8),
          Text('Question ${_index + 1} of ${_questions.length}',
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 30),
          Text(
            q.questionText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(scale, (i) {
              final value = i + 1;
              final isSel = selected == value;
              return GestureDetector(
                onTap: () => setState(() => _answers[_index] = value),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSel ? AppColors.primaryMaroon : Colors.white,
                    border: Border.all(color: AppColors.primaryMaroon),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text('$value',
                      style: TextStyle(
                        color: isSel
                            ? AppColors.accentGold
                            : AppColors.primaryMaroon,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Strongly Disagree',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              Text('Strongly Agree',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: selected == null
                ? null
                : _isLast
                    ? (_submitting ? null : _submit)
                    : () => setState(() => _index++),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.accentGold)),
                  )
                : Text(_isLast ? 'Submit Survey' : 'Next'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/map'),
            child: const Text('Skip Survey',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _AlreadyAnswered extends StatelessWidget {
  const _AlreadyAnswered();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("You've already answered this survey. Thank you!",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/map'),
            child: const Text('Back to Map'),
          ),
        ],
      ),
    );
  }
}

class _ThankYou extends StatelessWidget {
  final double score;

  /// Saved on the device, waiting for a connection.
  final bool queued;
  final FeedbackPerson person;
  const _ThankYou({
    required this.score,
    required this.person,
    this.queued = false,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(Icons.favorite, color: AppColors.errorRed, size: 64),
          const SizedBox(height: 16),
          const Text('Thank you!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Your feedback helps improve campus navigation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary)),
          if (queued) ...[
            const SizedBox(height: 12),
            const Text(
                "You're offline, so your answers are saved on this phone. "
                "They'll be sent automatically when you're back online.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 24),
          Text('SUS Score: ${score.toStringAsFixed(1)}',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryMaroon)),
          const SizedBox(height: 24),
          FeedbackCommentCard(
            ratingContext: FeedbackRepository.afterSus,
            person: person,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/map'),
            child: const Text('Back to Map'),
          ),
        ],
      ),
    );
  }
}
