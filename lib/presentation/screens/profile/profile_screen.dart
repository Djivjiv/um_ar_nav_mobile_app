import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/visitor_text.dart';
import '../../../core/utils/session_service.dart';
import '../../../data/models/feedback_person.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../widgets/feedback_comment_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Timer? _timer;
  bool _notifications = true;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    if (d.isNegative) return 'expired';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AuthCubit>().signOut();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) {
          if (state is AuthAuthenticated) {
            return _userView(state);
          }
          if (state is AuthVisitor) {
            return _visitorView(state);
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Not signed in'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Go to Login'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _userView(AuthAuthenticated state) {
    final u = state.user;
    return ListView(
      children: [
        Container(
          color: AppColors.primaryMaroon,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.white,
                child: Text(
                  u.displayName.isNotEmpty
                      ? u.displayName[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                      fontSize: 28,
                      color: AppColors.primaryMaroon,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              Text(u.displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              Text(u.email ?? '',
                  style: const TextStyle(color: Colors.white70)),
              if (u.isVerified) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentGold,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified,
                          size: 14, color: AppColors.primaryMaroon),
                      SizedBox(width: 4),
                      Text('Verified',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primaryMaroon,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card([
          _tile(Icons.badge_outlined, 'Role',
              u.hasRole ? u.roleLabel.toUpperCase() : 'NOT SET'),
          _tile(Icons.lock_outline, 'Access level', 'Full campus access'),
        ]),
        if (_userId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: FutureBuilder<int>(
              future: SessionService.getUserRemainingHours(_userId!),
              builder: (context, snapshot) {
                final hours = snapshot.data ?? 0;
                return Row(
                  children: [
                    const Icon(Icons.access_time,
                        color: AppColors.accentGold, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Session expires in: ${hours}h',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ProfileCommentEntry(person: FeedbackPerson.user(u)),
        ),
        _card([
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            value: _notifications,
            onChanged: (v) => setState(() => _notifications = v),
          ),
          _tile(Icons.info_outline, 'App version', AppConfig.appVersion),
        ]),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
        ),
      ],
    );
  }

  Widget _visitorView(AuthVisitor state) {
    final remaining = state.session.remaining;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const CircleAvatar(
          radius: 36,
          backgroundColor: AppColors.backgroundGray,
          child: Icon(Icons.person, size: 36, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text('Guest Visitor',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              const Text('Session expires in',
                  style: TextStyle(color: AppColors.textSecondary)),
              Text(
                _fmt(remaining),
                style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentGold,
                    letterSpacing: 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.accentGold),
          ),
          child: const Text(
            VisitorText.access,
            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 12),
        _card([
          _tile(Icons.info_outline, 'App version', AppConfig.appVersion),
        ]),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => context.go('/login'),
          child: const Text('Log in with your UM account'),
        ),
      ],
    );
  }

  Widget _card(List<Widget> children) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Card(child: Column(children: children)),
      );

  Widget _tile(IconData icon, String title, String value) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text(value,
            style: const TextStyle(color: AppColors.textSecondary)),
      );
}
