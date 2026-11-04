import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Shown instead of the app when a build is missing its keys, which only
/// happens to someone building the app. See `missingKeys`.
class SetupRequiredApp extends StatelessWidget {
  final List<String> missing;

  const SetupRequiredApp({super.key, required this.missing});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UM-AR Nav',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.vpn_key_outlined,
                    size: 48, color: AppColors.primaryMaroon),
                const SizedBox(height: 16),
                const Text('Setup required',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('This build was made without these keys:'),
                const SizedBox(height: 12),
                for (final name in missing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SelectableText(name,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 12),
                const Text('Pass each one when you run or build the app, '
                    'for example:'),
                const SizedBox(height: 8),
                const SelectableText(
                  'flutter run --dart-define=SUPABASE_URL=... '
                  '--dart-define=SUPABASE_ANON_KEY=... '
                  '--dart-define=MAPTILER_KEY=...',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text('The README has the commands for debug and '
                    'release builds.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
