import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';

/// Shown when the device's Location (GPS) service is turned OFF — distinct
/// from a denied permission.
class LocationServiceScreen extends StatefulWidget {
  const LocationServiceScreen({super.key});

  @override
  State<LocationServiceScreen> createState() => _LocationServiceScreenState();
}

class _LocationServiceScreenState extends State<LocationServiceScreen> {
  Future<void> _openSettings() async {
    await Geolocator.openLocationSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
    final on = await Geolocator.isLocationServiceEnabled();
    if (on && mounted) context.go('/');
  }

  Future<void> _checkAgain() async {
    final on = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (on) {
      context.go('/');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Location is still off. Please enable it in settings.'),
          backgroundColor: AppColors.primaryMaroon,
        ),
      );
    }
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
              const SizedBox(height: 40),
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
                child: const Icon(Icons.location_off,
                    size: 50, color: AppColors.primaryMaroon),
              ),
              const SizedBox(height: 24),
              const Text(
                'Location is Turned Off',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please turn on your location to verify you are inside the '
                'University of Mindanao Matina Campus.',
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
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings,
                      color: AppColors.accentGold),
                  label: const Text('Open Location Settings',
                      style: TextStyle(
                          color: AppColors.accentGold,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryMaroon,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _checkAgain,
                  icon: const Icon(Icons.refresh,
                      color: AppColors.primaryMaroon),
                  label: const Text('Check Again',
                      style: TextStyle(
                          color: AppColors.primaryMaroon,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primaryMaroon),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
