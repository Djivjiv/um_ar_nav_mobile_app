import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/maptiler_config.dart';
import '../../core/constants/app_colors.dart';
import '../../core/network/connectivity_service.dart';
import '../../data/local/campus_tile_cache.dart';
import '../../data/models/building_model.dart';
import 'building_label_marker.dart';
import 'campus_tile_provider.dart';

/// Shared FlutterMap wrapper: MapTiler base + UM overlay, cached tiles,
/// constrained camera, rotation disabled, and Google-Maps-style building
/// labels that appear at [MapTilerConfig.buildingLabelZoom].
class UmMapWidget extends StatefulWidget {
  final MapController controller;
  final List<BuildingModel> buildings;
  final ValueChanged<BuildingModel>? onBuildingTap;
  final List<Polyline> polylines;
  final List<Marker> extraMarkers;

  /// Extra FlutterMap layer widgets inserted above the polyline layer
  /// (e.g. a custom animated route overlay). Rendered as-is.
  final List<Widget> extraLayers;
  final LatLng? initialCenter;
  final double initialZoom;
  final bool showLabels;
  final VoidCallback? onMapReady;
  final void Function(MapCamera camera)? onCameraChanged;

  /// Defaults to [ConnectivityService.instance].
  final ConnectivityService? connectivity;

  const UmMapWidget({
    super.key,
    required this.controller,
    this.buildings = const [],
    this.onBuildingTap,
    this.polylines = const [],
    this.extraMarkers = const [],
    this.extraLayers = const [],
    this.initialCenter,
    this.initialZoom = 17.5,
    this.showLabels = true,
    this.onMapReady,
    this.onCameraChanged,
    this.connectivity,
  });

  @override
  State<UmMapWidget> createState() => _UmMapWidgetState();
}

class _UmMapWidgetState extends State<UmMapWidget> {
  /// Memory-only cache for tiles outside the campus (lost on restart).
  /// Campus tiles at zoom 16–19 are kept on disk by [CampusTileCache].
  static final CacheStore _cacheStore = MemCacheStore();

  // Built once per widget — not in build() — so frequent rebuilds (e.g. an
  // animated route overlay) don't spawn a new Dio client every frame.
  late final TileProvider _baseTileProvider = CampusCachedTileProvider(
    source: CampusTileSource.base,
    fallback: CachedTileProvider(
      maxStale: const Duration(days: 30),
      store: _cacheStore,
    ),
  );
  late final TileProvider _overlayTileProvider = CampusCachedTileProvider(
    source: CampusTileSource.overlay,
    fallback: CachedTileProvider(
      maxStale: const Duration(days: 30),
      store: _cacheStore,
    ),
  );

  double _zoom = 17.5;

  late final ConnectivityService _connectivity =
      widget.connectivity ?? ConnectivityService.instance;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
    _connectivity.addListener(_onConnectivityChange);
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChange);
    super.dispose();
  }

  void _onConnectivityChange() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _keepToSavedTiles());
  }

  /// Offline, a map zoomed out below the saved tiles moves back in to them.
  void _keepToSavedTiles() {
    if (!mounted || _connectivity.isOnline) return;
    final camera = widget.controller.camera;
    if (camera.zoom < MapTilerConfig.offlineMinZoom) {
      widget.controller.move(camera.center, MapTilerConfig.offlineMinZoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showText =
        widget.showLabels && _zoom >= MapTilerConfig.buildingLabelZoom;

    // Buildings render only as Google-Maps-style text labels (when zoomed in
    // enough). No dot markers — the campus map never shows node/point dots.
    final buildingMarkers = showText
        ? widget.buildings
            .map((b) => BuildingLabelMarker.build(
                  b,
                  () => widget.onBuildingTap?.call(b),
                ))
            .toList()
        : <Marker>[];

    return FlutterMap(
      mapController: widget.controller,
      options: MapOptions(
        initialCenter: widget.initialCenter ?? MapTilerConfig.campusCenter,
        initialZoom: widget.initialZoom,
        minZoom: MapTilerConfig.minZoomFor(online: _connectivity.isOnline),
        maxZoom: MapTilerConfig.maxZoom,
        backgroundColor: AppColors.backgroundGray,
        cameraConstraint: CameraConstraint.contain(
          bounds: MapTilerConfig.cameraBounds,
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _keepToSavedTiles();
          widget.onMapReady?.call();
        },
        onPositionChanged: (camera, _) {
          widget.onCameraChanged?.call(camera);
          // Only rebuild when zoom crosses the label show/hide threshold —
          // NOT on every zoom delta — so panning/zooming never lags.
          const threshold = MapTilerConfig.buildingLabelZoom;
          final crossed = (camera.zoom >= threshold) != (_zoom >= threshold);
          if (crossed) {
            setState(() => _zoom = camera.zoom);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: MapTilerConfig.baseTileUrl,
          userAgentPackageName: MapTilerConfig.userAgentPackageName,
          maxNativeZoom: 19,
          tileProvider: _baseTileProvider,
          errorTileCallback: (tile, error, stackTrace) {},
        ),
        TileLayer(
          urlTemplate: MapTilerConfig.umOverlayTileUrl,
          userAgentPackageName: MapTilerConfig.userAgentPackageName,
          maxNativeZoom: 19,
          tileProvider: _overlayTileProvider,
          errorTileCallback: (tile, error, stackTrace) {},
        ),
        if (widget.polylines.isNotEmpty)
          PolylineLayer(polylines: widget.polylines),
        ...widget.extraLayers,
        if (buildingMarkers.isNotEmpty || widget.extraMarkers.isNotEmpty)
          MarkerLayer(markers: [...buildingMarkers, ...widget.extraMarkers]),
        const _AttributionBadge(),
      ],
    );
  }
}

class _AttributionBadge extends StatelessWidget {
  const _AttributionBadge();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 6, bottom: 2),
        child: Text(
          '© MapTiler © OpenStreetMap',
          style: TextStyle(fontSize: 9, color: Colors.black54),
        ),
      ),
    );
  }
}
