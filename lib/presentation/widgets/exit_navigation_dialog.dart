import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// The "Exit Navigation?" confirmation shared by the navigation screens.
/// Resolves to true only when the user taps Exit.
Future<bool> confirmExitNavigation(BuildContext context) async {
  final leave = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Exit Navigation?'),
      content: const Text('Are you sure you want to exit navigation?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Continue',
              style: TextStyle(color: AppColors.primaryMaroon)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Exit', style: TextStyle(color: Colors.grey)),
        ),
      ],
    ),
  );
  return leave ?? false;
}
