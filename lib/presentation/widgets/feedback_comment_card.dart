import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/feedback_person.dart';
import '../../data/repositories/feedback_repository.dart';
import '../bloc/auth/auth_cubit.dart';

/// The person giving feedback, from the sign-in state.
FeedbackPerson feedbackPerson(AuthState state) => state is AuthAuthenticated
    ? FeedbackPerson.user(state.user)
    : const FeedbackPerson.visitor();

/// A short, optional comment box. Send and Skip both close it.
class FeedbackCommentCard extends StatefulWidget {
  /// `rating_context`: one of the [FeedbackRepository] contexts.
  final String ratingContext;
  final FeedbackPerson person;
  final VoidCallback? onClosed;

  const FeedbackCommentCard({
    super.key,
    required this.ratingContext,
    required this.person,
    this.onClosed,
  });

  @override
  State<FeedbackCommentCard> createState() => _FeedbackCommentCardState();
}

class _FeedbackCommentCardState extends State<FeedbackCommentCard> {
  final _controller = TextEditingController();
  bool _sending = false;
  bool _closed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending &&
      FeedbackRepository.cleanComment(_controller.text).isNotEmpty;

  void _close() {
    setState(() => _closed = true);
    widget.onClosed?.call();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    bool sent;
    try {
      sent = await context.read<FeedbackRepository>().submitComment(
            comment: _controller.text,
            ratingContext: widget.ratingContext,
            person: widget.person,
          );
    } catch (e) {
      // Not even saved on the device: keep the text so it can be tried again.
      debugPrint('Comment not saved: $e');
      if (mounted) {
        setState(() => _sending = false);
        _showMessage('Your comment could not be saved. '
            'Tap Send to try again.');
      }
      return;
    }
    if (!mounted) return;
    _showMessage(sent
        ? 'Thanks for your comment.'
        : "Thanks. Your comment is saved and will be sent when you're back "
            'online.');
    _close();
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.backgroundGray),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Any suggestion or comment? (optional)',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 3,
            maxLength: FeedbackRepository.maxLength,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _sending ? null : _close,
                  child: const Text('Skip',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _canSend ? _send : null,
                  child: const Text('Send'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The comment entry for a signed-in user on the profile screen: a row that
/// opens the card.
class ProfileCommentEntry extends StatefulWidget {
  final FeedbackPerson person;

  const ProfileCommentEntry({super.key, required this.person});

  @override
  State<ProfileCommentEntry> createState() => _ProfileCommentEntryState();
}

class _ProfileCommentEntryState extends State<ProfileCommentEntry> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (_open) {
      return FeedbackCommentCard(
        ratingContext: FeedbackRepository.fromProfile,
        person: widget.person,
        onClosed: () => setState(() => _open = false),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.chat_bubble_outline),
        title: const Text('Send a suggestion or comment'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => _open = true),
      ),
    );
  }
}
