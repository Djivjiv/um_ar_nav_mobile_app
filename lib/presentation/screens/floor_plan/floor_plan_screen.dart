import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/building_icon_map.dart';
import '../../../data/models/floor_plan_model.dart';
import '../../../data/models/indoor_node_model.dart';
import '../../../data/repositories/floor_plan_repository.dart';
import '../../bloc/navigation/indoor_nav_cubit.dart';
import '../../widgets/floor_plan_viewer.dart';
import '../../widgets/loading_skeleton.dart';

class FloorPlanScreen extends StatefulWidget {
  final int buildingId;
  final String? initialFloorPlanId;

  const FloorPlanScreen({
    super.key,
    required this.buildingId,
    this.initialFloorPlanId,
  });

  @override
  State<FloorPlanScreen> createState() => _FloorPlanScreenState();
}

class _FloorPlanScreenState extends State<FloorPlanScreen> {
  late final FloorPlanRepository _repo = context.read<FloorPlanRepository>();

  List<FloorPlanModel> _floors = const [];
  FloorPlanModel? _current;
  bool _loading = true;
  String? _error;
  bool _pickingFrom = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final floors = await _repo.getFloorsForBuilding(widget.buildingId);
      FloorPlanModel? initial;
      if (widget.initialFloorPlanId != null &&
          widget.initialFloorPlanId != '0') {
        for (final f in floors) {
          if (f.id.toString() == widget.initialFloorPlanId) initial = f;
        }
      }
      initial ??= floors.isNotEmpty ? floors.first : null;
      setState(() {
        _floors = floors;
        _current = initial;
        _loading = false;
      });
      if (initial != null) {
        // ignore: use_build_context_synchronously
        context.read<IndoorNavCubit>().loadFloor(initial.id.toString());
      }
    } catch (e) {
      setState(() {
        _error = 'Could not load floor plans.';
        _loading = false;
      });
    }
  }

  void _selectFloor(FloorPlanModel f) {
    setState(() => _current = f);
    context.read<IndoorNavCubit>().loadFloor(f.id.toString());
  }

  void _onNodeTap(IndoorNodeModel node) {
    final cubit = context.read<IndoorNavCubit>();
    showModalBottomSheet(
      context: context,
      builder: (_) => _NodeSheet(
        node: node,
        onNavigate: node.isNavigable
            ? () {
                if (_pickingFrom) {
                  cubit.setFrom(node);
                } else {
                  cubit.setTo(node);
                }
                setState(() => _pickingFrom = !_pickingFrom);
                Navigator.of(context).pop();
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Floor Plan')),
      body: _loading
          ? const _FloorLoading()
          : _error != null
              ? ErrorRetry(message: _error!, onRetry: _load)
              : _floors.isEmpty
                  ? const EmptyState(
                      message: 'No floor plans available for this building.')
                  : Column(
                      children: [
                        _FloorTabs(
                          floors: _floors,
                          current: _current,
                          onSelect: _selectFloor,
                        ),
                        Expanded(
                          child: BlocBuilder<IndoorNavCubit, IndoorNavState>(
                            builder: (context, nav) {
                              if (nav.status == IndoorNavStatus.loading) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              final pixels = nav.pathPixels
                                  .map((p) => Offset(p.longitude, p.latitude))
                                  .toList();
                              return FloorPlanViewer(
                                imageUrl: _current?.imageUrl,
                                nodes: nav.nodes,
                                pathPixels: pixels,
                                selectedNodeId: nav.fromNode?.id ??
                                    nav.toNode?.id,
                                onNodeTap: _onNodeTap,
                              );
                            },
                          ),
                        ),
                        _IndoorNavBar(pickingFrom: _pickingFrom),
                      ],
                    ),
    );
  }
}

class _FloorTabs extends StatelessWidget {
  final List<FloorPlanModel> floors;
  final FloorPlanModel? current;
  final ValueChanged<FloorPlanModel> onSelect;

  const _FloorTabs({
    required this.floors,
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: floors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = floors[i];
          final selected = f.id == current?.id;
          return ChoiceChip(
            label: Text(f.tabLabel),
            selected: selected,
            labelStyle: TextStyle(
                color: selected ? Colors.white : AppColors.textPrimary),
            onSelected: (_) => onSelect(f),
          );
        },
      ),
    );
  }
}

class _IndoorNavBar extends StatelessWidget {
  final bool pickingFrom;
  const _IndoorNavBar({required this.pickingFrom});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<IndoorNavCubit, IndoorNavState>(
      builder: (context, nav) {
        final cubit = context.read<IndoorNavCubit>();
        return Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _endpointChip(
                        'From',
                        nav.fromNode?.displayLabel,
                        AppColors.successGreen,
                        active: pickingFrom,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _endpointChip(
                        'To',
                        nav.toNode?.displayLabel,
                        AppColors.primaryMaroon,
                        active: !pickingFrom,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            (nav.fromNode != null && nav.toNode != null)
                                ? cubit.computeRoute
                                : null,
                        child: const Text('Find Indoor Route'),
                      ),
                    ),
                    if (nav.hasRoute) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: cubit.clearRoute,
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
                if (nav.status == IndoorNavStatus.error && nav.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(nav.error!,
                        style: const TextStyle(
                            color: AppColors.errorRed, fontSize: 12)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _endpointChip(String label, String? value, Color color,
      {required bool active}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active
            ? color.withValues(alpha: 0.12)
            : AppColors.backgroundGray,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: active ? color : Colors.transparent, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          Text(
            value ?? 'Tap a node',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _NodeSheet extends StatelessWidget {
  final IndoorNodeModel node;
  final VoidCallback? onNavigate;

  const _NodeSheet({required this.node, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (node.roomNumber != null)
            Text(node.roomNumber!,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryMaroon)),
          Text(
            node.roomName ?? node.name ?? node.displayLabel,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (node.label != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: BuildingIconMap.colorForNodeType(node.label)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(node.label!,
                  style: TextStyle(
                      fontSize: 12,
                      color: BuildingIconMap.colorForNodeType(node.label))),
            ),
          if (node.nodeDescription != null) ...[
            const SizedBox(height: 10),
            Text(node.nodeDescription!,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
          if (node.operatingHours != null)
            _row(Icons.access_time, node.operatingHours!),
          if (node.contact != null) _row(Icons.call, node.contact!),
          const SizedBox(height: 16),
          if (onNavigate != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.directions_walk),
                label: const Text('Navigate Here'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _FloorLoading extends StatelessWidget {
  const _FloorLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        SizedBox(height: 12),
        LoadingSkeleton(height: 34, width: 240),
        SizedBox(height: 16),
        Expanded(child: LoadingSkeleton(height: double.infinity)),
      ],
    );
  }
}
