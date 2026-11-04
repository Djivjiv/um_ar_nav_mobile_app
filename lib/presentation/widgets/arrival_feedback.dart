import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/feedback_repository.dart';
import '../../data/repositories/survey_repository.dart';
import '../bloc/auth/auth_cubit.dart';
import 'feedback_comment_card.dart';

/// What an arrival screen asks for. Someone who hasn't answered the SUS sees
/// [rateButton]; someone who has sees the optional comment card, once a trip.
class ArrivalFeedback extends StatefulWidget {
  /// `navigation_sessions.trip_id`, if this trip is logged.
  final String? tripId;

  /// Opens the survey. May leave the arrival screen for good, or complete
  /// when the survey is closed.
  final Future<void> Function() onRate;

  /// Each screen keeps the look of its own button.
  final Widget Function(VoidCallback onPressed) rateButton;

  const ArrivalFeedback({
    super.key,
    required this.tripId,
    required this.onRate,
    required this.rateButton,
  });

  @override
  State<ArrivalFeedback> createState() => _ArrivalFeedbackState();
}

enum _Ask { checking, survey, comment, nothing }

class _ArrivalFeedbackState extends State<ArrivalFeedback> {
  _Ask _ask = _Ask.checking;

  late final FeedbackRepository _feedback = context.read<FeedbackRepository>();
  late final SurveyRepository _survey = context.read<SurveyRepository>();
  late final _person = feedbackPerson(context.read<AuthCubit>().state);

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final submitted = await _survey.hasSubmitted(userId: _person.userId);
    if (!mounted) return;
    setState(() {
      if (!submitted) {
        _ask = _Ask.survey;
      } else {
        _ask = _feedback.isTripClosed(widget.tripId)
            ? _Ask.nothing
            : _Ask.comment;
      }
    });
  }

  Future<void> _rate() async {
    await widget.onRate();
    if (!mounted) return;
    // The survey offers its own comment card, so this trip has had its turn.
    if (await _survey.hasSubmitted(userId: _person.userId)) _closeForTrip();
  }

  void _closeForTrip() {
    _feedback.closeTrip(widget.tripId);
    if (mounted) setState(() => _ask = _Ask.nothing);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_ask) {
      _Ask.checking => const SizedBox(height: 48),
      _Ask.survey => widget.rateButton(_rate),
      _Ask.comment => FeedbackCommentCard(
          ratingContext: FeedbackRepository.afterArrival,
          person: _person,
          onClosed: _closeForTrip,
        ),
      _Ask.nothing => const SizedBox.shrink(),
    };
  }
}
