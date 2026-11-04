import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/building_icon_map.dart';
import '../../bloc/building/building_cubit.dart';
import '../../widgets/floor_plans_button.dart';
import '../../widgets/loading_skeleton.dart';
import '../../widgets/route_start_picker.dart';

class BuildingDetailScreen extends StatefulWidget {
  final int buildingId;
  const BuildingDetailScreen({super.key, required this.buildingId});

  @override
  State<BuildingDetailScreen> createState() => _BuildingDetailScreenState();
}

class _BuildingDetailScreenState extends State<BuildingDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BuildingCubit>().selectBuilding(widget.buildingId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<BuildingCubit, BuildingState>(
        builder: (context, state) {
          if (state.detailStatus == BuildingStatus.loading) {
            return const _LoadingDetail();
          }
          if (state.detailStatus == BuildingStatus.error) {
            return Scaffold(
              appBar: AppBar(),
              body: ErrorRetry(
                message: state.selectedError ?? 'Failed to load.',
                onRetry: () => context
                    .read<BuildingCubit>()
                    .selectBuilding(widget.buildingId),
              ),
            );
          }
          final b = state.selectedBuilding;
          if (b == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const EmptyState(message: 'Building not found.'),
            );
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(b.label),
                  background: b.firstImage != null
                      ? CachedNetworkImage(
                          imageUrl: b.firstImage!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => _cover(),
                        )
                      : _cover(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.name,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      _info(Icons.access_time, b.openingHours ?? 'Hours N/A'),
                      if (b.contact != null)
                        InkWell(
                          onTap: () => _dial(b.contact!),
                          child: _info(Icons.call, b.contact!),
                        ),
                      _info(Icons.layers, '${b.floorCount} floor(s)'),
                      _info(
                        b.isAccessible
                            ? Icons.accessible
                            : Icons.not_accessible,
                        b.isAccessible
                            ? 'Wheelchair accessible'
                            : 'Accessibility unavailable',
                      ),
                      if (state.selectedRooms.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Rooms',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: state.selectedRooms
                              .map((r) => Chip(label: Text(r.label)))
                              .toList(),
                        ),
                      ],
                      if (state.selectedFacilities.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Facilities',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        ...state.selectedFacilities.map(
                          (f) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(BuildingIconMap.iconForCategory(
                                f.facilityCategories)),
                            title: Text(f.roomName),
                            subtitle: f.description.isNotEmpty
                                ? Text(f.description.join(' '))
                                : null,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // GPS start, else the user picks one — never a
                          // guessed start node.
                          final started =
                              await startRouteToBuilding(context, b);
                          if (started && context.mounted) context.go('/map');
                        },
                        icon: const Icon(Icons.directions),
                        label: const Text('Navigate Here'),
                      ),
                      FloorPlansButton(buildingId: widget.buildingId),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _cover() => Container(
        color: AppColors.primaryMaroon,
        child: const Center(
          child: Icon(Icons.location_city, size: 64, color: Colors.white38),
        ),
      );

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(color: AppColors.textSecondary))),
          ],
        ),
      );

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number.replaceAll(' ', ''));
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

class _LoadingDetail extends StatelessWidget {
  const _LoadingDetail();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          LoadingSkeleton(height: 180),
          SizedBox(height: 16),
          LoadingSkeleton(height: 24, width: 200),
          SizedBox(height: 12),
          LoadingSkeleton(height: 16),
          SizedBox(height: 8),
          LoadingSkeleton(height: 16),
          SizedBox(height: 8),
          LoadingSkeleton(height: 16, width: 150),
        ],
      ),
    );
  }
}
