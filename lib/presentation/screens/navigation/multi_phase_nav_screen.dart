import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_phase_manager.dart';
import '../../../data/models/floor_plan_model.dart';
import '../../../data/models/indoor_edge_model.dart';
import '../../../data/models/indoor_node_model.dart';
import '../../../data/repositories/floor_plan_repository.dart';
import '../../../data/repositories/indoor_navigation_repository.dart';
import '../../bloc/navigation/outdoor_nav_cubit.dart';
import '../../routes/app_router.dart';
import 'turn_by_turn_screen.dart';

class MultiPhaseNavScreen extends StatefulWidget {
  final NavigationRoute navigationRoute;
  const MultiPhaseNavScreen({super.key, required this.navigationRoute});

  @override
  State<MultiPhaseNavScreen> createState() => _MultiPhaseNavScreenState();
}

class _MultiPhaseNavScreenState extends State<MultiPhaseNavScreen> {
  late final NavigationRoute _route = widget.navigationRoute;

  // Indoor phase state.
  bool _indoorLoading = false;
  String? _indoorError;

  /// The floor the user starts on (origin room's floor, or the ground floor
  /// when coming in from outside) and the destination floor.
  FloorPlanModel? _startPlan;
  FloorPlanModel? _destPlan;

  /// 0 = start floor (walk to stairs/elevator), 1 = destination floor.
  int _indoorFloorStep = 0;

  /// Computed per step: pixel-space path + start/end for the current floor.
  List<Offset> _pathPixels = const [];
  Offset? _startPixel;
  Offset? _endPixel;

  /// Turn-by-turn instructions for the current indoor floor step.
  List<IndoorInstruction> _instructions = const [];
  int _currentStep = 0;
  bool _navNextPressed = false;
  bool _navPrevPressed = false;

  int get _originFloor => _route.originFloor ?? 1;
  int get _destFloorNo => _route.destFloor ?? 1;

  /// Start and destination are on the same floor — one floor plan, no
  /// stairs / elevator step.
  bool get _sameFloor => _originFloor == _destFloorNo;

  bool get _needsTwoFloors => !_sameFloor && _destPlan != null;

