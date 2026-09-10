import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/building_model.dart';

/// Google-Maps-style white-haloed text label for a building.
class BuildingLabelMarker {
  BuildingLabelMarker._();

  static Marker build(BuildingModel building, VoidCallback onTap) {
    return Marker(
      point: building.location,
      width: 140,
      height: 40,
      alignment: Alignment.center,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(
          building.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1A1A1A),
            shadows: [
              Shadow(color: Colors.white, blurRadius: 6, offset: Offset(0, 0)),
            ],
          ),
        ),
      ),
    );
  }

  /// Small maroon dot shown for buildings when zoomed out past the label zoom.
  static Marker dot(BuildingModel building, VoidCallback onTap) {
    return Marker(
      point: building.location,
      width: 16,
      height: 16,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primaryMaroon,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }
}
