import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../bloc/auth/auth_cubit.dart';

class VerifyEmailScreen extends StatelessWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Email')),
      body: BlocListener<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            context.go('/map');
          } else if (state is AuthUnauthenticated) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Email not verified yet. Please try again.')),
            );
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread_outlined,
                  size: 72, color: AppColors.primaryMaroon),
              const SizedBox(height: 20),
              const Text('Check your inbox',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(
                'We sent a verification link to\n$email\n\n'
                'Tap the link, then come back and continue.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () =>
                    context.read<AuthCubit>().refreshAfterVerification(),
                child: const Text("I've Verified — Continue"),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () =>
                    context.read<AuthCubit>().resendVerification(email),
                child: const Text('Resend Email'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
