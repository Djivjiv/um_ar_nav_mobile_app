import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geofence_service.dart';
import '../../bloc/auth/auth_cubit.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with CampusGate {
  bool _isLoading = false;
  String? _errorMessage;

  void _signInWithGoogle() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    context.read<AuthCubit>().signInWithGoogle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthLoading) return;
          setState(() => _isLoading = false);

          if (state is AuthError) {
            // The cubit only emits friendly messages here; the detailed
            // error is logged to the debug console by the repository/cubit.
            debugPrint('Google Sign-In error: ${state.message}');
            setState(() => _errorMessage = state.message);
          } else if (state is AuthNeedsRoleSelection) {
            context.go('/select-role');
          } else if (state is AuthAuthenticated) {
            gateToMap();
          } else if (state is AuthUnauthenticated) {
            // Cancelled sign-in — just clear the spinner, no message.
            setState(() => _errorMessage = null);
          }
        },
        builder: (context, state) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  _Header(),
                  const Spacer(flex: 2),
                  _GoogleButton(
                    loading: _isLoading,
                    onPressed: _isLoading ? null : _signInWithGoogle,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 14),
                    _ErrorBox(message: _errorMessage!),
                  ],
                  const SizedBox(height: 20),
                  Row(children: const [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or',
                          style:
                              TextStyle(color: AppColors.textSecondary)),
                    ),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _isLoading
                        ? null
                        : () => context.go('/visitor'),
                    child: const Text('Continue as Visitor'),
                  ),
                  const Spacer(flex: 3),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Only @umindanao.edu.ph accounts allowed',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          padding: const EdgeInsets.all(12),
          child: Image.asset(
            'assets/images/umlogo.png',
            errorBuilder: (_, _, _) => const Icon(Icons.school,
                color: AppColors.primaryMaroon, size: 56),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'UM-AR Nav',
          style: TextStyle(
            color: AppColors.primaryMaroon,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Campus Navigation',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onPressed;

  const _GoogleButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 1.5,
        shadowColor: Colors.black26,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDADCE0)),
            ),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      _GoogleLogo(),
                      SizedBox(width: 12),
                      Text(
                        'Sign in with Google',
                        style: TextStyle(
                          color: Color(0xFF3C4043),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Small multi-colour "G" mark drawn without an image asset.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.22;
    final arcRect = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Blue, green, yellow, red quarter-ish arcs.
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(arcRect, -0.35, 1.25, false, paint);
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(arcRect, 0.9, 1.4, false, paint);
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(arcRect, 2.3, 1.2, false, paint);
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(arcRect, 3.5, 1.4, false, paint);

    // Blue crossbar of the "G".
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.5, size.height * 0.42, size.width * 0.5,
          size.height * 0.16),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline,
              color: AppColors.errorRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: AppColors.errorRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
