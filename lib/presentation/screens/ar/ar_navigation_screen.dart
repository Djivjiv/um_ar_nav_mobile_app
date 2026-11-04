import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/ar_nav_config.dart';
import '../../../core/config/maptiler_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../data/local/campus_tile_cache.dart';
import '../../../data/models/building_model.dart';
import '../../../data/models/facility_model.dart';
import '../../../data/models/room_model.dart';
import '../../../data/repositories/building_repository.dart';
import '../../../data/repositories/facility_repository.dart';
import '../../../data/repositories/outdoor_ar_repository.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/services/ar_info_overlay.dart';
import '../../../domain/services/ar_network_routing.dart';
import '../../../domain/services/ar_route_geometry.dart';
import '../../../domain/services/off_route_tracker.dart';
import '../../bloc/navigation/navigation_session_logger.dart';
import '../../bloc/navigation/outdoor_nav_cubit.dart';
import '../../widgets/ar_info_card.dart';
import '../../widgets/arrival_feedback.dart';
import '../../widgets/campus_tile_provider.dart';
import '../../widgets/dev_coordinate_panel.dart';

/// Full-screen, location-based AR walking guide.
///
/// The route follows the AR path network (`outdoor_ar_nodes` /
/// `outdoor_ar_edges`), or the route points every 6 m when the network has
/// no path. Each GPS fix is smoothed, snapped onto that polyline, and a
/// target waypoint
/// [lookAheadMeters] further along the route is chosen. The camera overlay
/// places a marker on that target using the smoothed compass heading and
/// the camera's horizontal FOV, so the guidance follows the walkway around
/// corners instead of pointing straight at the destination.
///
/// Tilt the phone UP for the camera view, DOWN for a 2D map. All sensors
/// are optional — the screen degrades to whatever is available.
class ARNavigationScreen extends StatefulWidget {
  final List<LatLng> routePoints;
  final String fromName;
  final String toName;
  final double distanceMeters;
  final LatLng? destinationLatLng;

  /// Graph node ids of [routePoints] (from `OutdoorNavState.pathNodeIds`).
  /// Used to find the destination building when [destinationBuildingId]
  /// is not given, and for analytics.
  final List<String> routeNodeIds;

  /// Destination building (for `ar_emoji` / `ar_label` /
  /// `ar_arrival_radius_m`). Falls back to the last route node's building.
  final int? destinationBuildingId;

  /// The destination when it is a room or facility (`'room'` /
  /// `'facility'` + its id), for the information card. Null for a building.
  final String? destinationType;
  final String? destinationId;

  /// The coordinates panel and the long-press tuning overlay.
  final bool devTools;

  /// Distance ahead of the snapped position the target waypoint sits.
  static const double lookAheadMeters = ArNavConfig.lookAheadMeters;

  const ARNavigationScreen({
    super.key,
    required this.routePoints,
    required this.fromName,
    required this.toName,
    required this.distanceMeters,
    this.destinationLatLng,
    this.routeNodeIds = const [],
    this.destinationBuildingId,
    this.destinationType,
    this.destinationId,
    this.devTools = kDevCoordinateTools,
  });

  @override
  State<ARNavigationScreen> createState() => _ARNavigationScreenState();
}

