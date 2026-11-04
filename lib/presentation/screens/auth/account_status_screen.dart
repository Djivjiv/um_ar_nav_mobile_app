import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geofence_service.dart';
import '../../../data/models/user_profile_model.dart';
import '../../bloc/auth/auth_cubit.dart';

/// Title and short explanation for an account that can't use the app.
({String title, String message, IconData icon}) accountStatusText(
    AccountAccess access) {
  return switch (access) {
    AccountAccess.rejected => (
        title: 'Account not approved',
        message: "Your account request wasn't approved, so you can't use "
            'UM-AR Nav with it. Contact the university if you think this is '
            'a mistake.',
        icon: Icons.block,
      ),
    AccountAccess.inactive => (
        title: 'Account deactivated',
        message: 'This account has been deactivated, so you can no longer '
            'use UM-AR Nav with it. Contact the university if you think '
            'this is a mistake.',
        icon: Icons.person_off_outlined,
      ),
    _ => (
        title: 'Waiting for approval',
        message: 'An admin needs to approve your account before you can use '
            'UM-AR Nav. Check back later.',
        icon: Icons.hourglass_top,
      ),
  };
}

/// Shown instead of the app while [AuthAccountBlocked].
class AccountStatusScreen extends StatefulWidget {
  const AccountStatusScreen({super.key});

  @override
  State<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends State<AccountStatusScreen> {
  bool _checking = false;
  bool _gating = false;

  Future<void> _checkAgain() async {
    final cubit = context.read<AuthCubit>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    await cubit.recheckAccess();
    if (!mounted) return;
    setState(() => _checking = false);
    final state = cubit.state;
    if (state is AuthAccountBlocked && state.access == AccountAccess.pending) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Not approved yet.')));
    }
  }

  /// Approved — but still verify the user is on campus before the map.
  Future<void> _gateToMap() async {
    if (_gating) return;
    _gating = true;
    await GeofenceService.gate(context);
    _gating = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) _gateToMap();
        },
        builder: (context, state) {
          final access = state is AuthAccountBlocked
              ? state.access
              : AccountAccess.pending;
          final text = accountStatusText(access);
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(text.icon,
                        size: 56, color: AppColors.primaryMaroon),
                    const SizedBox(height: 16),
                    Text(text.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryMaroon)),
                    const SizedBox(height: 8),
                    Text(text.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 24),
                    if (access == AccountAccess.pending) ...[
                      ElevatedButton(
                        onPressed: _checking ? null : _checkAgain,
                        child: const Text('Check again'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    OutlinedButton(
                      onPressed: () => context.read<AuthCubit>().signOut(),
                      child: const Text('Back to sign in'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
