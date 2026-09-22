import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/maptiler_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/unity_bridge_service.dart';
import '../../bloc/navigation/outdoor_nav_cubit.dart';
import 'ar_navigation_screen.dart';
import 'unity_ar_screen.dart';

/// The AR tab — a launcher for the full-screen [ARNavigationScreen]. It shows
/// the current route (if any) and starts AR guidance; with no route it can
/// still open an AR compass pointed at the campus.
class ArScreen extends StatelessWidget {
  const ArScreen({super.key});

  Future<void> _launch(BuildContext context, OutdoorNavState nav) async {
    final hasRoute = nav.hasRoute && nav.path.length >= 2;
    final routePoints = hasRoute ? nav.path : const <LatLng>[];
    final fromName =
        hasRoute ? (nav.from?.label ?? 'Your location') : 'Your location';
    final toName =
        hasRoute ? (nav.to?.label ?? 'Destination') : 'UM Matina Campus';
    final distanceMeters = hasRoute ? nav.distanceMeters : 0.0;
    final destinationLatLng =
        hasRoute ? nav.path.last : MapTilerConfig.campusCenter;
    final useUnity =
        hasRoute && await UnityBridgeService.instance.isAvailable();
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => useUnity
            ? UnityArScreen(
                routePoints: routePoints,
                buildingId: nav.to?.buildingId?.toString() ?? '',
                destinationName: toName,
                fromName: fromName,
                distanceMeters: distanceMeters,
                destinationLatLng: destinationLatLng,
              )
            : ARNavigationScreen(
                routePoints: routePoints,
                fromName: fromName,
                toName: toName,
                distanceMeters: distanceMeters,
                destinationLatLng: destinationLatLng,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OutdoorNavCubit, OutdoorNavState>(
      builder: (context, nav) {
        final hasRoute = nav.hasRoute && nav.path.length >= 2;
        return Scaffold(
          backgroundColor: AppColors.backgroundGray,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.view_in_ar,
                        size: 56, color: AppColors.primaryMaroon),
                  ),
                  const SizedBox(height: 20),
                  const Text('AR Navigation',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Text(
                    hasRoute
                        ? 'Follow a floating arrow through your camera. '
                            'Tilt the phone down any time to see the 2D map.'
                        : 'Plan a route on the Map tab first, then come back '
                            'here for a guided AR walk.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  if (hasRoute)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.accentGold),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.route,
                              color: AppColors.accentGold, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(nav.to?.label ?? 'Destination',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary)),
                                Text(
                                  '${nav.distanceMeters.toStringAsFixed(0)} m'
                                  '  ·  ~${nav.walkMinutes} min walk',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () => _launch(context, nav),
                      icon: const Icon(Icons.camera_alt,
                          color: AppColors.accentGold),
                      label: Text(
                        hasRoute
                            ? 'Start AR Navigation'
                            : 'Open AR Compass',
                        style: const TextStyle(
                            color: AppColors.accentGold,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryMaroon,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  if (!hasRoute) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => context.go('/map'),
                      child: const Text('Go to Map',
                          style:
                              TextStyle(color: AppColors.primaryMaroon)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
