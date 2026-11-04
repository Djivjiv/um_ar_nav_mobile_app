import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/services/instruction_service.dart';
import '../../bloc/navigation/outdoor_nav_cubit.dart';
import '../../routes/app_router.dart';
import '../../widgets/arrival_feedback.dart';
import '../../widgets/exit_navigation_dialog.dart';
import '../../widgets/navigation_path_painter.dart';
import '../../widgets/um_map_widget.dart';

class TurnByTurnScreen extends StatefulWidget {
  final TurnByTurnArgs? args;

  /// When true (destination is a room / facility), the outdoor leg is only
  /// one phase of a longer journey: show a bottom "I'm at &lt;building&gt;
  /// Entrance" bar instead of the normal arrival panel.
  final bool hasMorePhases;
  final String? destBuildingName;
  final VoidCallback? onArrivedAtBuilding;

  /// Called when the user steps onto the final (arrival) step of a trip
  /// with no further phases.
  final VoidCallback? onArrived;

  /// `navigation_sessions.trip_id` of this trip, if it is logged.
  final String? tripId;

  const TurnByTurnScreen({
    super.key,
    this.args,
    this.hasMorePhases = false,
    this.destBuildingName,
    this.onArrivedAtBuilding,
    this.onArrived,
    this.tripId,
  });

  @override
  State<TurnByTurnScreen> createState() => _TurnByTurnScreenState();
}

