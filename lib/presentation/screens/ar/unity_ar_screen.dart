import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/models/ar_messages.dart';
import '../../../services/unity_bridge_service.dart';
import '../../bloc/navigation/navigation_session_logger.dart';
import '../../bloc/navigation/outdoor_nav_cubit.dart';
import '../../widgets/arrival_feedback.dart';
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

  /// Graph node ids of [routePoints] — handed to the camera AR fallback so
  /// it can find the destination building for the AR path network.
  final List<String> routeNodeIds;

  /// The real bridge when null.
  final UnityBridgeService? bridge;

  const UnityArScreen({
    super.key,
    this.bridge,
    required this.routePoints,
    required this.buildingId,
    required this.destinationName,
    this.fromName = 'Your location',
    this.distanceMeters = 0,
    this.destinationLatLng,
    this.floorNumber,
    this.indoorPath,
    this.routeNodeIds = const [],
  });

  @override
  State<UnityArScreen> createState() => _UnityArScreenState();
}

class _UnityArScreenState extends State<UnityArScreen> {
  late final UnityBridgeService _bridge =
      widget.bridge ?? UnityBridgeService.instance;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _initializing = true;
  String? _error;

  /// Where Unity says the user arrived; null until then.
  String? _arrivedAt;

  /// `navigation_sessions` logging, once Unity has really started the trip.
  /// The camera AR fallback logs its own trip. Unity reports no off-route
  /// data, so these rows stay `off_route_tracked = false`.
  NavigationSessionLogger? _analytics;

  @override
  void initState() {
    super.initState();
    _sub = _bridge.events.listen(_onUnityEvent);
    _start();
  }

  @override
  void dispose() {
    // Left without arriving → an "abandoned" end row (no-op if completed).
    _analytics?.abandon();
    _sub?.cancel();
    if (_arrivedAt == null) unawaited(_bridge.stopNavigation());
    super.dispose();
  }

  Future<void> _start() async {
    final indoorPath = widget.indoorPath;
    final floorNumber = widget.floorNumber;
    final bool ok;
    if (!await _bridge.isAvailable()) {
      ok = false;
    } else if (indoorPath != null && floorNumber != null) {
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
    if (ok) {
      _analytics = NavigationSessionLogger.of(
        context,
        mode: TripMode.ar,
        totalSteps: indoorPath?.length ?? widget.routePoints.length - 1,
        fromNode: widget.routeNodeIds.firstOrNull ?? 'unknown',
        toNode:
            widget.routeNodeIds.lastOrNull ?? 'building:${widget.buildingId}',
        fromName: widget.fromName,
        toName: widget.destinationName,
        distanceMeters: widget.distanceMeters,
      )..start();
    }
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

  /// Only a trip Unity really started can arrive, so this stays off while
  /// Unity is unavailable.
  void _onArrived(Map<String, dynamic> event) {
    final trip = _analytics;
    if (trip == null || _arrivedAt != null) return;
    trip.complete();
    unawaited(_bridge.stopNavigation());
    if (!mounted) return;
    setState(() {
      _arrivedAt = event['destination']?.toString() ?? widget.destinationName;
    });
  }

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
          routeNodeIds: widget.routeNodeIds,
          destinationBuildingId: int.tryParse(widget.buildingId),
        ),
      ),
    );
  }

  /// The arrival flow of the camera AR screen: the SUS once per person, then
  /// the optional comment, both from [ArrivalFeedback].
  Widget _buildArrivalPanel(String destination) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
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
              Text(destination,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final arrivedAt = _arrivedAt;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: AppColors.primaryMaroon,
          foregroundColor: Colors.white,
          title: const Text('AR Navigation'),
        ),
        body: arrivedAt != null
            ? _buildArrivalPanel(arrivedAt)
            : Center(
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
