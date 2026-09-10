import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geofence_service.dart';
import '../../bloc/auth/auth_cubit.dart';

class VisitorScreen extends StatefulWidget {
  const VisitorScreen({super.key});

  @override
  State<VisitorScreen> createState() => _VisitorScreenState();
}

class _VisitorScreenState extends State<VisitorScreen> {
  Timer? _timer;
  Duration _remaining = const Duration(hours: 2);
  bool _gating = false;

  Future<void> _gateToMap() async {
    if (_gating) return;
    _gating = true;
    final inside = await GeofenceService.gate(context);
    if (inside && mounted) context.go('/map');
    _gating = false;
  }

  @override
  void initState() {
    super.initState();
    // Kick off session creation if not already a visitor.
    final state = context.read<AuthCubit>().state;
    if (state is! AuthVisitor) {
      context.read<AuthCubit>().continueAsVisitor();
    } else {
      _startTimer(state);
    }
  }

  void _startTimer(AuthVisitor state) {
    _timer?.cancel();
    _remaining = state.session.remaining;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = state.session.remaining;
      });
      if (_remaining <= Duration.zero) {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formatted {
    final d = _remaining.isNegative ? Duration.zero : _remaining;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visitor Access')),
      body: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthVisitor) {
            _startTimer(state);
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          final loading = state is AuthLoading;
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.badge_outlined,
                    size: 64, color: AppColors.primaryMaroon),
                const SizedBox(height: 18),
                const Text('You are browsing as a Visitor',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('Your session expires in 2 hours',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                if (loading)
                  const CircularProgressIndicator()
                else
                  Text(
                    _formatted,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentGold,
                      letterSpacing: 2,
                    ),
                  ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundGray,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Visitor access is limited to building-level information. '
                    'Sign in with a school email for full indoor navigation '
                    'and room details.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed:
                      (state is AuthVisitor) ? _gateToMap : null,
                  child: const Text('Continue to Map'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Have a school email? Login'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
