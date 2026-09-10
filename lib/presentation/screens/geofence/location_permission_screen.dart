import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geofence_service.dart';

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _isChecking = false;

  Future<void> _enableLocation() async {
    setState(() => _isChecking = true);
    await GeofenceService.openSettings();
    await Future<void>.delayed(const Duration(seconds: 2));
    final result = await GeofenceService.checkUserLocation();
    if (!mounted) return;

    if (result == GeofenceResult.insideCampus) {
      context.go('/map');
    } else if (result == GeofenceResult.permissionDenied) {
      await GeofenceService.openAppSettings();
      if (mounted) setState(() => _isChecking = false);
    } else if (result == GeofenceResult.outsideCampus) {
      context.go('/outside-campus');
    } else {
      setState(() => _isChecking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read your location yet.')),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('visitor_session_id');
    await prefs.remove('login_time');
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGray,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 48),
              Image.asset(
                'assets/images/umlogo.png',
                width: 80,
                height: 80,
                errorBuilder: (_, _, _) => const Icon(Icons.school,
                    size: 80, color: AppColors.primaryMaroon),
              ),
              const SizedBox(height: 24),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_disabled,
                    size: 50, color: AppColors.primaryMaroon),
              ),
              const SizedBox(height: 24),
              const Text(
                'Location Access Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              const Text(
                'UM-AR Nav needs your location to verify you are inside the '
                'University of Mindanao Matina Campus.\n\n'
                'Please enable location access to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isChecking ? null : _enableLocation,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                  AppColors.accentGold)),
                        )
                      : const Icon(Icons.my_location,
                          color: AppColors.accentGold),
                  label: Text(_isChecking ? 'Checking...' : 'Enable Location'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _signOut,
                child: const Text('Sign Out',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