class _ARNavigationScreenState extends State<ARNavigationScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Camera
  CameraController? _cameraController;
  bool _cameraInitialized = false;
  String? _cameraError;

  /// True while [_initCamera] is running, so a resume can't start a second
  /// initialisation in parallel.
  bool _cameraInitializing = false;

  /// True while the app is in the background — the camera stays released.
  bool _inBackground = false;

  /// `navigation_sessions` logging (only when there is a real route).
  NavigationSessionLogger? _analytics;

  // Sensors
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _positionSub;

  /// Where the top of the device points (used to rotate the 2D map).
  double _compassHeading = 0;

  /// Where the back camera points, raw and low-pass filtered.
  double? _rawCameraHeading;
  double? _smoothedHeading;
  final HeadingSmoother _headingSmoother = HeadingSmoother();

  Position? _currentPosition;
  LatLng? _smoothedPosition;
  final PositionSmoother _positionSmoother = PositionSmoother();

  // AR / Map mode (tilt-driven, with hysteresis to stop flicker)
  bool _isARMode = true;
  late final AnimationController _modeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  // Route
  late List<LatLng> _routePoints = widget.routePoints;
  late List<String> _routeNodeIds = widget.routeNodeIds;
  late LatLng? _destination = widget.destinationLatLng ??
      (widget.routePoints.isNotEmpty ? widget.routePoints.last : null);
  late DenseRoute _route = densifyPolyline(widget.routePoints);
  int _routeGeneration = 0;
  String _routeSource = 'route points (loading AR network…)';
  BuildingModel? _building;

  // Guidance
  SnapResult? _snap;
  LatLng? _target;
  int? _targetSegment;
  double _remainingDistance = 0;
  double? _distanceToDestination;
  bool _offRoute = false;

  /// Off-route state + the count of separate deviations (error rate).
  final OffRouteTracker _offRouteTracker = OffRouteTracker();

  // Information card: the destination or another building, when near it.
  ArPlaceInfo? _info;
  int? _infoBuildingId;
  bool _infoForDestination = false;
  bool _infoExpanded = false;
  List<BuildingModel>? _allBuildings;

  /// Places the user closed the card for; it stays closed for that place.
  final Set<int> _dismissedInfoIds = {};

  bool get _showInfo =>
      _info != null && !_dismissedInfoIds.contains(_infoBuildingId);

  /// Measured height of the bottom panel, which the direction arrow stays
  /// above.
  final GlobalKey _bottomPanelKey = GlobalKey();
  double _bottomPanelHeight = 0;

  bool _rerouting = false;
  String? _rerouteError;
  bool _arrived = false;
  bool _showDebug = false;

  final MapController _mapController = MapController();
  static const Distance _distance = Distance();

  // Campus tiles from the on-disk cache, so the 2D view works offline.
  late final TileProvider _baseTiles = CampusCachedTileProvider(
      source: CampusTileSource.base, fallback: NetworkTileProvider());
  late final TileProvider _overlayTiles = CampusCachedTileProvider(
      source: CampusTileSource.overlay, fallback: NetworkTileProvider());

  bool get _hasRoute => _route.isUsable;

  double get _arrivalRadius =>
      _building?.arArrivalRadiusM ?? ArNavConfig.defaultArrivalRadiusMeters;

  String get _markerEmoji => _building?.arEmoji ?? ArNavConfig.defaultEmoji;

  String get _markerLabel => _building?.arLabel ?? widget.toName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConnectivityService.instance.addListener(_onConnectivityChange);
    _remainingDistance = widget.distanceMeters;
    if (widget.routePoints.length >= 2) {
      _analytics = NavigationSessionLogger.of(
        context,
        mode: TripMode.ar,
        totalSteps: _plannedSteps(),
        fromNode: widget.routeNodeIds.isNotEmpty
            ? widget.routeNodeIds.first
            : 'unknown',
        toNode: widget.routeNodeIds.isNotEmpty
            ? widget.routeNodeIds.last
            : (widget.destinationBuildingId != null
                ? 'building:${widget.destinationBuildingId}'
                : 'unknown'),
        fromName: widget.fromName,
        toName: widget.toName,
        distanceMeters: widget.distanceMeters,
      )..start();
    }
    _initCamera();
    _initCompass();
    _initAccelerometer();
    _initGps();
    // After the first frame: these may call setState synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadDenseRoute();
      _loadBuilding();
    });
  }

  void _onConnectivityChange() {
    if (mounted) setState(() {});
  }

  /// Turn-by-turn steps of the planned route (error-rate denominator): the
  /// outdoor route's instructions, else its segments.
  int _plannedSteps() {
    try {
      final n = context.read<OutdoorNavCubit>().state.instructions.length;
      if (n > 0) return n;
    } catch (_) {}
    return widget.routePoints.length - 1;
  }

  @override
  void dispose() {
    // Left without arriving → an "abandoned" end row (no-op if completed).
    _analytics?.abandon();
    WidgetsBinding.instance.removeObserver(this);
    ConnectivityService.instance.removeListener(_onConnectivityChange);
    _cameraController?.dispose();
    _compassSub?.cancel();
    _accelSub?.cancel();
    _positionSub?.cancel();
    _modeCtrl.dispose();
    super.dispose();
  }

  /// Releases the camera when the app leaves the foreground (so other apps
  /// can use it and it stops draining the battery) and re-opens it on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _inBackground = true;
        _releaseCamera();
      case AppLifecycleState.resumed:
        _inBackground = false;
        if (_cameraController == null && !_cameraInitializing) _initCamera();
      case AppLifecycleState.detached:
        break;
    }
  }

  void _releaseCamera() {
    final controller = _cameraController;
    if (controller == null) return;
    if (mounted) {
      setState(() {
        _cameraController = null;
        _cameraInitialized = false;
      });
    } else {
      _cameraController = null;
      _cameraInitialized = false;
    }
    controller.dispose();
  }

  // ─────────────────────────── sensors ───────────────────────────

  Future<void> _initCamera() async {
    if (_cameraInitializing) return;
    _cameraInitializing = true;
    var droppedForBackground = false;
    try {
      droppedForBackground = await _openCamera();
    } finally {
      _cameraInitializing = false;
    }
    // The app came back while the dropped controller was being disposed —
    // the resume handler skipped re-opening, so do it now.
    if (droppedForBackground && mounted && !_inBackground) _initCamera();
  }

  /// Returns true when the controller was discarded because the app went to
  /// the background during initialisation.
  Future<bool> _openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No camera on this device');
        return false;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      // Closed, or sent to the background while initialising.
      if (!mounted || _inBackground) {
        await controller.dispose();
        return mounted;
      }
      setState(() {
        _cameraController = controller;
        _cameraInitialized = true;
        _cameraError = null;
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() {
          _cameraError = 'Camera unavailable — use the 2D map instead';
          _isARMode = false;
          _modeCtrl.value = 1;
        });
      }
    }
    return false;
  }

  void _initCompass() {
    final events = FlutterCompass.events;
    if (events == null) {
      debugPrint('Compass not available on this device');
      return;
    }
    _compassSub = events.listen((event) {
      final h = event.heading;
      if (h == null || !mounted) return;
      // headingForCameraMode = where the back camera points (phone held
      // upright); falls back to the top-of-device heading.
      final camera = event.headingForCameraMode ?? h;
      setState(() {
        _compassHeading = h;
        _rawCameraHeading = camera;
        _smoothedHeading = _headingSmoother.add(camera);
      });
    }, onError: (Object e) => debugPrint('Compass error: $e'));
  }

  void _initAccelerometer() {
    _accelSub = accelerometerEventStream().listen((event) {
      // Pitch: ~0° when the phone lies flat, ~90° when held upright.
      final pitch = math.atan2(
            event.z,
            math.sqrt(event.x * event.x + event.y * event.y),
          ) *
          180 /
          math.pi;
      // Hysteresis: need >25° to enter AR, <15° to drop to map.
      final wantAR = _isARMode ? pitch > 15 : pitch > 25;
      if (wantAR != _isARMode) _setMode(wantAR);
    }, onError: (Object e) => debugPrint('Accelerometer error: $e'));
  }

  void _setMode(bool ar) {
    if (!mounted || _cameraError != null && ar) return;
    setState(() => _isARMode = ar);
    if (ar) {
      _modeCtrl.reverse();
    } else {
      _modeCtrl.forward();
      _recenterMap();
    }
  }

  LocationSettings _locationSettings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: ArNavConfig.gpsDistanceFilterMeters,
          intervalDuration: ArNavConfig.gpsInterval,
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: ArNavConfig.gpsDistanceFilterMeters,
          activityType: ActivityType.fitness,
          allowBackgroundLocationUpdates: false,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: ArNavConfig.gpsDistanceFilterMeters,
        );
    }
  }

  void _initGps() {
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings(),
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _smoothedPosition = _positionSmoother
            .add(LatLng(position.latitude, position.longitude));
        _updateGuidance();
      });
      if (!_isARMode) _recenterMap();
      final me = _smoothedPosition;
      if (me != null) _updatePlaceInfo(me);
    }, onError: (Object e) => debugPrint('GPS stream error: $e'));
  }

  void _recenterMap() {
    final p = _smoothedPosition;
    try {
      if (p != null) _mapController.move(p, 17.5);
      _mapController.rotate(-_compassHeading);
    } catch (_) {
      // map not attached yet
    }
  }

  // ─────────────────────────── route data ───────────────────────────

  /// Replaces the initial polyline with a path over the AR path network
  /// (`outdoor_ar_nodes` / `outdoor_ar_edges`, cached by
  /// [OutdoorArRepository]): nearest AR node to the route start → the AR
  /// node linked to the destination building. With no such path it keeps
  /// the route points with 6 m fill-in (see [planArRoute]).
  Future<void> _loadDenseRoute() async {
    final generation = ++_routeGeneration;
    if (_routePoints.length < 2) {
      setState(() => _routeSource = 'no route (compass mode)');
      return;
    }

    final arRepo = context.read<OutdoorArRepository>();
    final buildingId = await _destinationBuildingId();
    if (!mounted || generation != _routeGeneration) return;

    ArNetwork network;
    String? loadError;
    try {
      network = await arRepo.getNetwork();
    } catch (e) {
      debugPrint('AR network load failed: $e');
      network = const ArNetwork(nodes: [], edges: []);
      loadError = 'AR network unavailable';
    }
    if (!mounted || generation != _routeGeneration) return;

    final plan = planArRoute(
      nodes: network.nodes,
      edges: network.edges,
      fallbackRoutePoints: _routePoints,
      routeStart: _routePoints.first,
      destinationBuildingId: buildingId,
    );
    debugPrint('🧭 ${plan.description}');
    if (!plan.route.isUsable) {
      setState(() => _routeSource = '${plan.description} — unusable');
      return;
    }
    setState(() {
      _route = plan.route;
      _snap = null;
      _routeSource = loadError == null
          ? plan.description
          : 'AR network: no path, using route points ($loadError)';
      _updateGuidance();
    });
  }

  /// The destination building: from the caller, else the building of the
  /// outdoor route's last graph node.
  Future<int?> _destinationBuildingId() async {
    final id = widget.destinationBuildingId;
    if (id != null || _routeNodeIds.isEmpty) return id;
    final nav = context.read<OutdoorNavCubit>();
    await nav.ensureGraph();
    final lastId = _routeNodeIds.last;
    for (final n in nav.repo.nodes) {
      if (n.id == lastId) return n.buildingId;
    }
    return null;
  }

  Future<void> _loadBuilding() async {
    final id = await _destinationBuildingId();
    if (!mounted || id == null) return;
    try {
      final b = await context.read<BuildingRepository>().getBuildingById(id);
      if (!mounted || b == null) return;
      setState(() => _building = b);
    } catch (e) {
      debugPrint('AR building lookup failed: $e');
    }
  }

  /// Fills the information card for [building] from the offline-cached
  /// room / facility repositories. Missing data just hides lines.
  Future<void> _loadInfo(BuildingModel building,
      {required bool isDestination}) async {
    // The same building again only if its destination details haven't
    // arrived since (the first GPS fix can beat _loadBuilding).
    if (_infoBuildingId == building.id &&
        _infoForDestination == isDestination) {
      return;
    }
    _infoBuildingId = building.id;
    _infoForDestination = isDestination;
    final type = isDestination ? widget.destinationType : null;
    var rooms = const <RoomModel>[];
    var facilities = const <FacilityModel>[];
    try {
      if (type == 'room') {
        rooms = await context
            .read<RoomRepository>()
            .getRoomsForBuilding(building.id);
      } else if (type == 'facility') {
        facilities = await context
            .read<FacilityRepository>()
            .getFacilitiesForBuilding(building.id);
      }
    } catch (e) {
      debugPrint('AR info: details unavailable ($e)');
    }
    if (!mounted || _infoBuildingId != building.id) return;
    setState(() {
      _info = selectArPlaceInfo(
        building: building,
        isDestination: isDestination,
        placeType: type,
        placeId: isDestination ? widget.destinationId : null,
        rooms: rooms,
        facilities: facilities,
      );
      _infoExpanded = false;
    });
  }

  /// Shows the card for the place the user is near: the destination (with
  /// its room / facility details) or a building passed on the way. Buildings
  /// come from the offline cache, so this works without a connection; with
  /// nothing cached there is simply no card.
  Future<void> _updatePlaceInfo(LatLng me) async {
    try {
      _allBuildings ??= await context.read<BuildingRepository>().getBuildings();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final destinationId = _building?.id;
    final b = arInfoBuilding(
      buildings: _allBuildings!,
      position: me,
      destinationId: destinationId,
      metersToDestination: _arrived ? 0 : _distanceToDestination,
      currentId: _infoBuildingId,
    );
    if (b == null) {
      if (_info != null || _infoBuildingId != null) {
        setState(() {
          _info = null;
          _infoBuildingId = null;
          _infoExpanded = false;
        });
      }
      return;
    }
    await _loadInfo(b, isDestination: b.id == destinationId);
  }

  // ─────────────────────── guidance maths ───────────────────────

  /// Snap → look-ahead target → off-route / arrival checks. Call inside
  /// setState whenever the position or route changes.
  void _updateGuidance() {
    final me = _smoothedPosition;
    if (me == null) return;
    final dest = _destination;

    _distanceToDestination =
        dest == null ? null : _distance.as(LengthUnit.Meter, me, dest);

    if (_hasRoute) {
      final snap =
          _route.snap(me, previousDistanceAlong: _snap?.distanceAlong);
      final target = _route.lookAheadTarget(snap,
          lookAheadMeters: ARNavigationScreen.lookAheadMeters);
      _snap = snap;
      _target = target.point;
      _targetSegment = target.segmentIndex;
      _remainingDistance =
          math.max(0, _route.totalLength - snap.distanceAlong);

      if (!_arrived) {
        // Each separate deviation is one navigation error.
        if (_offRouteTracker.update(snap.distanceFromRoute,
            accuracyMeters: _currentPosition?.accuracy)) {
          _analytics?.recordOffRoute();
        } else if (_offRouteTracker.tracked) {
          _analytics?.markOffRouteTracked();
        }
        _offRoute = _offRouteTracker.offRoute;
      }

      final d = _distanceToDestination;
      if (!_arrived && d != null && d <= _arrivalRadius) {
        _markArrived(manual: false);
      }
    } else {
      // No route (AR compass mode): point straight at the destination.
      _target = dest;
      _targetSegment = null;
      _remainingDistance = _distanceToDestination ?? 0;
    }
  }

  /// Arrival: automatically within the arrival radius, or [manual] when
  /// the user confirms "I have arrived" because GPS never got that close.
  /// Call inside setState.
  void _markArrived({required bool manual}) {
    if (_arrived) return;
    _arrived = true;
    _offRoute = false;
    _offRouteTracker.reset();
    HapticFeedback.mediumImpact();
    _analytics?.complete(manual: manual);
  }

  Future<void> _confirmArrivedManually() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Have you arrived?'),
        content: Text(
            'Only confirm if you are at ${widget.toName} but the app '
            "hasn't detected it. This trip will be saved as confirmed by you."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not yet')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('I have arrived')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => _markArrived(manual: true));
      final me = _smoothedPosition;
      if (me != null) _updatePlaceInfo(me);
    }
  }

  /// Bearing from the user to [p] relative to where the camera points
  /// (-180..180, positive = right). Null without a position or heading.
  double? _relativeBearingTo(LatLng? p) {
    final me = _smoothedPosition;
    final heading = _smoothedHeading;
    if (me == null || heading == null || p == null) return null;
    return normalizeAngle180(bearingBetween(me, p) - heading);
  }

  Future<void> _reroute() async {
    final me = _smoothedPosition;
    if (me == null || _rerouting) return;
    setState(() {
      _rerouting = true;
      _rerouteError = null;
    });
    final cubit = context.read<OutdoorNavCubit>();
    final ok = await cubit.rerouteFrom(me);
    if (!mounted) return;
    final s = cubit.state;
    setState(() {
      _rerouting = false;
      if (ok && s.path.length >= 2) {
        _analytics?.recordReroute();
        _offRouteTracker.reset();
        _routePoints = s.path;
        _routeNodeIds = s.pathNodeIds;
        _destination = s.path.last;
        _route = densifyPolyline(s.path);
        _routeSource = 'route points (loading AR network…)';
        _snap = null;
        _offRoute = false;
        _updateGuidance();
      } else {
        _rerouteError = s.error ?? "Couldn't find a new route.";
      }
    });
    if (ok) _loadDenseRoute();
  }

  String get _distanceText => _formatMeters(_remainingDistance);

  static String _formatMeters(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '${m.toStringAsFixed(0)} m';
  }

  int get _estimatedMinutes =>
      _remainingDistance <= 0 ? 0 : (_remainingDistance / 84).ceil();

  String _directionText() {
    if (_routePoints.isEmpty && widget.destinationLatLng == null) {
      return 'Point the phone around to find your heading';
    }
    if (_smoothedPosition == null) return 'Waiting for GPS…';
    final a = _relativeBearingTo(_target);
    if (a == null) return 'Waiting for compass…';
    if (a.abs() < 15) return '↑  Head straight';
    if (a >= 15 && a <= 45) return '↗  Bear right';
    if (a > 45 && a <= 135) return '→  Turn right';
    if (a > 135) return '↘  Turn around (right)';
    if (a <= -15 && a >= -45) return '↖  Bear left';
    if (a < -45 && a >= -135) return '←  Turn left';
    return '↙  Turn around (left)';
  }

  // ─────────────────────────── arrival ───────────────────────────

  void _openSurvey() {
    final router = GoRouter.of(context);
    final tripId = _analytics?.tripId;
    Navigator.of(context).pop();
    router.push('/survey', extra: {'navigation_session_id': tripId});
  }

  void _returnToMap() {
    try {
      context.read<OutdoorNavCubit>().clearRoute();
    } catch (e) {
      debugPrint('Clear route: $e');
    }
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/map');
  }

  // ─────────────────────────── build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _modeCtrl,
            builder: (context, _) => Stack(
              children: [
                Opacity(
                  opacity: 1 - _modeCtrl.value,
                  child: IgnorePointer(
                    ignoring: !_isARMode,
                    child: _buildCameraView(),
                  ),
                ),
                Opacity(
                  opacity: _modeCtrl.value,
                  child: IgnorePointer(
                    ignoring: _isARMode,
                    child: _buildMapView(),
                  ),
                ),
              ],
            ),
          ),
          if (_isARMode) _buildArOverlay(),
          _buildTopBar(),
          _buildModeIndicator(),
          if (_offRoute && !_arrived) _buildOffRouteBanner(),
          if (widget.devTools && _showDebug) _buildDebugOverlay(),
          if (widget.devTools) _buildCoordinatePanel(),
          _arrived ? _buildArrivalPanel() : _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (_cameraError != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_outlined,
                    color: Colors.white38, size: 56),
                const SizedBox(height: 12),
                Text(_cameraError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      );
    }
    if (!_cameraInitialized || _cameraController == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.accentGold),
              SizedBox(height: 16),
              Text('Initializing camera…',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
    return SizedBox.expand(child: CameraPreview(_cameraController!));
  }

  Widget _buildMapView() {
    final center = _smoothedPosition ??
        (_routePoints.isNotEmpty
            ? _routePoints.first
            : MapTilerConfig.campusCenter);
    final snap = _snap;
    final pts = _route.points;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 17.5,
        minZoom: MapTilerConfig.minZoomFor(
            online: ConnectivityService.instance.isOnline),
        maxZoom: MapTilerConfig.maxZoom,
        backgroundColor: AppColors.backgroundGray,
      ),
      children: [
        TileLayer(
          urlTemplate: MapTilerConfig.baseTileUrl,
          userAgentPackageName: MapTilerConfig.userAgentPackageName,
          maxNativeZoom: 19,
          tileProvider: _baseTiles,
          errorTileCallback: (_, _, _) {},
        ),
        TileLayer(
          urlTemplate: MapTilerConfig.umOverlayTileUrl,
          userAgentPackageName: MapTilerConfig.userAgentPackageName,
          maxNativeZoom: 19,
          tileProvider: _overlayTiles,
          errorTileCallback: (_, _, _) {},
        ),
        if (_hasRoute)
          PolylineLayer(
            polylines: [
              if (snap != null)
                Polyline(
                  points: [...pts.sublist(0, snap.segmentIndex + 1), snap.point],
                  strokeWidth: 4,
                  color: Colors.grey.withValues(alpha: 0.5),
                ),
              Polyline(
                points: snap == null
                    ? pts
                    : [snap.point, ...pts.sublist(snap.segmentIndex + 1)],
                strokeWidth: 5,
                color: const Color(0xFF1A73E8),
                borderStrokeWidth: 2,
                borderColor: Colors.white,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (_target != null && _hasRoute && !_arrived)
              Marker(
                point: _target!,
                width: 14,
                height: 14,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accentGold,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            if (_smoothedPosition != null)
              Marker(
                point: _smoothedPosition!,
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A73E8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            if (_destination != null)
              Marker(
                point: _destination!,
                width: 40,
                height: 50,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on,
                    color: AppColors.primaryMaroon, size: 40),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Long-press the title to toggle the tuning overlay.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: widget.devTools
                      ? () {
                          HapticFeedback.selectionClick();
                          setState(() => _showDebug = !_showDebug);
                        }
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.toName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      Text(
                          _arrived
                              ? 'You have arrived'
                              : '$_distanceText away',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _setMode(!_isARMode),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          _isARMode
                              ? Icons.map_outlined
                              : Icons.camera_alt_outlined,
                          color: Colors.white,
                          size: 16),
                      const SizedBox(width: 4),
                      Text(_isARMode ? '2D Map' : 'AR',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
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

  Widget _buildModeIndicator() {
    return Positioned(
      top: 96,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isARMode
                ? Colors.black.withValues(alpha: 0.6)
                : AppColors.primaryMaroon.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_isARMode ? Icons.camera_alt : Icons.map,
                  color: AppColors.accentGold, size: 14),
              const SizedBox(width: 6),
              Text(
                _isARMode
                    ? 'AR Mode — tilt down for Map'
                    : 'Map Mode — tilt up for AR',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Camera-view overlay: the look-ahead target marker (or an edge arrow
  /// when it is outside the FOV), a destination marker when in view, and
  /// the direction arrow.
  Widget _buildArOverlay() {
    if (_arrived) {
      return const Positioned.fill(
        child: IgnorePointer(
          child: Center(child: Text('🎉', style: TextStyle(fontSize: 96))),
        ),
      );
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;
            final children = <Widget>[];

            final targetRel = _relativeBearingTo(_target);
            if (targetRel != null) {
              final x = screenXForRelativeBearing(targetRel, w);
              if (x != null) {
                const markerWidth = 180.0;
                children.add(Positioned(
                  left: (x - markerWidth / 2).clamp(0.0, math.max(0.0, w - markerWidth)),
                  top: h * 0.30,
                  width: markerWidth,
                  child: _TargetMarker(
                    emoji: _markerEmoji,
                    label: _markerLabel,
                    distance: _distanceText,
                  ),
                ));
              } else {
                children.add(_EdgeArrow(
                  onLeft: targetRel < 0,
                  top: h * 0.40,
                ));
              }
            }

            // Final destination marker, only when it is a separate point
            // from the look-ahead target and inside the FOV.
            final destDistance = _distanceToDestination;
            if (_hasRoute &&
                destDistance != null &&
                destDistance > ARNavigationScreen.lookAheadMeters + 2) {
              final destRel = _relativeBearingTo(_destination);
              final xd = destRel == null
                  ? null
                  : screenXForRelativeBearing(destRel, w);
              if (xd != null) {
                const markerWidth = 150.0;
                children.add(Positioned(
                  left: (xd - markerWidth / 2).clamp(0.0, math.max(0.0, w - markerWidth)),
                  top: h * 0.17,
                  width: markerWidth,
                  child: _DestinationMarker(
                    emoji: _markerEmoji,
                    label: _markerLabel,
                    distance: _formatMeters(destDistance),
                  ),
                ));
              }
            }

            children.add(Positioned(
              left: 0,
              right: 0,
              top: arDirectionTop(h, _bottomPanelHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                    angle: (targetRel ?? 0) * math.pi / 180,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppColors.accentGold.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color:
                                  AppColors.accentGold.withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 5),
                        ],
                      ),
                      child: const Icon(Icons.navigation,
                          color: Colors.white, size: 50),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _directionText(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ));

            return Stack(children: children);
          },
        ),
      ),
    );
  }

  Widget _buildOffRouteBanner() {
    final off = _snap?.distanceFromRoute;
    return Positioned(
      top: 132,
      left: 16,
      right: 16,
      child: Material(
        color: AppColors.errorRed.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.wrong_location, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("You're off the route",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    Text(
                      _rerouteError ??
                          (off == null
                              ? 'Head back to the walkway'
                              : '${off.toStringAsFixed(0)} m from the walkway'),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _rerouting ? null : _reroute,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.errorRed,
                ),
                child: _rerouting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.errorRed),
                      )
                    : const Text('Re-route',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebugOverlay() {
    final p = _currentPosition;
    final s = _smoothedPosition;
    final snap = _snap;
    final me = _smoothedPosition;
    final targetDist = (me != null && _target != null)
        ? _distance.as(LengthUnit.Meter, me, _target!)
        : null;
    String deg(double? v) => v == null ? '—' : '${v.toStringAsFixed(0)}°';
    String m(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} m';
    String ll(double lat, double lng) =>
        '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

    final lines = <String>[
      'GPS acc   ${p == null ? '—' : '±${p.accuracy.toStringAsFixed(1)} m'}'
          '  (${_positionSmoother.sampleCount}/${ArNavConfig.gpsSmoothingWindow} fixes)',
      'raw pos   ${p == null ? '—' : ll(p.latitude, p.longitude)}',
      'smooth    ${s == null ? '—' : ll(s.latitude, s.longitude)}',
      'heading   raw ${deg(_rawCameraHeading)}  smooth ${deg(_smoothedHeading)}'
          '  top ${deg(_compassHeading)}',
      'rel→tgt   ${deg(_relativeBearingTo(_target))}'
          '  (FOV ${ArNavConfig.cameraHorizontalFovDeg.toStringAsFixed(0)}°)',
      'off route ${m(snap?.distanceFromRoute)}'
          '  (limit ${ArNavConfig.offRouteMeters.toStringAsFixed(0)} m)'
          '${_offRoute ? '  OFF' : ''}',
      'target    ${m(targetDist)}'
          '  (look-ahead ${ARNavigationScreen.lookAheadMeters.toStringAsFixed(0)} m)',
      'index     snap ${snap?.segmentIndex ?? '—'}'
          '  target ${_targetSegment ?? '—'}'
          '  / ${math.max(0, _route.points.length - 1)} segs',
      'along     ${m(snap?.distanceAlong)} / ${m(_route.totalLength)}',
      'dest      ${m(_distanceToDestination)}'
          '  (arrive ≤ ${_arrivalRadius.toStringAsFixed(0)} m)',
      'route     $_routeSource',
    ];

    return Positioned(
      top: 132 + (_offRoute && !_arrived ? 70 : 0),
      left: 8,
      right: 8,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            lines.join('\n'),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontFamily: 'monospace',
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  /// Below the off-route banner and the tuning overlay, when they are up.
  /// Shows the raw fix, not the smoothed one, and uses this screen's GPS and
  /// compass so its own readings are left alone.
  Widget _buildCoordinatePanel() {
    final p = _currentPosition;
    return Positioned(
      top: 132 + (_offRoute && !_arrived ? 70 : 0) + (_showDebug ? 190 : 0),
      left: 8,
      child: DevCoordinatePanel(
        latitude: p?.latitude,
        longitude: p?.longitude,
        accuracy: p?.accuracy,
        heading: _rawCameraHeading == null ? null : _compassHeading,
      ),
    );
  }

  Widget _buildArrivalPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(context).padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 8),
            const Text('You have arrived',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryMaroon)),
            const SizedBox(height: 4),
            Text(widget.toName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _buildInfoCard(dark: false),
            const SizedBox(height: 6),
            ArrivalFeedback(
              tripId: _analytics?.tripId,
              onRate: () async => _openSurvey(),
              rateButton: (onPressed) => ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                ),
                child: const Text('Rate your experience'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _returnToMap,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
              child: const Text('Return to Map'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final height = _bottomPanelKey.currentContext?.size?.height;
      if (mounted && height != null && height != _bottomPanelHeight) {
        setState(() => _bottomPanelHeight = height);
      }
    });
    // An open card takes the place of these lines, leaving room for the arrow.
    final compact = _isARMode && _infoExpanded && _showInfo;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        key: _bottomPanelKey,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildInfoCard(dark: true),
            if (!compact) ...[
              Text(
                _isARMode
                    ? 'Tilt the phone down to see the map'
                    : 'Tilt the phone up for AR view',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  if (!compact) ...[
                    Row(
                      children: [
                        const Icon(Icons.radio_button_checked,
                            color: AppColors.successGreen, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(widget.fromName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: AppColors.primaryMaroon, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(widget.toName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24, height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _infoChip(Icons.straighten, _distanceText,
                          AppColors.accentGold),
                      _infoChip(Icons.access_time, '~$_estimatedMinutes min',
                          Colors.white70),
                      _infoChip(Icons.explore,
                          '${(_smoothedHeading ?? _compassHeading).toStringAsFixed(0)}°',
                          Colors.white54),
                    ],
                  ),
                  if (_hasRoute && _analytics != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _confirmArrivedManually,
                        icon: const Icon(Icons.flag_outlined,
                            size: 16, color: Colors.white70),
                        label: const Text('I have arrived',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The information card, or nothing when there is no data or the user
  /// closed it. Lives in the bottom panel; [arDirectionTop] keeps the AR
  /// arrow above it.
  Widget _buildInfoCard({required bool dark}) {
    final info = _info;
    if (info == null || !_showInfo) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ArInfoCard(
        info: info,
        dark: dark,
        expanded: _infoExpanded,
        maxExpandedHeight:
            MediaQuery.of(context).size.height * (dark ? 0.14 : 0.2),
        onToggle: () => setState(() => _infoExpanded = !_infoExpanded),
        onClose: () => setState(() {
          _dismissedInfoIds.add(_infoBuildingId!);
          _infoExpanded = false;
        }),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Floating marker on the look-ahead target: building emoji, label and
/// remaining route distance.
class _TargetMarker extends StatelessWidget {
  final String emoji;
  final String label;
  final String distance;

  const _TargetMarker({
    required this.emoji,
    required this.label,
    required this.distance,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accentGold, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 34)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              Text(distance,
                  style: const TextStyle(
                      color: AppColors.accentGold,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        // Pointer stem toward the walkway.
        Container(width: 2, height: 26, color: AppColors.accentGold),
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: AppColors.accentGold,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

/// Smaller marker for the final destination when it is inside the FOV.
class _DestinationMarker extends StatelessWidget {
  final String emoji;
  final String label;
  final String distance;

  const _DestinationMarker({
    required this.emoji,
    required this.label,
    required this.distance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryMaroon.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white70),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Flexible(
            child: Text('$label · $distance',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Shown at the screen edge when the target is outside the camera FOV.
class _EdgeArrow extends StatelessWidget {
  final bool onLeft;
  final double top;

  const _EdgeArrow({required this.onLeft, required this.top});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: onLeft ? 8 : null,
      right: onLeft ? null : 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accentGold),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(onLeft ? Icons.chevron_left : Icons.chevron_right,
                color: AppColors.accentGold, size: 44),
            Text(onLeft ? 'Turn left' : 'Turn right',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
