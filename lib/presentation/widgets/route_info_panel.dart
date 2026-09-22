import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../bloc/navigation/outdoor_nav_cubit.dart';

/// White card shown above the bottom nav when a route is active.
class RouteInfoPanel extends StatelessWidget {
  final OutdoorNavState state;
  final VoidCallback onStart;
  final VoidCallback onClear;
  final VoidCallback? onARNavigation;

  const RouteInfoPanel({
    super.key,
    required this.state,
    required this.onStart,
    required this.onClear,
    this.onARNavigation,
  });

  @override
  Widget build(BuildContext context) {
    final from = state.from?.label ?? 'Start';
    final to = state.to?.label ?? 'Destination';
    final dist = state.distanceMeters >= 1000
        ? '${(state.distanceMeters / 1000).toStringAsFixed(2)} km'
        : '${state.distanceMeters.round()} m';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.backgroundGray,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          _row(Icons.circle, AppColors.successGreen, 'From', from),
          const Padding(
            padding: EdgeInsets.only(left: 7),
            child: SizedBox(
              height: 14,
              child: VerticalDivider(width: 2, thickness: 1),
            ),
          ),
          _row(Icons.location_on, AppColors.primaryMaroon, 'To', to),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat(dist, 'distance', AppColors.textPrimary, bold: true),
              const SizedBox(width: 16),
              _stat('${state.walkMinutes} min', 'walk', AppColors.accentGold),
              const SizedBox(width: 16),
              _stat('${state.waypointCount}', 'waypoints',
                  AppColors.googleMapsBlue),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: state.hasRoute ? onStart : null,
            icon: const Icon(Icons.navigation, color: AppColors.accentGold),
            label: const Text('Start Navigation',
                style: TextStyle(
                    color: AppColors.accentGold,
                    fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryMaroon,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed:
                state.hasRoute ? (onARNavigation ?? () {}) : null,
            icon: const Icon(Icons.view_in_ar,
                color: AppColors.primaryMaroon),
            label: const Text('AR Navigation',
                style: TextStyle(
                    color: AppColors.primaryMaroon,
                    fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentGold,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onClear,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryMaroon,
              side: const BorderSide(color: AppColors.primaryMaroon),
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Clear Route'),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 10),
        Text('$label: ',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _stat(String value, String label, Color color, {bool bold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                fontSize: 15)),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}
