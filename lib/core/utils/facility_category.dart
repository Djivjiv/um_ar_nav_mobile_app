import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Colour + icon for a facility category string.
class FacilityCategory {
  FacilityCategory._();

  static String normalize(String? raw) {
    final c = (raw ?? '').trim();
    return c.isEmpty ? 'Other' : c;
  }

  static Color color(String? raw) {
    switch (normalize(raw).toLowerCase()) {
      case 'laboratory':
        return const Color(0xFF534AB7);
      case 'cashier':
        return AppColors.accentGold;
      case 'office':
        return AppColors.infoBlue;
      case 'comfort room':
        return const Color(0xFFE91E8C);
      case 'lecture hall':
        return const Color(0xFF00695C);
      case 'chapel':
        return AppColors.primaryMaroon;
      case 'clinic':
        return AppColors.errorRed;
      case 'library':
        return const Color(0xFF01579B);
      case 'canteen':
        return const Color(0xFFE65100);
      case 'sports':
        return AppColors.successGreen;
      default:
        return AppColors.textSecondary;
    }
  }

  static IconData icon(String? raw) {
    switch (normalize(raw).toLowerCase()) {
      case 'laboratory':
        return Icons.science_outlined;
      case 'cashier':
        return Icons.point_of_sale_outlined;
      case 'office':
        return Icons.badge_outlined;
      case 'comfort room':
        return Icons.wc_outlined;
      case 'lecture hall':
        return Icons.co_present_outlined;
      case 'chapel':
        return Icons.church_outlined;
      case 'clinic':
        return Icons.local_hospital_outlined;
      case 'library':
        return Icons.local_library_outlined;
      case 'canteen':
        return Icons.restaurant_outlined;
      case 'sports':
        return Icons.sports_basketball_outlined;
      default:
        return Icons.meeting_room_outlined;
    }
  }
}
