import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geofence_service.dart';
import '../../bloc/auth/auth_cubit.dart';

class _Role {
  final String value;
  final String title;
  final String subtitle;
  final IconData icon;
  const _Role(this.value, this.title, this.subtitle, this.icon);
}

const _roles = [
  _Role('student', 'Student', 'Enrolled student', Icons.school),
  _Role('employee', 'Employee', 'University staff', Icons.work_outline),
  _Role('faculty', 'Faculty', 'Teaching staff', Icons.co_present),
];

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  String? _selected;
  bool _gating = false;

  Future<void> _gateToMap() async {
    if (_gating) return;
    _gating = true;
    final inside = await GeofenceService.gate(context);
    if (inside && mounted) context.go('/map');
    _gating = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            _gateToMap();
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          final saving = state is AuthLoading;
          final user = state is AuthNeedsRoleSelection
              ? state.user
              : (state is AuthAuthenticated ? state.user : null);

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: Image.asset(
                        'assets/images/umlogo.png',
                        errorBuilder: (_, _, _) => const Icon(Icons.school,
                            color: AppColors.primaryMaroon, size: 48),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Welcome to UM-AR Nav!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryMaroon,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (user?.displayName.isNotEmpty == true)
                    Text(
                      user!.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (user?.email != null)
                    Text(
                      user!.email!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text(
                    'What is your role?',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'This helps us personalize your experience',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  ..._roles.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RoleCard(
                          role: r,
                          selected: _selected == r.value,
                          onTap: () => setState(() => _selected = r.value),
                        ),
                      )),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_selected == null || saving)
                          ? null
                          : () => context
                              .read<AuthCubit>()
                              .selectRole(_selected!),
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation(
                                      AppColors.accentGold)),
                            )
                          : const Text('Continue'),
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

class _RoleCard extends StatelessWidget {
  final _Role role;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentGold.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.primaryMaroon
                : const Color(0xFFDADCE0),
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
          ],
        ),
        child: Row(
          children: [
            Icon(role.icon, color: AppColors.primaryMaroon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(role.subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? AppColors.primaryMaroon
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