  @override
  void initState() {
    super.initState();
    if (_route.currentPhase == NavigationPhase.indoorNavigation) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadIndoor());
    }
  }

  void _advance() {
    setState(() {
      _route.advancePhase();
      // Same-floor trips don't need a stairs / elevator choice.
      if (_route.currentPhase == NavigationPhase.elevatorOrStairs &&
          _sameFloor) {
        _route.advancePhase();
      }
    });
    if (_route.currentPhase == NavigationPhase.indoorNavigation) {
      _loadIndoor();
    }
  }

  void _onArrived() {
    setState(() {
      _route.currentPhaseIndex = _route.phases.length - 1;
    });
  }

  // ─────────────────────── indoor loading ───────────────────────

  Future<void> _loadIndoor() async {
    final bId = int.tryParse(_route.destBuildingId ?? '');
    if (bId == null) {
      setState(() => _indoorError = 'Destination building is unknown.');
      return;
    }
    setState(() {
      _indoorLoading = true;
      _indoorError = null;
      _indoorFloorStep = 0;
    });
    try {
      final all =
          await context.read<FloorPlanRepository>().getFloorsForBuilding(bId);
      if (!mounted) return;
      all.sort((a, b) => a.floorNumber.compareTo(b.floorNumber));

      FloorPlanModel? planForFloor(int floor) {
        for (final f in all) {
          if (f.floorNumber == floor) return f;
        }
        return null;
      }

      final lowest = all.isEmpty
          ? null
          : all.reduce((a, b) => a.floorNumber <= b.floorNumber ? a : b);

      // Start on the origin room's floor (or the ground floor when the user
      // is coming in from outside); end on the destination floor.
      _startPlan = planForFloor(_originFloor) ?? lowest;
      _destPlan = planForFloor(_destFloorNo) ??
          (_sameFloor ? _startPlan : (all.isNotEmpty ? all.last : _startPlan));

      if (_startPlan == null) {
        setState(() {
          _indoorLoading = false;
          _indoorError = 'No floor plan is available for this building.';
        });
        return;
      }

      await _computeStepPath();
      if (mounted) setState(() => _indoorLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _indoorLoading = false;
          _indoorError = 'Could not load the floor plans.';
        });
      }
    }
  }

  Future<void> _computeStepPath() async {
    final repo = context.read<IndoorNavigationRepository>();
    final plan = (_indoorFloorStep == 0 || !_needsTwoFloors)
        ? _startPlan!
        : _destPlan!;

    // Reset step state for this floor step.
    _instructions = const [];
    _currentStep = 0;

    debugPrint('🗺 Calculating indoor path — floor plan ${plan.id} '
        '(floor ${plan.floorNumber}, step $_indoorFloorStep)');

    List<IndoorNodeModel> nodes;
    List<IndoorEdgeModel> edges;
    try {
      nodes = await repo.getNodesForFloor(plan.id.toString());
      edges = await repo.getEdgesForFloor(plan.id.toString());
    } catch (e) {
      debugPrint('❌ Failed to load indoor nodes/edges: $e');
      _pathPixels = const [];
      _startPixel = null;
      _endPixel = null;
      return;
    }

    final navigable = nodes.where((n) => n.isNavigable).toList();
    debugPrint('   Floor nodes: ${nodes.length}');
    debugPrint('   Floor edges: ${edges.length}');
    debugPrint('   Navigable nodes: ${navigable.length}');

    if (nodes.isEmpty || navigable.isEmpty) {
      debugPrint('❌ No navigable indoor nodes found for this floor');
      _pathPixels = const [];
      _startPixel = null;
      _endPixel = null;
      _indoorError = 'No indoor nodes found for this floor.';
      return;
    }

    final transportLabel =
        _route.selectedTransport == 'elevator' ? 'elevator' : 'stairs';

    final nodeById = {for (final n in nodes) n.id: n};

    // When the trip starts inside this building (room → room), begin at the
    // origin room's node; otherwise begin at a building entrance.
    IndoorNodeModel originStart() =>
        _srcRoomNode(nodes) ??
        _firstWhere(navigable, (n) => n.isEntrance) ??
        navigable.first;

    late IndoorNodeModel start;
    // true → pick whichever destination-room node is NEAREST by graph
    // distance; false → the end node is a fixed transport node.
    late bool targetIsRoom;
    IndoorNodeModel? fixedEnd;

    if (!_needsTwoFloors) {
      start = originStart();
      targetIsRoom = true;
      debugPrint('   Single floor: origin → destination room');
    } else if (_indoorFloorStep == 0) {
      start = originStart();
      fixedEnd = _nearestByLabel(nodes, transportLabel, start) ?? navigable.last;
      targetIsRoom = false;
      debugPrint('   Start floor: origin → nearest $transportLabel');
    } else {
      final approxRoom = _destRoomNode(nodes) ?? navigable.last;
      start =
          _nearestByLabel(nodes, transportLabel, approxRoom) ?? navigable.first;
      targetIsRoom = true;
      debugPrint('   Destination floor: $transportLabel → destination room');
    }

    debugPrint('   Start node: ${start.id} '
        '(${start.displayLabel}, entrance=${start.isEntrance})');

    _startPixel = Offset(start.x, start.y);

    // One Dijkstra sweep from the start; reused to score every candidate end.
    final dij = _indoorDijkstra(nodes: nodes, edges: edges, fromId: start.id);

    void unreachable() {
      debugPrint('❌ Indoor destination unreachable — check that the nodes '
          'are connected with edges in the admin app.');
      _pathPixels = const [];
      _endPixel = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not find an indoor path. Make sure the nodes are '
              'connected with edges in the admin app.',
            ),
            backgroundColor: AppColors.primaryMaroon,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }

    if (dij == null) {
      unreachable();
      return;
    }

    IndoorNodeModel? end;
    if (targetIsRoom) {
      // Pick the destination-room node with the SHORTEST path from the start.
      var bestDist = double.infinity;
      for (final c in _destRoomCandidates(nodes)) {
        final d = dij.dist[c.id] ?? double.infinity;
        debugPrint('   Dest candidate ${c.id} (${c.displayLabel}): '
            'dist=${d.isFinite ? d.toStringAsFixed(1) : "∞"}');
        if (d < bestDist) {
          bestDist = d;
          end = c;
        }
      }
      end ??= navigable.last;
      debugPrint('✅ Nearest destination node: ${end.id} '
          '(dist ${bestDist.isFinite ? bestDist.toStringAsFixed(1) : "∞"})');
    } else {
      end = fixedEnd!;
    }

    _endPixel = Offset(end.x, end.y);
    debugPrint('   End node:   ${end.id} (${end.displayLabel})');

    if (!(dij.dist[end.id] ?? double.infinity).isFinite) {
      unreachable();
      return;
    }

    final pathNodes = _reconstructIndoor(dij.prev, nodeById, end.id);
    if (pathNodes.length < 2 || pathNodes.first.id != start.id) {
      unreachable();
      return;
    }

    _pathPixels = pathNodes.map((n) => Offset(n.x, n.y)).toList();
    _instructions = _generateIndoorInstructions(_pathPixels);
    _currentStep = 0;
    debugPrint('✅ Indoor path: ${pathNodes.length} nodes → '
        '${pathNodes.map((n) => n.id).join(" → ")}');
    debugPrint('   Instructions: ${_instructions.length} steps');
  }

  void _onArrivedAtRoom() => _onArrived();

  // ─────────────────── indoor turn-by-turn instructions ───────────────────

  /// Metres per image pixel for the active floor plan. Falls back to a
  /// reasonable default when the plan carries no usable scale.
  double get _metersPerPixel {
    final plan = (_indoorFloorStep == 0 || !_needsTwoFloors)
        ? _startPlan
        : _destPlan;
    final s = plan?.scaleFactor ?? 0;
    return (s > 0 && s < 0.5) ? s : 0.05;
  }

  List<IndoorInstruction> _generateIndoorInstructions(
      List<Offset> pathPoints) {
    if (pathPoints.length < 2) return const [];

    final mpp = _metersPerPixel;
    final instructions = <IndoorInstruction>[];

    var segmentStart = 0;
    var segmentDist = 0.0;
    var currentDir = 'straight';

    for (var i = 1; i < pathPoints.length; i++) {
      final dx = pathPoints[i].dx - pathPoints[i - 1].dx;
      final dy = pathPoints[i].dy - pathPoints[i - 1].dy;
      segmentDist += math.sqrt(dx * dx + dy * dy);

      String newDir;
      if (i < pathPoints.length - 1) {
        final b1 = _pixelBearing(pathPoints[i - 1], pathPoints[i]);
        final b2 = _pixelBearing(pathPoints[i], pathPoints[i + 1]);
        newDir = _pixelDirection(b1, b2);
      } else {
        newDir = 'arrive';
      }

      final dirChanged = newDir != 'straight' && newDir != currentDir;
      final tooLong = segmentDist > 200;
      final isLast = i == pathPoints.length - 1;

      if (dirChanged || tooLong || isLast) {
        final segPts = pathPoints.sublist(segmentStart, i + 1);
        final distMeters = segmentDist * mpp;
        instructions.add(IndoorInstruction(
          instructionText:
              _buildIndoorText(currentDir, segmentDist, distMeters, isLast),
          directionIcon: _indoorIcon(isLast ? 'arrive' : currentDir),
          distancePixels: segmentDist,
          distanceMeters: distMeters,
          fromPoint: pathPoints[segmentStart],
          toPoint: pathPoints[i],
          segmentPoints: segPts,
        ));
        segmentStart = i;
        segmentDist = 0;
        currentDir = newDir;
      }
    }

    return instructions;
  }

  double _pixelBearing(Offset from, Offset to) =>
      math.atan2(to.dy - from.dy, to.dx - from.dx) * 180 / math.pi;

  String _pixelDirection(double b1, double b2) {
    var diff = b2 - b1;
    while (diff > 180) {
      diff -= 360;
    }
    while (diff < -180) {
      diff += 360;
    }
    if (diff.abs() < 20) return 'straight';
    if (diff.abs() > 150) return 'uturn';
    if (diff > 90) return 'sharp_right';
    if (diff > 30) return 'right';
    if (diff > 20) return 'slight_right';
    if (diff < -90) return 'sharp_left';
    if (diff < -30) return 'left';
    if (diff < -20) return 'slight_left';
    return 'straight';
  }

  String _buildIndoorText(
      String dir, double pixels, double meters, bool isLast) {
    if (isLast) return 'You have arrived!';
    final distStr = meters >= 1
        ? '${meters.toStringAsFixed(0)}m'
        : '${pixels.toStringAsFixed(0)} steps';
    switch (dir) {
      case 'straight':
        return 'Go straight for $distStr';
      case 'left':
        return 'Turn left, continue $distStr';
      case 'right':
        return 'Turn right, continue $distStr';
      case 'slight_left':
        return 'Bear left, continue $distStr';
      case 'slight_right':
        return 'Bear right, continue $distStr';
      case 'sharp_left':
        return 'Sharp left, go $distStr';
      case 'sharp_right':
        return 'Sharp right, go $distStr';
      case 'uturn':
        return 'Turn around';
      default:
        return 'Continue $distStr';
    }
  }

  IconData _indoorIcon(String dir) {
    switch (dir) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight_left':
        return Icons.turn_slight_left;
      case 'slight_right':
        return Icons.turn_slight_right;
      case 'sharp_left':
        return Icons.turn_sharp_left;
      case 'sharp_right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      case 'arrive':
        return Icons.location_on;
      default:
        return Icons.arrow_upward;
    }
  }

  /// Dijkstra over the indoor edge graph. Returns the ordered nodes from
  /// [fromId] to [toId], following `indoor_edges`; null if unreachable.
  /// Full Dijkstra over the indoor edge graph from [fromId] — returns the
  /// shortest distance and predecessor for EVERY node (so the caller can pick
  /// the nearest of several destination candidates). null = graph unusable.
  ({Map<String, double> dist, Map<String, String?> prev})? _indoorDijkstra({
    required List<IndoorNodeModel> nodes,
    required List<IndoorEdgeModel> edges,
    required String fromId,
  }) {
    final nodeById = {for (final n in nodes) n.id: n};
    if (!nodeById.containsKey(fromId)) {
      debugPrint('❌ Start node id is not in the node list');
      return null;
    }

    // adjacency: nodeId → [(neighbourId, weight), …]
    final adjacency = <String, List<MapEntry<String, double>>>{
      for (final n in nodes) n.id: <MapEntry<String, double>>[],
    };

    var edgesAdded = 0;
    for (final e in edges) {
      if (!e.isActive) continue;
      final a = nodeById[e.fromNode];
      final b = nodeById[e.toNode];
      if (a == null || b == null) continue;
      if (!a.isNavigable || !b.isNavigable) continue;
      final w = e.weight > 0 ? e.weight : (a.position - b.position).distance;
      adjacency[e.fromNode]!.add(MapEntry(e.toNode, w));
      if (e.isTwoWay) {
        adjacency[e.toNode]!.add(MapEntry(e.fromNode, w));
      }
      edgesAdded++;
    }

    debugPrint('🧭 Indoor Dijkstra from $fromId');
    debugPrint('   Edges wired into graph: $edgesAdded / ${edges.length}');
    debugPrint('   Start neighbours: ${adjacency[fromId]!.length}');

    if (edgesAdded == 0) {
      debugPrint('❌ No usable edges — every node is isolated.');
      return null;
    }

    final dist = <String, double>{
      for (final id in adjacency.keys) id: double.infinity,
    };
    final prev = <String, String?>{};
    dist[fromId] = 0;
    final unvisited = Set<String>.from(adjacency.keys);

    while (unvisited.isNotEmpty) {
      String? current;
      var minDist = double.infinity;
      for (final id in unvisited) {
        final d = dist[id]!;
        if (d < minDist) {
          minDist = d;
          current = id;
        }
      }
      if (current == null || minDist == double.infinity) break;

      unvisited.remove(current);
      for (final edge in adjacency[current]!) {
        if (!unvisited.contains(edge.key)) continue;
        final nd = minDist + edge.value;
        if (nd < dist[edge.key]!) {
          dist[edge.key] = nd;
          prev[edge.key] = current;
        }
      }
    }

    return (dist: dist, prev: prev);
  }

  List<IndoorNodeModel> _reconstructIndoor(
    Map<String, String?> prev,
    Map<String, IndoorNodeModel> nodeById,
    String toId,
  ) {
    final path = <IndoorNodeModel>[];
    String? cur = toId;
    var safety = 0;
    while (cur != null && safety < 1000) {
      final n = nodeById[cur];
      if (n != null) path.insert(0, n);
      cur = prev[cur];
      safety++;
    }
    return path;
  }

  /// Every navigable node that could be the destination room's entrance —
  /// linked by `linked_room_id` first, else by room number / label / name.
  List<IndoorNodeModel> _destRoomCandidates(List<IndoorNodeModel> nodes) {
    final targetId = _route.to['id']?.toString();
    final targetName = (_route.destRoomName ?? '').toLowerCase().trim();

    if (targetId != null) {
      final linked = nodes
          .where((n) =>
              n.isNavigable && n.linkedRoomId?.toString() == targetId)
          .toList();
      if (linked.isNotEmpty) return linked;
    }
    if (targetName.isNotEmpty) {
      final byName = nodes.where((n) {
        if (!n.isNavigable) return false;
        final rno = (n.roomNumber ?? '').toLowerCase();
        final el = (n.entranceLabel ?? '').toLowerCase();
        final rn = (n.roomName ?? '').toLowerCase();
        return rno.contains(targetName) ||
            el.contains(targetName) ||
            rn.contains(targetName);
      }).toList();
      if (byName.isNotEmpty) return byName;
    }
    return const [];
  }

  IndoorNodeModel? _firstWhere(
      List<IndoorNodeModel> nodes, bool Function(IndoorNodeModel) test) {
    for (final n in nodes) {
      if (test(n)) return n;
    }
    return null;
  }

  /// The origin room's navigable node — only when the trip starts inside a
  /// room / facility (room → room). Returns null for a building origin so the
  /// caller falls back to a building entrance.
  IndoorNodeModel? _srcRoomNode(List<IndoorNodeModel> nodes) {
    final fromType = (_route.from['type'] ?? 'building').toString();
    if (fromType != 'room' && fromType != 'facility') return null;
    return _matchRoomNode(
      nodes,
      _route.from['id']?.toString(),
      (_route.originRoomName ?? _route.fromName ?? '').toLowerCase().trim(),
      label: 'Start',
    );
  }

  /// The destination should be the ROOM ENTRANCE node (a navigable node
  /// linked to the room), NOT the informational label node.
  IndoorNodeModel? _destRoomNode(List<IndoorNodeModel> nodes) {
    return _matchRoomNode(
      nodes,
      _route.to['id']?.toString(),
      (_route.destRoomName ?? '').toLowerCase().trim(),
      label: 'End',
    );
  }

  IndoorNodeModel? _matchRoomNode(
    List<IndoorNodeModel> nodes,
    String? targetId,
    String targetName, {
    required String label,
  }) {
    debugPrint('   Looking for $label room node — id: $targetId');

    if (targetId != null) {
      // Priority 1: navigable ENTRANCE node linked to the room.
      for (final n in nodes) {
        if (n.isNavigable &&
            n.isEntrance &&
            n.linkedRoomId?.toString() == targetId) {
          debugPrint('✅ $label: room entrance node ${n.id} '
              '(${n.entranceLabel ?? n.displayLabel})');
          return n;
        }
      }
      // Priority 2: any navigable node linked to the room.
      for (final n in nodes) {
        if (n.isNavigable && n.linkedRoomId?.toString() == targetId) {
          debugPrint('✅ $label: linked navigable node ${n.id}');
          return n;
        }
      }
    }

    // Priority 3: navigable node whose room number / entrance label / name
    // matches the room name.
    if (targetName.isNotEmpty) {
      for (final n in nodes) {
        if (!n.isNavigable) continue;
        final rno = (n.roomNumber ?? '').toLowerCase();
        final elabel = (n.entranceLabel ?? '').toLowerCase();
        final rname = (n.roomName ?? '').toLowerCase().trim();
        if (rno.contains(targetName) ||
            elabel.contains(targetName) ||
            rname == targetName ||
            rname.contains(targetName)) {
          debugPrint('✅ $label: matched by room number / label — ${n.id}');
          return n;
        }
      }
    }

    debugPrint('⚠️ $label: no linked room node found');
    return null;
  }

  IndoorNodeModel? _nearestByLabel(List<IndoorNodeModel> nodes, String label,
      IndoorNodeModel to) {
    IndoorNodeModel? best;
    double bestD = double.infinity;
    for (final n in nodes) {
      if (!(n.label ?? '').toLowerCase().contains(label)) continue;
      final dx = n.x - to.x;
      final dy = n.y - to.y;
      final d = dx * dx + dy * dy;
      if (d < bestD) {
        bestD = d;
        best = n;
      }
    }
    return best;
  }

  Future<void> _goToDestinationFloor() async {
    setState(() {
      _indoorFloorStep = 1;
      _indoorLoading = true;
    });
    await _computeStepPath();
    if (mounted) setState(() => _indoorLoading = false);
  }

  // ─────────────────────────── build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    // Always wrap in a full-screen guard so the phase widget below is the
    // only thing that fills the route.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Exit Navigation?'),
            content: const Text(
                'Are you sure you want to exit navigation?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Continue',
                    style: TextStyle(color: AppColors.primaryMaroon)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Exit',
                    style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        );
        if (shouldLeave ?? false) navigator.pop();
      },
      child: _buildCurrentPhaseScreen(),
    );
  }

  /// Returns a complete Scaffold (or the full-screen [TurnByTurnScreen]) for
  /// the active phase.
  Widget _buildCurrentPhaseScreen() {
    switch (_route.currentPhase) {
      case NavigationPhase.exitOriginBuilding:
        return _exitScreen();
      case NavigationPhase.outdoorNavigation:
        return _outdoorScreen();
      case NavigationPhase.elevatorOrStairs:
        return _transportChoiceScreen();
      case NavigationPhase.indoorNavigation:
        return _indoorScreen();
      case NavigationPhase.arrived:
        return _arrivedScreen();
    }
  }

  // ─────────────────────── phase indicator ───────────────────────

  static const _phaseMeta = {
    NavigationPhase.exitOriginBuilding: (Icons.exit_to_app, 'Exit'),
    NavigationPhase.outdoorNavigation: (Icons.map_outlined, 'Walk'),
    NavigationPhase.elevatorOrStairs: (Icons.login, 'Enter'),
    NavigationPhase.indoorNavigation: (Icons.business, 'Navigate'),
  };

  Widget _phaseIndicator() {
    final visible =
        _route.phases.where((p) => p != NavigationPhase.arrived).toList();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(visible.length, (index) {
        final phase = visible[index];
        final isCurrent = index == _route.currentPhaseIndex;
        final isCompleted = index < _route.currentPhaseIndex;
        final meta = _phaseMeta[phase] ?? (Icons.circle, '');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index > 0)
              Container(
                width: 24,
                height: 2,
                margin: const EdgeInsets.only(bottom: 14),
                color: isCompleted
                    ? AppColors.successGreen
                    : Colors.grey[300],
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.successGreen
                        : isCurrent
                            ? AppColors.primaryMaroon
                            : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 14)
                        : Icon(meta.$1,
                            color: isCurrent
                                ? Colors.white
                                : Colors.grey[500],
                            size: 14),
                  ),
                ),
                const SizedBox(height: 2),
                Text(meta.$2,
                    style: TextStyle(
                      fontSize: 9,
                      color: isCurrent
                          ? AppColors.primaryMaroon
                          : Colors.grey[500],
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                    )),
              ],
            ),
          ],
        );
      }),
    );
  }

  PreferredSizeWidget _appBar({bool showClose = true}) {
    return AppBar(
      title: const Text('Navigation'),
      leading: showClose
          ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
    );
  }

  // ─────────────────── Phase 1 — Exit building ───────────────────

  Widget _exitScreen() {
    final buildingName = _route.originBuildingName ?? 'the building';
    return Scaffold(
      backgroundColor: AppColors.backgroundGray,
      appBar: _appBar(),
      body: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _phaseIndicator(),
            const SizedBox(height: 32),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.exit_to_app,
                  size: 40, color: AppColors.primaryMaroon),
            ),
            const SizedBox(height: 24),
            const Text('Exit the Building',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.location_on,
                          color: AppColors.primaryMaroon, size: 18),
                      SizedBox(width: 8),
                      Text('You are at:',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(_route.originRoomName ?? 'Origin Location',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                  Text(_route.originBuildingName ?? '',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.door_front_door_outlined,
                          color: AppColors.accentGold, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Head to the nearest exit of $buildingName to '
                          'continue navigation.',
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _advance,
                icon: const Icon(Icons.check_circle_outline,
                    color: AppColors.accentGold),
                label: const Text("I'm Outside Now",
                    style: TextStyle(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryMaroon,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
        ),
      ),
    );
  }

  // ─────────────────── Phase 2 — Outdoor ───────────────────

  Widget _outdoorScreen() {
    if (_route.outdoorPath.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.backgroundGray,
        appBar: _appBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text('No outdoor route found',
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryMaroon,
                  side: const BorderSide(color: AppColors.primaryMaroon),
                ),
                child: const Text('Return to Map'),
              ),
            ],
          ),
        ),
      );
    }

    final nextPhase = _route.phases[(_route.currentPhaseIndex + 1)
        .clamp(0, _route.phases.length - 1)];
    final continuesIndoors = nextPhase != NavigationPhase.arrived;

    return TurnByTurnScreen(
      args: TurnByTurnArgs(
        path: _route.outdoorPath,
        nodes: const [],
        destinationName:
            _route.toName ?? _route.destBuildingName ?? 'your destination',
      ),
      hasMorePhases: continuesIndoors,
      destBuildingName: _route.destBuildingName,
      onArrivedAtBuilding: _advance,
    );
  }

  // ─────────────────── Phase 3A — Transport ───────────────────

  Widget _transportChoiceScreen() {
    return Scaffold(
      backgroundColor: AppColors.backgroundGray,
      appBar: _appBar(showClose: false),
      body: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _phaseIndicator(),
            const SizedBox(height: 32),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.business,
                  size: 40, color: AppColors.primaryMaroon),
            ),
            const SizedBox(height: 24),
            Text('You are at ${_route.destBuildingName ?? 'the building'}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Destination: ${_route.destRoomName ?? '—'}'
              '\nFloor ${_route.destFloor}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            Text(
              'How would you like to go to Floor ${_route.destFloor}?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 24),
            _transportCard(
              icon: Icons.stairs,
              title: 'Take Stairs',
              subtitle: 'Navigate to the stairs, then to your floor',
              color: AppColors.primaryMaroon,
              onTap: () {
                _route.selectedTransport = 'stairs';
                _advance();
              },
            ),
            const SizedBox(height: 12),
            if (_route.hasElevator)
              _transportCard(
                icon: Icons.elevator,
                title: 'Take Elevator',
                subtitle: 'Navigate to the elevator, then to your floor',
                color: AppColors.infoBlue,
                onTap: () {
                  _route.selectedTransport = 'elevator';
                  _advance();
                },
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.accentGold),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline,
                        color: AppColors.accentGold, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No elevator available in this building. '
                        'Please use the stairs.',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF633806)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _transportCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }

  // ─────────────────── Phase 3B — Indoor ───────────────────

  bool get _isFinalIndoorStep =>
      _instructions.isNotEmpty &&
      _currentStep >= _instructions.length - 1;

  Widget _indoorScreen() {
    final transport =
        _route.selectedTransport == 'elevator' ? 'elevator' : 'stairs';
    final onGround = _needsTwoFloors && _indoorFloorStep == 0;
    final showTurnByTurn = !_indoorLoading &&
        _indoorError == null &&
        _instructions.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_route.destBuildingName ?? 'Building',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            Text(
              onGround
                  ? 'Floor $_originFloor — find the $transport'
                  : 'Navigate to ${_route.destRoomName ?? 'your room'}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Direction card sits directly below the AppBar — no phase
          // indicator, no gap.
          if (showTurnByTurn) _indoorDirectionCard(),
          Expanded(child: _indoorBody()),
          _indoorBottomPanel(onGround, transport),
        ],
      ),
    );
  }

  Widget _indoorDirectionCard() {
    final step = _instructions[_currentStep.clamp(0, _instructions.length - 1)];
    final isLastStep = _isFinalIndoorStep;
    final next = !isLastStep && _currentStep < _instructions.length - 1
        ? _instructions[_currentStep + 1]
        : null;
    final shown = _instructions.length > 8 ? 8 : _instructions.length;
    final activeDot = _currentStep > 7 ? 7 : _currentStep;

    return ClipRRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Column(
              key: ValueKey(_currentStep),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(step.directionIcon,
                    size: 48,
                    color: isLastStep
                        ? AppColors.successGreen
                        : AppColors.primaryMaroon),
                const SizedBox(height: 8),
                Text(step.instructionText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                if (isLastStep && _route.destRoomName != null) ...[
                  const SizedBox(height: 4),
                  Text(_route.destRoomName!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.successGreen,
                          fontWeight: FontWeight.w600)),
                ],
                if (!isLastStep && next != null) ...[
                  const SizedBox(height: 4),
                  Text('Then: ${next.instructionText}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(shown, (i) {
                    final isActive = i == activeDot;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: isActive ? 18 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.primaryMaroon
                            : const Color(0xFFD9C9B0),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Text('Step ${_currentStep + 1} of ${_instructions.length}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _indoorBottomPanel(bool onGround, String transport) {
    // No instructions (path unreachable / still loading) — offer a single
    // action so the user is never stuck.
    if (_instructions.isEmpty) {
      return Container(
        color: AppColors.primaryMaroon,
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: onGround ? _goToDestinationFloor : _onArrivedAtRoom,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentGold,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              onGround
                  ? 'Go to Floor ${_route.destFloor} ►'
                  : 'Arrived! 🎉',
              style: const TextStyle(
                  color: AppColors.primaryMaroon,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
          ),
        ),
      );
    }

    var remainingDist = 0.0;
    for (var i = _currentStep; i < _instructions.length; i++) {
      remainingDist += _instructions[i].distanceMeters;
    }
    final remainingSeconds = (remainingDist / 0.8).ceil();
    final remainingMin = remainingSeconds ~/ 60;
    final remainingSec = remainingSeconds % 60;

    final isLastStep = _currentStep >= _instructions.length - 1;
    // On the ground-floor step of a two-floor trip the final action is to
    // change floors, not to finish.
    final finishIsFloorChange = isLastStep && onGround;

    return Container(
      color: AppColors.primaryMaroon,
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Column(
              key: ValueKey(_currentStep),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _instructions[_currentStep.clamp(0, _instructions.length - 1)]
                      .instructionText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.straighten,
                        color: AppColors.accentGold, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      remainingDist >= 1
                          ? '${remainingDist.toStringAsFixed(0)}m remaining'
                          : 'Almost there',
                      style: const TextStyle(
                          color: AppColors.accentGold, fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.access_time,
                        color: Colors.white60, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      remainingMin > 0
                          ? '~${remainingMin}m ${remainingSec}s'
                          : '~${remainingSec}s',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _navPrevPressed = true),
                  onTapCancel: () =>
                      setState(() => _navPrevPressed = false),
                  onTapUp: (_) {
                    setState(() {
                      _navPrevPressed = false;
                      if (_currentStep > 0) {
                        _currentStep--;
                      }
                    });
                    // At the first step of the destination floor, "Previous"
                    // returns to the ground-floor view.
                    if (_currentStep == 0 &&
                        _needsTwoFloors &&
                        !onGround) {
                      _returnToGroundFloor();
                    }
                  },
                  child: AnimatedScale(
                    scale: _navPrevPressed ? 0.95 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _currentStep > 0 ||
                                    (_needsTwoFloors && !onGround)
                                ? Colors.white54
                                : Colors.white24),
                      ),
                      child: Center(
                        child: Text('Previous',
                            style: TextStyle(
                                color: _currentStep > 0 ||
                                        (_needsTwoFloors && !onGround)
                                    ? Colors.white
                                    : Colors.white38,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _navNextPressed = true),
                  onTapCancel: () =>
                      setState(() => _navNextPressed = false),
                  onTapUp: (_) {
                    setState(() => _navNextPressed = false);
                    if (finishIsFloorChange) {
                      _goToDestinationFloor();
                    } else if (isLastStep) {
                      _onArrivedAtRoom();
                    } else {
                      setState(() => _currentStep++);
                    }
                  },
                  child: AnimatedScale(
                    scale: _navNextPressed ? 0.95 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: (isLastStep && !finishIsFloorChange)
                            ? AppColors.successGreen
                            : AppColors.accentGold,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          finishIsFloorChange
                              ? 'Go to Floor ${_route.destFloor} ►'
                              : isLastStep
                                  ? 'Arrived! 🎉'
                                  : 'Next ►',
                          style: TextStyle(
                            color: (isLastStep && !finishIsFloorChange)
                                ? Colors.white
                                : AppColors.primaryMaroon,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
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

  Future<void> _returnToGroundFloor() async {
    setState(() {
      _indoorFloorStep = 0;
      _indoorLoading = true;
    });
    await _computeStepPath();
    if (mounted) setState(() => _indoorLoading = false);
  }

  Widget _indoorBody() {
    if (_indoorLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryMaroon),
      );
    }
    if (_indoorError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off,
                size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 8),
            Text(_indoorError!,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _loadIndoor, child: const Text('Retry')),
          ],
        ),
      );
    }

    final plan = (_indoorFloorStep == 0 || !_needsTwoFloors)
        ? _startPlan
        : _destPlan;
    if (plan == null) {
      return const Center(
        child: Text('No floor plan available.',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return _RouteFloorView(
      key: ValueKey('${plan.id}-$_indoorFloorStep'),
      imageUrl: plan.imageUrl,
      pathPixels: _pathPixels,
      startPixel: _startPixel,
      endPixel: _endPixel,
      isFinalStep: _isFinalIndoorStep,
      // Room → room on the same floor: open in top view so the whole route
      // is previewed before the user steps through it.
      startTopView: _route.startInTopView &&
          _indoorFloorStep == 0 &&
          _currentStep == 0,
      focusSegment: _instructions.isEmpty
          ? const []
          : _instructions[_currentStep.clamp(0, _instructions.length - 1)]
              .segmentPoints,
      completedSegment: _completedIndoorPoints(),
    );
  }

  /// Route points from the start up to the beginning of the current step —
  /// drawn as the solid grey "already walked" trail.
  List<Offset> _completedIndoorPoints() {
    if (_currentStep <= 0 ||
        _instructions.isEmpty ||
        _pathPixels.length < 2) {
      return const [];
    }
    var idx = 0;
    for (var i = 0; i < _currentStep && i < _instructions.length; i++) {
      idx += _instructions[i].segmentPoints.length - 1;
    }
    idx = idx.clamp(0, _pathPixels.length - 1);
    return _pathPixels.sublist(0, idx + 1);
  }

  // ─────────────────── Arrived ───────────────────

  Widget _arrivedScreen() {
    return Scaffold(
      backgroundColor: AppColors.primaryMaroon,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle,
                  color: AppColors.accentGold, size: 100),
              const SizedBox(height: 24),
              const Text('You Have Arrived!',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text(_route.destRoomName ?? _route.toName ?? 'Destination',
                  style: const TextStyle(
                      fontSize: 16, color: Colors.white70)),
              if (_route.destBuildingName != null) ...[
                const SizedBox(height: 4),
                Text(_route.destBuildingName!,
                    style: const TextStyle(
                        fontSize: 14, color: Colors.white54)),
              ],
              const SizedBox(height: 48),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.push('/survey');
                    },
                    icon: const Icon(Icons.star_outline,
                        color: AppColors.primaryMaroon),
                    label: const Text('Rate Your Experience',
                        style: TextStyle(
                            color: AppColors.primaryMaroon,
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentGold,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  try {
                    context.read<OutdoorNavCubit>().clearRoute();
                  } catch (e) {
                    debugPrint('Clear route: $e');
                  }
                  final router = GoRouter.of(context);
                  final nav = Navigator.of(context, rootNavigator: true);
                  if (nav.canPop()) nav.pop();
                  router.go('/map');
                },
                child: const Text('Return to Map',
                    style: TextStyle(color: Colors.white70, fontSize: 15)),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// One merged turn-by-turn step across the indoor floor plan.
class IndoorInstruction {
  final String instructionText;
  final IconData directionIcon;
  final double distancePixels;
  final double distanceMeters;
  final Offset fromPoint;
  final Offset toPoint;
  final List<Offset> segmentPoints;

  const IndoorInstruction({
    required this.instructionText,
    required this.directionIcon,
    required this.distancePixels,
    required this.distanceMeters,
    required this.fromPoint,
    required this.toPoint,
    required this.segmentPoints,
  });
}

/// Floor-plan image + route overlay. No node dots — only the path line, a
/// green start dot, and a Google-Maps-style pin at the destination.
class _RouteFloorView extends StatefulWidget {
  final String? imageUrl;
  final List<Offset> pathPixels;
  final Offset? startPixel;
  final Offset? endPixel;

  /// Image-pixel points of the current turn-by-turn step; the camera pans /
  /// rotates / zooms to frame these and they draw as animated marching ants.
  /// Empty = show the whole plan.
  final List<Offset> focusSegment;

  /// Image-pixel points already walked (drawn solid grey).
  final List<Offset> completedSegment;

  /// Last step of the trip — camera zooms straight in on the destination
  /// with no rotation.
  final bool isFinalStep;

  /// Open in whole-plan top view (route preview) rather than the
  /// follow-the-step camera.
  final bool startTopView;

  const _RouteFloorView({
    super.key,
    required this.imageUrl,
    required this.pathPixels,
    required this.startPixel,
    required this.endPixel,
    this.focusSegment = const [],
    this.completedSegment = const [],
    this.isFinalStep = false,
    this.startTopView = false,
  });

  @override
  State<_RouteFloorView> createState() => _RouteFloorViewState();
}

class _RouteFloorViewState extends State<_RouteFloorView>
    with TickerProviderStateMixin {
  final _controller = TransformationController();
  Size? _imageSize;

  // Viewport (InteractiveViewer) + contained-image size, cached from the last
  // layout pass so the camera animation can do its maths.
  Size _viewportSize = Size.zero;
  Size _contentSize = Size.zero;

  late final AnimationController _cameraCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  Animation<Matrix4>? _cameraAnim;

  // Marching-ants dash phase, like the outdoor turn-by-turn overlay.
  late final AnimationController _dashCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  /// Whole-floor "top view" vs. the follow-the-step navigation camera.
  late bool _isTopView = widget.startTopView;

  @override
  void initState() {
    super.initState();
    _cameraCtrl.addListener(() {
      final anim = _cameraAnim;
      if (anim != null) _controller.value = anim.value;
    });
    _resolveImage();
  }

  @override
  void didUpdateWidget(_RouteFloorView old) {
    super.didUpdateWidget(old);
    // Each turn-by-turn step hands a different segmentPoints list instance.
    if (!identical(old.focusSegment, widget.focusSegment) ||
        old.isFinalStep != widget.isFinalStep) {
      // Stepping Next / Previous drops out of top view back to navigation.
      _isTopView = false;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _animateCameraToSegment(widget.focusSegment));
    }
  }

  void _toggleTopView() {
    setState(() => _isTopView = !_isTopView);
    if (_isTopView) {
      _animateToTopView();
    } else {
      _animateCameraToSegment(widget.focusSegment);
    }
  }

  /// Whole floor plan, straight (identity transform = the fit-to-viewport
  /// view since the content box is already letterboxed).
  void _animateToTopView() {
    if (!mounted) return;
    _cameraAnim = Matrix4Tween(
      begin: _controller.value.clone(),
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(
      parent: _cameraCtrl,
      curve: Curves.easeInOutCubic,
    ));
    _cameraCtrl.forward(from: 0);
  }

  void _resolveImage() {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) return;
    final provider = CachedNetworkImageProvider(url);
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _imageSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            ));
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _animateCameraToSegment(widget.focusSegment));
      }
      stream.removeListener(listener);
    }, onError: (_, _) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  /// Pans / rotates / zooms the [InteractiveViewer] so the current step
  /// fills the viewport. On the final step it zooms straight in on the
  /// destination with NO rotation so the label reads right-side up.
  void _animateCameraToSegment(List<Offset> segment) {
    if (!mounted || _isTopView) return;
    final imgSize = _imageSize;
    if (imgSize == null ||
        imgSize.width == 0 ||
        _viewportSize == Size.zero ||
        _contentSize == Size.zero) {
      return;
    }

    double avgX, avgY, rotation, scale;

    if (widget.isFinalStep && widget.endPixel != null) {
      avgX = widget.endPixel!.dx;
      avgY = widget.endPixel!.dy;
      rotation = 0;
      scale = 3.0;
    } else {
      if (segment.isEmpty) return;

      // Segment centre + length in image pixels.
      avgX = 0;
      avgY = 0;
      for (final p in segment) {
        avgX += p.dx;
        avgY += p.dy;
      }
      avgX /= segment.length;
      avgY /= segment.length;

      var segLen = 0.0;
      for (var i = 1; i < segment.length; i++) {
        segLen += (segment[i] - segment[i - 1]).distance;
      }

      // Rotate the plan so the direction of travel points UP on screen,
      // like the outdoor turn-by-turn map.
      rotation = 0;
      if (segment.length >= 2) {
        final dx = segment.last.dx - segment.first.dx;
        final dy = segment.last.dy - segment.first.dy;
        rotation = -math.atan2(dx, -dy);
      }

      // Tighter zoom for shorter segments.
      scale = 3.0;
      if (segLen > 400) {
        scale = 1.8;
      } else if (segLen > 200) {
        scale = 2.4;
      }
    }
    scale = scale.clamp(0.3, 5.0);

    // image px → position inside the (centred) content box → viewport px.
    final k = _contentSize.width / imgSize.width;
    final originX = (_viewportSize.width - _contentSize.width) / 2;
    final originY = (_viewportSize.height - _contentSize.height) / 2;
    final childX = originX + avgX * k;
    final childY = originY + avgY * k;

    // target = T(viewportCentre) · R(rotation) · S(scale) · T(-focusPoint)
    final target = Matrix4.identity()
      ..translateByDouble(
          _viewportSize.width / 2, _viewportSize.height / 2, 0, 1)
      ..multiply(Matrix4.rotationZ(rotation))
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-childX, -childY, 0, 1);

    _cameraAnim = Matrix4Tween(
      begin: _controller.value.clone(),
      end: target,
    ).animate(CurvedAnimation(
      parent: _cameraCtrl,
      curve: Curves.easeInOutCubic,
    ));
    _cameraCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _cameraCtrl.dispose();
    _dashCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      return const ColoredBox(
        color: AppColors.backgroundGray,
        child: Center(
          child: Text('Floor plan image not available',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    final imgSize = _imageSize;

    return LayoutBuilder(
      builder: (context, constraints) {
        Size render = Size(constraints.maxWidth, constraints.maxHeight);
        if (imgSize != null) {
          final ar = imgSize.width / imgSize.height;
          final boxAr = constraints.maxWidth / constraints.maxHeight;
          render = ar > boxAr
              ? Size(constraints.maxWidth, constraints.maxWidth / ar)
              : Size(constraints.maxHeight * ar, constraints.maxHeight);
        }
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _contentSize = render;

        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
          transformationController: _controller,
          minScale: 0.3,
          maxScale: 5.0,
          boundaryMargin: const EdgeInsets.all(200),
          child: Center(
            child: SizedBox(
              width: render.width,
              height: render.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: widget.imageUrl!,
                    fit: BoxFit.fill,
                    placeholder: (_, _) => const ColoredBox(
                      color: AppColors.backgroundGray,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, _, _) => const ColoredBox(
                      color: AppColors.backgroundGray,
                      child: Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                  if (imgSize != null)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _dashCtrl,
                        builder: (context, _) => CustomPaint(
                          painter: _RoutePainter(
                            pathPoints: widget.pathPixels,
                            completedPoints: widget.completedSegment,
                            activePoints: widget.focusSegment,
                            startPoint: widget.startPixel,
                            endPoint: widget.endPixel,
                            imageSize: imgSize,
                            dashOffset: _dashCtrl.value,
                            showEndDot: widget.isFinalStep,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
              ),
            ),
            if (imgSize != null)
              Positioned(
                top: 8,
                right: 8,
                child: Tooltip(
                  message: _isTopView ? 'Navigation View' : 'Top View',
                  child: GestureDetector(
                    onTap: _toggleTopView,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isTopView
                            ? AppColors.primaryMaroon
                            : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Icon(
                        _isTopView ? Icons.navigation : Icons.crop_free,
                        color: _isTopView
                            ? Colors.white
                            : AppColors.primaryMaroon,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Interpolates two 2‑D affine transforms (translate + rotate‑Z + uniform
/// scale) by decomposing each and lerping scale, angle (shortest way) and
/// translation separately — so the view rotates smoothly instead of
/// shearing.
class Matrix4Tween extends Tween<Matrix4> {
  Matrix4Tween({required Matrix4 super.begin, required Matrix4 super.end});

  @override
  Matrix4 lerp(double t) {
    final a = begin!.storage;
    final b = end!.storage;

    final aScale = math.sqrt(a[0] * a[0] + a[1] * a[1]);
    final bScale = math.sqrt(b[0] * b[0] + b[1] * b[1]);
    final aRot = math.atan2(a[1], a[0]);
    final bRot = math.atan2(b[1], b[0]);
    var dRot = bRot - aRot;
    while (dRot > math.pi) {
      dRot -= 2 * math.pi;
    }
    while (dRot < -math.pi) {
      dRot += 2 * math.pi;
    }

    final s = aScale + (bScale - aScale) * t;
    final r = aRot + dRot * t;
    final tx = a[12] + (b[12] - a[12]) * t;
    final ty = a[13] + (b[13] - a[13]) * t;
    final c = math.cos(r), sn = math.sin(r);

    final out = Matrix4.identity();
    final o = out.storage;
    o[0] = c * s;
    o[1] = sn * s;
    o[4] = -sn * s;
    o[5] = c * s;
    o[12] = tx;
    o[13] = ty;
    return out;
  }
}

class _RoutePainter extends CustomPainter {
  final List<Offset> pathPoints; // full route, image pixel space
  final List<Offset> completedPoints; // already walked (grey solid)
  final List<Offset> activePoints; // current step (marching ants)
  final Offset? startPoint;
  final Offset? endPoint;
  final Size imageSize;
  final double dashOffset; // 0 → 1, drives the ants
  final bool showEndDot; // gold end dot only on the final step

  _RoutePainter({
    required this.pathPoints,
    required this.completedPoints,
    required this.activePoints,
    required this.startPoint,
    required this.endPoint,
    required this.imageSize,
    required this.dashOffset,
    required this.showEndDot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;
    final sx = size.width / imageSize.width;
    final sy = size.height / imageSize.height;
    Offset scale(Offset p) => Offset(p.dx * sx, p.dy * sy);

    Path polyline(List<Offset> pts) {
      final path = Path()..moveTo(scale(pts.first).dx, scale(pts.first).dy);
      for (final p in pts.skip(1)) {
        final s = scale(p);
        path.lineTo(s.dx, s.dy);
      }
      return path;
    }

    // 1. Upcoming — faded blue (whole route, under everything else).
    if (pathPoints.length >= 2) {
      canvas.drawPath(
        polyline(pathPoints),
        Paint()
          ..color = const Color(0xFF1A73E8).withValues(alpha: 0.3)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    // 2. Completed — solid grey.
    if (completedPoints.length >= 2) {
      canvas.drawPath(
        polyline(completedPoints),
        Paint()
          ..color = Colors.grey.withValues(alpha: 0.5)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
    }

    // 3. Active step — white casing + animated blue marching ants.
    if (activePoints.length >= 2) {
      final activePath = polyline(activePoints);
      canvas.drawPath(
        activePath,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );

      final dashPaint = Paint()
        ..color = const Color(0xFF1A73E8)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      const dashLength = 20.0;
      const gapLength = 10.0;
      const total = dashLength + gapLength;
      final animOffset = dashOffset * total;

      for (final metric in activePath.computeMetrics()) {
        var start = animOffset - dashLength;
        while (start < metric.length) {
          final end = start + dashLength;
          if (end > 0) {
            canvas.drawPath(
              metric.extractPath(
                start < 0 ? 0 : start,
                end > metric.length ? metric.length : end,
              ),
              dashPaint,
            );
          }
          start += total;
        }
      }
    }

    void dot(Offset? p, Color color) {
      if (p == null) return;
      final c = scale(p);
      canvas.drawCircle(c, 3, Paint()..color = Colors.white);
      canvas.drawCircle(c, 2, Paint()..color = color);
    }

    dot(startPoint, AppColors.successGreen);
    if (showEndDot) dot(endPoint, AppColors.accentGold);
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.dashOffset != dashOffset ||
      old.pathPoints != pathPoints ||
      old.activePoints != activePoints ||
      old.completedPoints != completedPoints ||
      old.startPoint != startPoint ||
      old.endPoint != endPoint ||
      old.showEndDot != showEndDot;
}
