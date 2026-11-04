import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Downloads floor plan images into the same on-disk cache that
/// [CachedNetworkImage] / [CachedNetworkImageProvider] read from, so indoor
/// maps display without a connection. Files are stored but not decoded.
class FloorPlanImageCache {
  FloorPlanImageCache._();
  static final FloorPlanImageCache instance = FloorPlanImageCache._();

  /// URLs already confirmed on disk during this app run.
  final Set<String> _onDisk = {};

  /// Fetches every not-yet-cached URL, one at a time. Never throws.
  Future<void> prefetch(Iterable<String?> urls) async {
    for (final url in urls) {
      if (url == null || url.isEmpty || _onDisk.contains(url)) continue;
      try {
        // Returns the cached file when present and fresh; downloads otherwise.
        await CachedNetworkImageProvider.defaultCacheManager
            .getSingleFile(url)
            .timeout(const Duration(seconds: 60));
        _onDisk.add(url);
      } catch (e) {
        debugPrint('🖼 Could not cache floor plan image $url: $e');
      }
    }
  }
}
