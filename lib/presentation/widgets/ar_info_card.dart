import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../domain/services/ar_info_overlay.dart';

/// Compact place-information card for the AR screen: one line collapsed
/// (title + the most useful fact), tap to expand, ✕ to close. Lines with no
/// data are not shown.
class ArInfoCard extends StatelessWidget {
  final ArPlaceInfo info;

  /// Light text on a dark translucent card (over the camera) or the reverse.
  final bool dark;
  final bool expanded;
  final double maxExpandedHeight;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  const ArInfoCard({
    super.key,
    required this.info,
    required this.onToggle,
    required this.onClose,
    this.dark = true,
    this.expanded = false,
    this.maxExpandedHeight = 160,
  });

  /// The single fact shown while collapsed.
  static String? summary(ArPlaceInfo i) =>
      i.access ?? i.description ?? i.hours ?? i.contact;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppColors.textPrimary;
    final muted = dark ? Colors.white70 : AppColors.textSecondary;
    final line = summary(info);

    Widget row(IconData icon, String text, {Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 14, color: color ?? muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 12, color: color ?? fg)),
              ),
            ],
          ),
        );

    return Material(
      color: dark
          ? Colors.black.withValues(alpha: 0.75)
          : AppColors.backgroundGray,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.accentGold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: info.title,
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: fg)),
                        if (!info.isDestination)
                          TextSpan(
                              text: '  · nearby',
                              style: TextStyle(color: muted)),
                        if (!expanded && line != null)
                          TextSpan(
                              text: '\n$line',
                              style: TextStyle(color: muted)),
                      ]),
                      style: const TextStyle(fontSize: 12),
                      maxLines: expanded ? 2 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: muted),
                  IconButton(
                    tooltip: 'Hide information',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: onClose,
                    icon: Icon(Icons.close, color: muted),
                  ),
                ],
              ),
              if (expanded)
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxExpandedHeight),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (info.access != null)
                          row(Icons.lock_outline, info.access!,
                              color: AppColors.accentGold),
                        if (info.description != null)
                          row(Icons.notes, info.description!),
                        if (info.hours != null)
                          row(Icons.access_time, info.hours!),
                        if (info.contact != null)
                          row(Icons.call_outlined, info.contact!),
                        for (final s in info.services)
                          row(Icons.check_circle_outline, s),
                        for (final s in info.instructions)
                          row(Icons.rule, s),
                      ],
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
