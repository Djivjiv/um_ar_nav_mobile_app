import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/connectivity_service.dart';

/// Wraps the whole app: while offline, a slim strip at the top says saved
/// data is shown and when it was last updated. It takes the status-bar
/// space and pushes the page down — it never covers or blocks anything.
class OfflineBanner extends StatelessWidget {
  final Widget child;
  final ConnectivityService connectivity;

  const OfflineBanner({
    super.key,
    required this.child,
    required this.connectivity,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: connectivity,
      builder: (context, _) {
        if (connectivity.isOnline) return child;
        return Column(
          children: [
            Material(
              color: AppColors.textPrimary,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off,
                          size: 16, color: AppColors.accentGold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          offlineMessage(connectivity.dataUpdatedAt),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "Offline: showing saved data, last updated 14:05" (today) or
  /// "…, last updated Oct 27, 14:05".
  static String offlineMessage(DateTime? updatedAt, {DateTime? now}) {
    if (updatedAt == null) return 'Offline: showing saved data';
    final t = updatedAt.toLocal();
    final n = (now ?? DateTime.now()).toLocal();
    final hm = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    final sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
    final when = sameDay ? hm : '${_months[t.month - 1]} ${t.day}, $hm';
    return 'Offline: showing saved data, last updated $when';
  }
}
