import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geofence_service.dart';

class OutsideCampusScreen extends StatefulWidget {
  const OutsideCampusScreen({super.key});

  @override
  State<OutsideCampusScreen> createState() => _OutsideCampusScreenState();
}

class _OutsideCampusScreenState extends State<OutsideCampusScreen> {
  bool _isChecking = false;

  Future<void> _retryCheck() async {
    setState(() => _isChecking = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final inside = GeofenceService.isInsideCampus(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      if (inside) {
        context.go('/');
      } else {
        setState(() => _isChecking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Still outside campus. Please go to UM Matina Campus.'),
            backgroundColor: AppColors.primaryMaroon,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isChecking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot get location. Please try again.'),
          backgroundColor: AppColors.primaryMaroon,
        ),
      );
    }
  }

  void _exitApp() => SystemNavigator.pop();

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
                'Outside Campus',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 12),
              const Text(
                'UM-AR Nav is only available inside the University of '
                'Mindanao Matina Campus.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    height: 1.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please go to the campus to use the navigation app.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accentGold),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: const [
                    Icon(Icons.location_on,
                        color: AppColors.accentGold, size: 20),
                    SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('UM Matina Campus',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textPrimary)),
                        Text('Matina, Davao City',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isChecking ? null : _retryCheck,
                  icon: _isChecking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                  AppColors.accentGold)),
                        )
                      : const Icon(Icons.refresh,
                          color: AppColors.accentGold),
                  label: Text(_isChecking ? 'Checking...' : 'Check Again'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _exitApp,
                child: const Text('Exit App',
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
