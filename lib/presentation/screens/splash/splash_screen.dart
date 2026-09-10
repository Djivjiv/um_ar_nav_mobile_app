import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geofence_service.dart';
import '../../bloc/auth/auth_cubit.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final Animation<double> _scale = CurvedAnimation(
    parent: _c,
    curve: Curves.elasticOut,
  );

  @override
  void initState() {
    super.initState();
    // A cold start always re-verifies campus location.
    GeofenceService.campusVerified = false;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    debugPrint('🚀 App bootstrap started');
    debugPrint('   Skip geofence: ${AppConfig.skipGeofenceCheck}');

    // ── STEP 1 — location permission (asked once) ──
    // ── STEP 2 — location service (GPS) must be ON ──
    if (!AppConfig.skipGeofenceCheck) {
      if (!await _ensurePermission()) return;
      if (!mounted) return;
      if (!await _ensureLocationService()) return;
      if (!mounted) return;
    } else {
      debugPrint('⚠️ Geofence skipped — dev mode');
    }

    // ── STEP 3 — resolve the session, then campus-gate valid sessions ──
    await _checkAuthAndNavigate();
  }

  /// Ask for location permission once; route to /location-permission when it
  /// is denied / permanently denied. Returns true when granted.
  Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    debugPrint('🔐 Permission: $permission');
    if (permission == LocationPermission.denied) {
      debugPrint('   Requesting permission...');
      permission = await Geolocator.requestPermission();
      debugPrint('   After request: $permission');
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('❌ Permission not granted → /location-permission');
      if (mounted) context.go('/location-permission');
      return false;
    }
    debugPrint('✅ Permission granted');
    return true;
  }

  /// Route to /location-service-off when the device GPS is off. Returns true
  /// when the service is on.
  Future<bool> _ensureLocationService() async {
    final on = await Geolocator.isLocationServiceEnabled();
    debugPrint('📍 Location service enabled: $on');
    if (!on) {
      debugPrint('❌ Location service OFF → /location-service-off');
      if (mounted) context.go('/location-service-off');
      return false;
    }
    return true;
  }

  Future<void> _checkAuthAndNavigate() async {
    debugPrint('🔐 Checking auth session...');
    final authCubit = context.read<AuthCubit>();

    // Restore an authenticated session if the 8-hour window is still open,
    // otherwise fall back to a still-valid visitor session.
    var restored = await authCubit.tryRestoreTimedSession();
    if (!restored) {
      restored = await authCubit.restoreVisitorSession();
    }
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;
    if (!mounted) return;

    final authState = authCubit.state;
    final isAuthed = authState is AuthAuthenticated;
    final needsRole = authState is AuthNeedsRoleSelection;
    final isVisitor =
        authState is AuthVisitor && authState.session.isStillValid;

    if (!mounted) return;

    if (needsRole) {
      context.go('/select-role');
      return;
    }

    // No valid session → onboarding / login (campus check happens after
    // login instead).
    if (!((restored && isAuthed) || isVisitor)) {
      debugPrint('   No session — going to '
          '${seenOnboarding ? "login" : "onboarding"}');
      context.go(seenOnboarding ? '/login' : '/onboarding');
      return;
    }

    // Valid session → verify the user is physically on campus.
    await _checkCampusAndNavigate();
  }

  Future<void> _checkCampusAndNavigate() async {
    debugPrint('🌍 Checking campus location...');
    if (AppConfig.skipGeofenceCheck) {
      if (mounted) context.go('/map');
      return;
    }
    final inside = await GeofenceService.currentlyInsideCampus();
    if (!mounted) return;
    if (inside == true) GeofenceService.campusVerified = true;
    // inside == null → GPS fix failed; the user has a valid session, so let
    // them in rather than lock them out.
    context.go(inside == false ? '/outside-campus' : '/map');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryMaroon,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: Image.asset(
                  'assets/images/umlogo.png',
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.school,
                    size: 64,
                    color: AppColors.primaryMaroon,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'UM-AR Nav',
              style: TextStyle(
                color: AppColors.accentGold,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'University of Mindanao',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.accentGold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
