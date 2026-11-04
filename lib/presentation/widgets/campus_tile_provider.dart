import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../data/local/campus_tile_cache.dart';

/// Serves campus tiles (see [CampusTileCache.covers]) from the on-disk
/// [CampusTileCache], so the map shows offline after a restart. Every other
/// tile goes to [fallback] (network, possibly with an in-memory cache).
class CampusCachedTileProvider extends TileProvider {
  final CampusTileSource source;
  final TileProvider fallback;
  final CampusTileCache cache;

  CampusCachedTileProvider({
    required this.source,
    required this.fallback,
    CampusTileCache? cache,
  }) : cache = cache ?? CampusTileCache.instance;

  // Both flutter_map's NetworkTileProvider and flutter_map_cache's
  // CachedTileProvider only implement the cancel-loading path.
  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    if (cache.covers(coordinates.z, coordinates.x, coordinates.y)) {
      return CampusTileImage(
          cache, source, coordinates.z, coordinates.x, coordinates.y);
    }
    return fallback.supportsCancelLoading
        ? fallback.getImageWithCancelLoadingSupport(
            coordinates, options, cancelLoading)
        : fallback.getImage(coordinates, options);
  }

  @override
  void dispose() {
    fallback.dispose();
    super.dispose();
  }
}

/// One campus tile, loaded through [CampusTileCache.load].
@immutable
class CampusTileImage extends ImageProvider<CampusTileImage> {
  final CampusTileCache cache;
  final CampusTileSource source;
  final int z, x, y;

  const CampusTileImage(this.cache, this.source, this.z, this.x, this.y);

  @override
  Future<CampusTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          CampusTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: 1,
        debugLabel: '${source.id}/$z/$x/$y',
      );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await cache.load(source, z, x, y);
    return decode(await ui.ImmutableBuffer.fromUint8List(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes)));
  }

  @override
  bool operator ==(Object other) =>
      other is CampusTileImage &&
      other.source.id == source.id &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(source.id, z, x, y);
}
