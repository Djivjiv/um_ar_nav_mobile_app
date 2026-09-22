import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/models/ar_messages.dart';
import '../../../services/unity_bridge_service.dart';
import 'ar_navigation_screen.dart';

/// AR navigation rendered by a native Unity player (outdoor GPS arrows,
/// indoor node-based arrows) — talks to native code via
/// [UnityBridgeService] (MethodChannel + EventChannel), NOT
/// `flutter_unity_widget` (see the `unity-ar-blocked` project memory for
/// why that package doesn't build here).
///
/// The Unity `.aar` isn't in this repo yet, so today [UnityBridgeService]
/// always reports unavailable and this screen always shows its fallback
/// button to the existing camera+compass [ARNavigationScreen]. Callers
/// should check [UnityBridgeService.isAvailable] *before* pushing this
/// screen (see `map_screen.dart` / `ar_screen.dart`) so users go straight
/// to the working 2D/camera AR instead of hitting a dead-end detour.
class UnityArScreen extends StatefulWidget {
  final List<LatLng> routePoints;
  final String buildingId;
  final String destinationName;
  final String fromName;
  final double distanceMeters;
  final LatLng? destinationLatLng;
  final int? floorNumber;
  final List<ARIndoorNode>? indoorPath;

  const UnityArScreen({
    super.key,
    required this.routePoints,
    required this.buildingId,
    required this.destinationName,
    this.fromName = 'Your location',
    this.distanceMeters = 0,
    this.destinationLatLng,
    this.floorNumber,
    this.indoorPath,
  });

  @override
  State<UnityArScreen> createState() => _UnityArScreenState();
}

class _UnityArScreenState extends State<UnityArScreen> {
  final UnityBridgeService _bridge = UnityBridgeService.instance;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = _bridge.events.listen(_onUnityEvent);
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_bridge.stopNavigation());
    super.dispose();
  }

  Future<void> _start() async {
    final indoorPath = widget.indoorPath;
    final floorNumber = widget.floorNumber;
    final bool ok;
    if (indoorPath != null && floorNumber != null) {
      final message = ARIndoorMessage(
        buildingId: widget.buildingId,
        floorNumber: floorNumber,
        destinationName: widget.destinationName,
        indoorPath: indoorPath,
      );
      ok = await _bridge.startIndoorNavigation(message.toJson());
    } else {
      final message = ARStartMessage(
        buildingId: widget.buildingId,
        destinationName: widget.destinationName,
        outdoorWaypoints: widget.routePoints,
      );
      ok = await _bridge.startOutdoorNavigation(message.toJson());
    }
    if (!mounted) return;
    setState(() {
      _initializing = false;
      if (!ok && _error == null) {
        _error = 'Unity AR isn\'t available on this device yet.';
      }
    });
  }

  void _onUnityEvent(Map<String, dynamic> event) {
    final type = event['event'];
    if (type == 'arrived') {
      _onArrived(event);
    } else if (type == 'qr_scanned') {
      _onQrScanned(event);
    } else if (type == 'error') {
      _onError(event);
    }
  }

  void _onArrived(Map<String, dynamic> event) {
    if (!mounted) return;
    Navigator.of(context).pop();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('You have arrived!'),
        content:
            Text(event['destination']?.toString() ?? widget.destinationName),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onQrScanned(Map<String, dynamic> event) {
    debugPrint('🎮 [UnityAR] QR scanned: $event');
    // TODO(unity): resolve event['nodeId'] to the remaining indoor path and
    // call _bridge.startIndoorNavigation with the next leg.
  }

  void _onError(Map<String, dynamic> event) {
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _error = event['message']?.toString() ?? 'Unity AR error.';
    });
  }

  void _fallbackTo2D() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ARNavigationScreen(
          routePoints: widget.routePoints,
          fromName: widget.fromName,
          toName: widget.destinationName,
          distanceMeters: widget.distanceMeters,
          destinationLatLng: widget.destinationLatLng ??
              (widget.routePoints.isNotEmpty ? widget.routePoints.last : null),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: AppColors.primaryMaroon,
          foregroundColor: Colors.white,
          title: const Text('AR Navigation'),
        ),
        body: Center(
          child: _initializing
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.accentGold),
                    SizedBox(height: 16),
                    Text('Initializing AR…',
                        style: TextStyle(color: Colors.white)),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.view_in_ar_outlined,
                          color: Colors.white38, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        _error ?? 'Unity AR session ended.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _fallbackTo2D,
                        icon: const Icon(Icons.camera_alt,
                            color: AppColors.primaryMaroon),
                        label: const Text('Continue in Camera AR',
                            style:
                                TextStyle(color: AppColors.primaryMaroon)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentGold),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Back',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
