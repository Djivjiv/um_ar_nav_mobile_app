import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geofence_service.dart';
import '../../bloc/auth/auth_cubit.dart';

/// Shown when a visitor session runs out: start another, or log in.
class VisitorEndedScreen extends StatefulWidget {
  const VisitorEndedScreen({super.key});

  @override
  State<VisitorEndedScreen> createState() => _VisitorEndedScreenState();
}

class _VisitorEndedScreenState extends State<VisitorEndedScreen>
    with CampusGate {
  void _logIn() {
    context.read<AuthCubit>().reset();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthVisitor) {
            gateToMap();
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          final loading = state is AuthLoading;
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.timer_off_outlined,
                        size: 56, color: AppColors.primaryMaroon),
                    const SizedBox(height: 16),
                    const Text('Your visitor session ended',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryMaroon)),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: loading
                          ? null
                          : () =>
                              context.read<AuthCubit>().continueAsVisitor(),
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation(
                                      AppColors.accentGold)),
                            )
                          : const Text('Start a new session'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: loading ? null : _logIn,
                      child: const Text('Log in with your UM account'),
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
