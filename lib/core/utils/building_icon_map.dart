import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Maps building / facility category strings to Material icons and colors.
class BuildingIconMap {
  BuildingIconMap._();

  static IconData iconForCategory(String? category) {
    switch ((category ?? '').toLowerCase().trim()) {
      case 'academic':
      case 'college':
      case 'classroom':
        return Icons.school;
      case 'services':
      case 'office':
      case 'admin':
      case 'administration':
        return Icons.badge;
      case 'sports':
      case 'gym':
      case 'gymnasium':
      case 'field':
        return Icons.sports_basketball;
      case 'facilities':
      case 'facility':
        return Icons.apartment;
      case 'emergency':
      case 'clinic':
      case 'medical':
        return Icons.local_hospital;
      case 'library':
        return Icons.local_library;
      case 'canteen':
      case 'cafeteria':
      case 'food':
        return Icons.restaurant;
      case 'parking':
        return Icons.local_parking;
      case 'chapel':
      case 'church':
        return Icons.church;
      case 'laboratory':
      case 'lab':
        return Icons.science;
      case 'restroom':
      case 'comfort room':
      case 'cr':
        return Icons.wc;
      case 'atm':
      case 'bank':
        return Icons.atm;
      default:
        return Icons.location_city;
    }
  }

  static Color colorForCategory(String? category) {
    switch ((category ?? '').toLowerCase().trim()) {
      case 'academic':
        return AppColors.primaryMaroon;
      case 'services':
        return AppColors.infoBlue;
      case 'sports':
        return AppColors.successGreen;
      case 'emergency':
        return AppColors.errorRed;
      case 'facilities':
        return AppColors.accentGold;
      default:
        return AppColors.primaryMaroon;
    }
  }

  /// Icon for an indoor node "label" / "type".
  static IconData iconForNodeType(String? type) {
    switch ((type ?? '').toLowerCase().trim()) {
      case 'entrance':
        return Icons.login;
      case 'stairs':
      case 'stair':
        return Icons.stairs;
      case 'elevator':
      case 'lift':
        return Icons.elevator;
      case 'girlsrestroom':
      case 'girls restroom':
      case 'female restroom':
        return Icons.woman;
      case 'boyrestroom':
      case 'boys restroom':
      case 'male restroom':
        return Icons.man;
      case 'pathway':
      case 'hallway':
        return Icons.directions_walk;
      default:
        return Icons.place;
    }
  }

  static Color colorForNodeType(String? type) {
    switch ((type ?? '').toLowerCase().trim()) {
      case 'entrance':
        return AppColors.successGreen;
      case 'pathway':
      case 'hallway':
        return AppColors.accentGold;
      case 'stairs':
      case 'stair':
        return AppColors.primaryMaroon;
      case 'elevator':
      case 'lift':
        return AppColors.infoBlue;
      case 'girlsrestroom':
      case 'girls restroom':
      case 'female restroom':
        return const Color(0xFFE91E8C);
      case 'boyrestroom':
      case 'boys restroom':
      case 'male restroom':
        return AppColors.infoBlue;
      default:
        return AppColors.textSecondary;
    }
  }
}
