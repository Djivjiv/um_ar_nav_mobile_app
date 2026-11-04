import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/visitor_text.dart';
import '../../../core/utils/geofence_service.dart';
import '../../bloc/auth/auth_cubit.dart';

class VisitorScreen extends StatefulWidget {
  const VisitorScreen({super.key});

  @override
  State<VisitorScreen> createState() => _VisitorScreenState();
}

class _VisitorScreenState extends State<VisitorScreen> with CampusGate {
  Timer? _timer;
  Duration _remaining = const Duration(hours: 2);

  @override
  void initState() {
    super.initState();
    // Kick off session creation unless one is already running.
    final state = context.read<AuthCubit>().state;
    if (state is AuthVisitor && state.session.isStillValid) {
      _startTimer(state);
    } else {
      context.read<AuthCubit>().continueAsVisitor();
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
        context.read<AuthCubit>().checkVisitorSession();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formatted {
    final d = _remaining;
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
          final failed = state is AuthError;
          final ready = state is AuthVisitor && _remaining > Duration.zero;
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
                const Text('Your session time left',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                if (failed)
                  TextButton(
                    onPressed: () =>
                        context.read<AuthCubit>().continueAsVisitor(),
                    child: const Text('Try again'),
                  )
                else if (!ready)
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
                    VisitorText.access,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: ready ? gateToMap : null,
                  child: const Text('Continue to Map'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Log in with your UM account'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
