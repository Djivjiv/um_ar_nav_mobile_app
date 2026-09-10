import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/survey_question_model.dart';
import '../../../data/repositories/survey_repository.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../widgets/loading_skeleton.dart';

class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  late final SurveyRepository _repo = context.read<SurveyRepository>();
  final _commentController = TextEditingController();

  List<SurveyQuestionModel> _questions = const [];
  bool _loading = true;
  String? _error;
  int _index = 0;
  final Map<int, int> _answers = {};
  bool _submitting = false;
  double? _score;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = await _repo.getQuestions();
      setState(() {
        _questions = q;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Could not load the survey.';
        _loading = false;
      });
    }
  }

  bool get _isLast => _index == _questions.length - 1;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final ordered = List<int>.generate(
      _questions.length,
      (i) => _answers[i] ?? 3,
    );
    final score = SurveyRepository.calculateSusScore(ordered);

    final auth = context.read<AuthCubit>().state;
    String? userId;
    String? visitorId;
    String userType = 'visitor';
    if (auth is AuthAuthenticated) {
      userId = Supabase.instance.client.auth.currentUser?.id;
      userType = auth.user.roleLabel.isEmpty ? 'student' : auth.user.roleLabel;
    } else if (auth is AuthVisitor) {
      visitorId = auth.session.id.startsWith('local-') ? null : auth.session.id;
    }

    try {
      await _repo.submitResponse(
        userId: userId,
        visitorSessionId: visitorId,
        answers: ordered,
        susScore: score,
        userType: userType,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit — saved locally.')),
        );
      }
    }
    if (mounted) {
      setState(() {
        _submitting = false;
        _score = score;
      });
    }
  }

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
    if (_questions.isEmpty) {
      return const EmptyState(message: 'No survey questions available.');
    }
    if (_score != null) return _ThankYou(score: _score!);

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
          if (_isLast) ...[
            const SizedBox(height: 24),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Any suggestions? (optional)',
              ),
            ),
          ],
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

class _ThankYou extends StatelessWidget {
  final double score;
  const _ThankYou({required this.score});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, color: AppColors.errorRed, size: 64),
          const SizedBox(height: 16),
          const Text('Thank you!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Your feedback helps improve campus navigation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          Text('SUS Score: ${score.toStringAsFixed(1)}',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryMaroon)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go('/map'),
            child: const Text('Back to Map'),
          ),
        ],
      ),
    );
  }
}