class _TurnByTurnScreenState extends State<TurnByTurnScreen>
    with TickerProviderStateMixin {
  final MapController _map = MapController();
  bool _overview = false;
  bool _rotationEnabled = true;

  // Drives the "marching ants" dash animation on the active segment.
  late final AnimationController _dashCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  // Drives smooth camera morphing between steps.
  late final AnimationController _cameraCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  Animation<LatLng>? _centerAnim;
  Animation<double>? _zoomAnim;
  Animation<double>? _rotationAnim;

  // Local fallback if the cubit has no active route.
  List<LatLng> _path = const [];
  List<NavigationInstruction> _instructions = const [];
  int _localStep = 0;
  bool _useLocal = false;

  @override
  void initState() {
    super.initState();
    final nav = context.read<OutdoorNavCubit>().state;
    if (!nav.hasRoute && widget.args != null) {
      _useLocal = true;
      _path = widget.args!.path;
      _instructions = InstructionService.generateInstructions(
        _path,
        widget.args!.nodes,
        destinationName: widget.args!.destinationName,
      );
    }

    _cameraCtrl.addListener(_tickCamera);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _animateCameraToCurrentStep());
  }

  @override
  void dispose() {
    _dashCtrl.dispose();
    _cameraCtrl
      ..removeListener(_tickCamera)
      ..dispose();
    super.dispose();
  }

  // ── data helpers ──────────────────────────────────────────

  List<LatLng> get _activePath =>
      _useLocal ? _path : context.read<OutdoorNavCubit>().state.path;

  List<NavigationInstruction> get _steps => _useLocal
      ? _instructions
      : context.read<OutdoorNavCubit>().state.instructions;

  int get _step => _useLocal
      ? _localStep
      : context.read<OutdoorNavCubit>().state.currentStep;

  bool get _isLastStep => _step >= _steps.length - 1;

  /// Every route point covered by the current (merged) step.
  List<LatLng> _activeSlice(int step) {
    final steps = _steps;
    if (steps.isEmpty) return const [];
    final s = steps[step.clamp(0, steps.length - 1)];
    if (s.segmentPoints.length >= 2) return s.segmentPoints;
    return _activePath.length >= 2
        ? _activePath.sublist(_activePath.length - 2)
        : const [];
  }

  // ── stepping ──────────────────────────────────────────────

  void _next() {
    if (_step < _steps.length - 1) {
      if (_useLocal) {
        setState(() => _localStep++);
      } else {
        context.read<OutdoorNavCubit>().nextStep();
      }
      _animateCameraToCurrentStep();
      if (_isLastStep && !widget.hasMorePhases) widget.onArrived?.call();
    }
  }

  void _prev() {
    if (_step > 0) {
      if (_useLocal) {
        setState(() => _localStep--);
      } else {
        context.read<OutdoorNavCubit>().previousStep();
      }
      _animateCameraToCurrentStep();
    }
  }

  void _toggleOverview() {
    setState(() => _overview = !_overview);
    if (_overview) {
      _fitWholeRoute();
    } else {
      _animateCameraToCurrentStep();
    }
  }

  // ── camera ────────────────────────────────────────────────

  void _tickCamera() {
    final c = _centerAnim, z = _zoomAnim, r = _rotationAnim;
    if (c == null || z == null || r == null) return;
    try {
      _map.moveAndRotate(c.value, z.value, r.value);
    } catch (_) {/* map not ready yet */}
  }

  void _fitWholeRoute() {
    final path = _activePath;
    if (path.length < 2) return;
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(path),
        padding: const EdgeInsets.all(60),
      ));
    } catch (_) {}
  }

  void _smoothMoveTo({
    required LatLng target,
    required double zoom,
    required double rotation,
  }) {
    final MapCamera camera;
    try {
      camera = _map.camera;
    } catch (_) {
      return;
    }

    // North-up when rotation is locked; otherwise take the shortest angular
    // path so the map never sweeps the long way through 360°.
    final wanted = _rotationEnabled ? rotation : 0.0;
    final endRotation = _shortestRotation(camera.rotation, wanted);

    final curve =
        CurvedAnimation(parent: _cameraCtrl, curve: Curves.easeInOutCubic);
    _centerAnim = _LatLngTween(begin: camera.center, end: target).animate(curve);
    _zoomAnim = Tween<double>(begin: camera.zoom, end: zoom).animate(curve);
    _rotationAnim = Tween<double>(
      begin: camera.rotation,
      end: endRotation,
    ).animate(curve);
    _cameraCtrl.forward(from: 0);
  }

  /// Returns [to] expressed relative to [from] using the shortest turn, so a
  /// tween between them never rotates more than 180°.
  static double _shortestRotation(double from, double to) {
    var diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return from + diff;
  }

  void _animateCameraToCurrentStep() {
    if (_overview) return;
    final steps = _steps;
    if (steps.isEmpty) return;
    final instruction = steps[_step.clamp(0, steps.length - 1)];
    final points = instruction.segmentPoints.isNotEmpty
        ? instruction.segmentPoints
        : _activeSlice(_step);
    if (points.isEmpty) return;

    var avgLat = 0.0, avgLng = 0.0;
    for (final p in points) {
      avgLat += p.latitude;
      avgLng += p.longitude;
    }
    avgLat /= points.length;
    avgLng /= points.length;

    var zoom = 18.0;
    if (instruction.distanceMeters > 200) {
      zoom = 16.5;
    } else if (instruction.distanceMeters > 100) {
      zoom = 17.0;
    }

    // Rotate so the direction of travel points up (flutter_map rotates by
    // the negative of the heading).
    final heading = points.length >= 2
        ? _calculateBearing(points.first, points.last)
        : 0.0;

    _smoothMoveTo(
      target: LatLng(avgLat, avgLng),
      zoom: zoom,
      rotation: -heading,
    );
  }

  static double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitudeInRad;
    final lat2 = to.latitudeInRad;
    final dLng = to.longitudeInRad - from.longitudeInRad;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  // ── build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OutdoorNavCubit, OutdoorNavState>(
      builder: (context, _) {
        final steps = _steps;
        if (steps.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Navigation')),
            body: const Center(child: Text('No active route.')),
          );
        }
        final step = _step.clamp(0, steps.length - 1);
        final current = steps[step];
        final next = step < steps.length - 1 ? steps[step + 1] : null;
        final isArrival = current.direction == 'arrive';

        // When the trip continues indoors, the final outdoor step means the
        // user has reached the BUILDING ENTRANCE — not the room yet.
        final entranceArrival = isArrival && widget.hasMorePhases;
        final entranceText =
            'You have arrived at ${widget.destBuildingName ?? 'the building'} '
            'Entrance';

        // Completed (grey) + upcoming (faded) legs, split at the current
        // (merged) step; the bright active leg is the marching-ants overlay.
        final path = _activePath;
        final fromIdx = current.fromIndex.clamp(0, path.length - 1);
        final toIdx = current.toIndex.clamp(0, path.length - 1);
        final polylines = <Polyline>[
          if (toIdx < path.length - 1)
            Polyline(
              points: path.sublist(toIdx),
              strokeWidth: 4,
              color: kRouteBlue.withValues(alpha: 0.55),
              borderStrokeWidth: 1.5,
              borderColor: Colors.white.withValues(alpha: 0.7),
            ),
          if (fromIdx > 0)
            Polyline(
              points: path.sublist(0, fromIdx + 1),
              strokeWidth: 5,
              color: Colors.grey.withValues(alpha: 0.8),
              borderStrokeWidth: 1.5,
              borderColor: Colors.white,
            ),
        ];
        final activeSlice = _activeSlice(step);

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: UmMapWidget(
                  controller: _map,
                  polylines: polylines,
                  extraMarkers:
                      NavigationPathPainter.endpointMarkers(_activePath),
                  extraLayers: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _dashCtrl,
                        builder: (context, _) => _MarchingAnts(
                          points: activeSlice,
                          phase: _dashCtrl.value,
                        ),
                      ),
                    ),
                  ],
                  showLabels: false,
                  initialCenter: _activePath.isNotEmpty
                      ? _activePath.first
                      : null,
                  initialZoom: 18,
                ),
              ),

              // dim overlay
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.05),
                  ),
                ),
              ),

              // top bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: AppColors.primaryMaroon),
                        onPressed: () => _confirmAndExit(context),
                      ),
                      const Text('Turn-by-Turn',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryMaroon)),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          setState(
                              () => _rotationEnabled = !_rotationEnabled);
                          _animateCameraToCurrentStep();
                        },
                        icon: Icon(
                          _rotationEnabled
                              ? Icons.navigation
                              : Icons.explore,
                          color: _rotationEnabled
                              ? AppColors.accentGold
                              : AppColors.primaryMaroon,
                        ),
                        tooltip: _rotationEnabled
                            ? 'Rotation ON'
                            : 'Rotation OFF',
                      ),
                      TextButton.icon(
                        onPressed: _toggleOverview,
                        icon: Icon(_overview ? Icons.navigation : Icons.map),
                        label: Text(_overview ? 'Navigate' : 'Overview'),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),

              // direction card — morphs on step change
              Positioned(
                top: 70,
                left: 16,
                right: 16,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.3, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    )),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: isArrival && !entranceArrival
                      ? const SizedBox.shrink()
                      : _DirectionCard(
                          key: ValueKey(step),
                          current: current,
                          next: next,
                          step: step,
                          total: steps.length,
                          overrideText: entranceArrival ? entranceText : null,
                          showEntrancePin: entranceArrival,
                        ),
                ),
              ),

              // bottom panel
              Positioned(
                left: 0,
                right: 0,
                bottom: widget.hasMorePhases && _isLastStep ? 62 : 0,
                child: isArrival && !widget.hasMorePhases
                    ? _ArrivalPanel(
                        name: current.landmark,
                        tripId: widget.tripId,
                        onSurvey: () async {
                          await context.push('/survey');
                        },
                        onDone: () => _returnToMap(context),
                      )
                    : _BottomPanel(
                        stepKey: step,
                        current: current,
                        next: next,
                        totalDistance: _totalRemaining(steps, step),
                        onPrev: step > 0 ? _prev : null,
                        onNext: _next,
                        overrideCurrentText:
                            entranceArrival ? entranceText : null,
                      ),
              ),

              // "I'm at the building" bar — only when the trip continues
              // indoors after this outdoor leg, and only on the final step
              // (once the user has reached the building entrance).
              if (widget.hasMorePhases && _isLastStep)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: double.infinity,
                    color: AppColors.primaryMaroon,
                    padding: EdgeInsets.fromLTRB(
                        16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
                    child: ElevatedButton.icon(
                      onPressed: widget.onArrivedAtBuilding,
                      icon: const Icon(Icons.check_circle_outline,
                          color: AppColors.primaryMaroon),
                      label: Text(
                        "I'm at ${widget.destBuildingName ?? 'the building'} "
                        'Entrance',
                        style: const TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.successGreen,
                        minimumSize: const Size(double.infinity, 46),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Back arrow: same "Exit Navigation?" confirmation as the other
  /// navigation screens. `Navigator.pop` (not `maybePop`) so that, when this
  /// screen is embedded in MultiPhaseNavScreen, its PopScope doesn't ask a
  /// second time.
  Future<void> _confirmAndExit(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (await confirmExitNavigation(context)) navigator.pop();
  }

  /// Dismiss whatever is stacked on top of the map (this screen may be a
  /// go_router page OR embedded in a MultiPhaseNavScreen route), clear the
  /// route, then show the map.
  void _returnToMap(BuildContext context) {
    try {
      context.read<OutdoorNavCubit>().clearRoute();
    } catch (e) {
      debugPrint('Clear route: $e');
    }
    final router = GoRouter.of(context);
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
    router.go('/map');
  }

  double _totalRemaining(List<NavigationInstruction> steps, int from) {
    double d = 0;
    for (var i = from; i < steps.length; i++) {
      d += steps[i].distanceMeters;
    }
    return d;
  }
}

/// Linear interpolation between two [LatLng]s for smooth camera moves.
class _LatLngTween extends Tween<LatLng> {
  _LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) => LatLng(
        begin!.latitude + (end!.latitude - begin!.latitude) * t,
        begin!.longitude + (end!.longitude - begin!.longitude) * t,
      );
}

class _DirectionCard extends StatelessWidget {
  final NavigationInstruction current;
  final NavigationInstruction? next;
  final int step;
  final int total;

  /// Overrides [current.instructionText] (used for the building-entrance
  /// arrival on the last outdoor step when more phases follow).
  final String? overrideText;
  final bool showEntrancePin;

  const _DirectionCard({
    super.key,
    required this.current,
    required this.next,
    required this.step,
    required this.total,
    this.overrideText,
    this.showEntrancePin = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                  showEntrancePin
                      ? Icons.location_on
                      : current.directionIcon,
                  size: 60,
                  color: showEntrancePin
                      ? AppColors.successGreen
                      : AppColors.primaryMaroon),
              const SizedBox(height: 10),
              Text(overrideText ?? current.instructionText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
              if (next != null) ...[
                const SizedBox(height: 6),
                Text('Then: ${InstructionService.label(next!.direction)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 10),
              _Dots(step: step, total: total),
              const SizedBox(height: 2),
              Text('Step ${step + 1} of $total',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int step;
  final int total;
  const _Dots({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final shown = total > 10 ? 10 : total;
    final activeIndex = step > 9 ? 9 : step;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(shown, (i) {
        final isActive = i == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          width: isActive ? 20 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primaryMaroon
                : const Color(0xFFD9C9B0),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _BottomPanel extends StatefulWidget {
  final int stepKey;
  final NavigationInstruction current;
  final NavigationInstruction? next;
  final double totalDistance;
  final VoidCallback? onPrev;
  final VoidCallback onNext;

  /// Replaces the "Current: …" line (building-entrance arrival text).
  final String? overrideCurrentText;

  const _BottomPanel({
    required this.stepKey,
    required this.current,
    required this.next,
    required this.totalDistance,
    required this.onPrev,
    required this.onNext,
    this.overrideCurrentText,
  });

  @override
  State<_BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<_BottomPanel> {
  bool _nextPressed = false;
  bool _prevPressed = false;

  @override
  Widget build(BuildContext context) {
    final mins = (widget.totalDistance / 1.33 / 60).ceil();
    final prevEnabled = widget.onPrev != null;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primaryMaroon.withValues(alpha: 0.94),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 14, 16, MediaQuery.of(context).padding.bottom + 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, animation) => SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Column(
              key: ValueKey(widget.stepKey),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    widget.overrideCurrentText ??
                        'Current: ${widget.current.instructionText}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                if (widget.overrideCurrentText == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.next != null
                        ? 'Next: ${InstructionService.label(widget.next!.direction)}'
                        : 'Next: Arrive',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '${widget.totalDistance.toStringAsFixed(0)}m remaining'
                  '  ·  ~$mins min walk',
                  style: const TextStyle(
                      color: AppColors.accentGold,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 20),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTapDown: prevEnabled
                      ? (_) => setState(() => _prevPressed = true)
                      : null,
                  onTapCancel: prevEnabled
                      ? () => setState(() => _prevPressed = false)
                      : null,
                  onTapUp: prevEnabled
                      ? (_) {
                          setState(() => _prevPressed = false);
                          widget.onPrev?.call();
                        }
                      : null,
                  child: AnimatedScale(
                    scale: _prevPressed ? 0.95 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: prevEnabled
                              ? Colors.white54
                              : Colors.white24,
                        ),
                      ),
                      child: Center(
                        child: Text('Previous',
                            style: TextStyle(
                                color: prevEnabled
                                    ? Colors.white
                                    : Colors.white38,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _nextPressed = true),
                  onTapCancel: () => setState(() => _nextPressed = false),
                  onTapUp: (_) {
                    setState(() => _nextPressed = false);
                    widget.onNext();
                  },
                  child: AnimatedScale(
                    scale: _nextPressed ? 0.95 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.accentGold,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text('Next',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArrivalPanel extends StatelessWidget {
  final String name;
  final String? tripId;
  final Future<void> Function() onSurvey;
  final VoidCallback onDone;

  const _ArrivalPanel({
    required this.name,
    required this.tripId,
    required this.onSurvey,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle,
              color: AppColors.successGreen, size: 64),
          const SizedBox(height: 12),
          const Text('You have arrived!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          ArrivalFeedback(
            tripId: tripId,
            onRate: onSurvey,
            rateButton: (onPressed) => ElevatedButton(
                onPressed: onPressed,
                child: const Text('Rate your experience')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: onDone, child: const Text('Return to Map')),
        ],
      ),
    );
  }
}

/// Animated "marching ants" overlay for the active route segment. Projects
/// the segment's lat/lng points to screen space via [MapCamera] and draws
/// forward-crawling dashes over a translucent base line.
class _MarchingAnts extends StatelessWidget {
  final List<LatLng> points;

  /// 0 → 1, advanced each animation frame.
  final double phase;

  const _MarchingAnts({required this.points, required this.phase});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    final screen = points
        .map(camera.latLngToScreenOffset)
        .toList(growable: false);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _MarchingAntsPainter(screen, phase),
      ),
    );
  }
}

class _MarchingAntsPainter extends CustomPainter {
  final List<Offset> points;
  final double phase;

  _MarchingAntsPainter(this.points, this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = kRouteBlue.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final dashPaint = Paint()
      ..color = kRouteBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const dash = 16.0;
    const gap = 12.0;
    const period = dash + gap;

    for (final metric in path.computeMetrics()) {
      var start = (phase * period) - period;
      while (start < metric.length) {
        final a = math.max(0.0, start);
        final b = math.min(start + dash, metric.length);
        if (b > a) canvas.drawPath(metric.extractPath(a, b), dashPaint);
        start += period;
      }
    }
  }

  @override
  bool shouldRepaint(_MarchingAntsPainter old) =>
      old.phase != phase || old.points != points;
}
