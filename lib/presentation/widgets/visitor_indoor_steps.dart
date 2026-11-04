import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/visitor_text.dart';

/// Numbered written directions, shown in place of the 2D indoor map.
class VisitorIndoorSteps extends StatelessWidget {
  final List<String> steps;

  /// The number of the first step here; later floors carry on counting.
  final int firstNumber;

  /// Index in [steps] of the step the user is on.
  final int current;

  const VisitorIndoorSteps({
    super.key,
    required this.steps,
    this.firstNumber = 1,
    this.current = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.accentGold),
          ),
          child: const Text(
            VisitorText.indoorMessage,
            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 16),
        if (steps.isEmpty)
          const Text(
            "Written directions aren't available for this route.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            number: firstNumber + i,
            text: steps[i],
            active: i == current,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final int number;
  final String text;
  final bool active;

  const _StepRow({
    required this.number,
    required this.text,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step $number. $text',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: active
                  ? AppColors.primaryMaroon
                  : AppColors.backgroundGray,
              child: Text(
                '$number',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
