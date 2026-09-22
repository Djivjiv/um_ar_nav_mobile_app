import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/config/maptiler_config.dart';
import '../../../core/constants/app_colors.dart';

/// Full-screen AR walking guide. Tilt the phone UP to see the camera feed
/// with a floating arrow; tilt DOWN to drop into a 2D map. All sensors are
/// optional — the screen degrades to whatever is available.
class ARNavigationScreen extends StatefulWidget {
  final List<LatLng> routePoints;
  final String fromName;
  final String toName;
  final double distanceMeters;
  final LatLng? destinationLatLng;

  const ARNavigationScreen({
    super.key,
    required this.routePoints,
    required this.fromName,
    required this.toName,
    required this.distanceMeters,
    this.destinationLatLng,
  });

  @override
  State<ARNavigationScreen> createState() => _ARNavigationScreenState();
}

class _ARNavigationScreenState extends State<ARNavigationScreen>
    with TickerProviderStateMixin {
  // Camera
  CameraController? _cameraController;
  bool _cameraInitialized = false;
  String? _cameraError;

  // Sensors
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _positionSub;

  double _compassHeading = 0;
  Position? _currentPosition;

  // AR / Map mode (tilt-driven, with hysteresis to stop flicker)
  bool _isARMode = true;
  late final AnimationController _modeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  // Navigation
  int _currentStep = 0;
  double _remainingDistance = 0;
  double _bearingToTarget = 0;

  final MapController _mapController = MapController();
  static const Distance _distance = Distance();

  @override
  void initState() {
    super.initState();
    _remainingDistance = widget.distanceMeters;
    _updateArrowDirection();
    _initCamera();
    _initCompass();
    _initAccelerometer();
    _initGps();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _compassSub?.cancel();
    _accelSub?.cancel();
    _positionSub?.cancel();
    _modeCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────── sensors ───────────────────────────

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No camera on this device');
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
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
      setState(() {
        _compassHeading = h;
        _updateArrowDirection();
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

  void _initGps() {
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _updateProgress(position);
      });
      if (!_isARMode) _recenterMap();
    }, onError: (Object e) => debugPrint('GPS stream error: $e'));
  }

  void _recenterMap() {
    final p = _currentPosition;
    try {
      if (p != null) {
        _mapController.move(LatLng(p.latitude, p.longitude), 17.5);
      }
      _mapController.rotate(-_compassHeading);
    } catch (_) {
      // map not attached yet
    }
  }

  // ─────────────────────── navigation maths ───────────────────────

  LatLng? get _me => _currentPosition == null
      ? null
      : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

  void _updateProgress(Position position) {
    final me = LatLng(position.latitude, position.longitude);
    final pts = widget.routePoints;

    if (pts.length > 1 && _currentStep < pts.length - 1) {
      final d =
          _distance.as(LengthUnit.Meter, me, pts[_currentStep]);
      if (d < 15) _currentStep++;
    }

    final dest = widget.destinationLatLng ??
        (pts.isNotEmpty ? pts.last : null);
    if (dest != null) {
      _remainingDistance = _distance.as(LengthUnit.Meter, me, dest);
    }
    _updateArrowDirection();
  }

  void _updateArrowDirection() {
    final pts = widget.routePoints;
    final source = _me ?? (pts.isNotEmpty ? pts.first : null);
    final target = pts.isNotEmpty
        ? (_currentStep < pts.length - 1
            ? pts[_currentStep + 1]
            : pts.last)
        : widget.destinationLatLng;
    if (source == null || target == null) return;
    _bearingToTarget = _bearing(source, target);
  }

  double _bearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double get _relativeAngle {
    var a = _bearingToTarget - _compassHeading;
    while (a > 180) {
      a -= 360;
    }
    while (a < -180) {
      a += 360;
    }
    return a;
  }

  String get _distanceText {
    if (_remainingDistance >= 1000) {
      return '${(_remainingDistance / 1000).toStringAsFixed(1)} km';
    }
    return '${_remainingDistance.toStringAsFixed(0)} m';
  }

  int get _estimatedMinutes =>
      _remainingDistance <= 0 ? 0 : (_remainingDistance / 84).ceil();

  String _directionText() {
    if (widget.routePoints.isEmpty && widget.destinationLatLng == null) {
      return 'Point the phone around to find your heading';
    }
    final a = _relativeAngle;
    if (a.abs() < 15) return '↑  Head straight';
    if (a >= 15 && a <= 45) return '↗  Bear right';
    if (a > 45 && a <= 135) return '→  Turn right';
    if (a > 135) return '↘  Sharp right';
    if (a <= -15 && a >= -45) return '↖  Bear left';
    if (a < -45 && a >= -135) return '←  Turn left';
    return '↙  Sharp left';
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
          if (_isARMode) _buildARArrow(),
          _buildTopBar(),
          _buildModeIndicator(),
          _buildBottomPanel(),
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
    final center = _me ??
        (widget.routePoints.isNotEmpty
            ? widget.routePoints.first
            : MapTilerConfig.campusCenter);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 17.5,
        minZoom: MapTilerConfig.minZoom,
        maxZoom: MapTilerConfig.maxZoom,
        backgroundColor: AppColors.backgroundGray,
      ),
      children: [
        TileLayer(
          urlTemplate: MapTilerConfig.baseTileUrl,
          userAgentPackageName: MapTilerConfig.userAgentPackageName,
          maxNativeZoom: 19,
          errorTileCallback: (_, _, _) {},
        ),
        TileLayer(
          urlTemplate: MapTilerConfig.umOverlayTileUrl,
          userAgentPackageName: MapTilerConfig.userAgentPackageName,
          maxNativeZoom: 19,
          errorTileCallback: (_, _, _) {},
        ),
        if (widget.routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              if (_currentStep > 0)
                Polyline(
                  points:
                      widget.routePoints.sublist(0, _currentStep + 1),
                  strokeWidth: 4,
                  color: Colors.grey.withValues(alpha: 0.5),
                ),
              Polyline(
                points: widget.routePoints.sublist(_currentStep),
                strokeWidth: 5,
                color: const Color(0xFF1A73E8),
                borderStrokeWidth: 2,
                borderColor: Colors.white,
              ),
            ],
          ),
        if (_me != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _me!,
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
            ],
          ),
        if (widget.destinationLatLng != null)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.destinationLatLng!,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.toName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    Text('$_distanceText away',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
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

  Widget _buildARArrow() {
    final arriving = _remainingDistance > 0 && _remainingDistance < 12;
    return Positioned.fill(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppColors.accentGold.withValues(alpha: 0.5)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.toName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.straighten,
                          color: AppColors.accentGold, size: 14),
                      const SizedBox(width: 4),
                      Text(_distanceText,
                          style: const TextStyle(
                              color: AppColors.accentGold,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      const Icon(Icons.access_time,
                          color: Colors.white60, size: 14),
                      const SizedBox(width: 4),
                      Text('~$_estimatedMinutes min',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            Transform.rotate(
              angle: arriving ? 0 : _relativeAngle * math.pi / 180,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.accentGold.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 5),
                  ],
                ),
                child: Icon(
                    arriving ? Icons.location_on : Icons.navigation,
                    color: Colors.white,
                    size: 60),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                arriving ? '🎉 You have arrived' : _directionText(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
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
            Text(
              _isARMode
                  ? 'Tilt the phone down to see the map'
                  : 'Tilt the phone up for AR view',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
            const SizedBox(height: 12),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _infoChip(Icons.straighten, _distanceText,
                          AppColors.accentGold),
                      _infoChip(Icons.access_time, '~$_estimatedMinutes min',
                          Colors.white70),
                      _infoChip(Icons.explore,
                          '${_compassHeading.toStringAsFixed(0)}°',
                          Colors.white54),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
