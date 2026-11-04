import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/building_icon_map.dart';
import '../../data/models/building_model.dart';
import '../bloc/building/building_cubit.dart';
import 'floor_plans_button.dart';
import 'loading_skeleton.dart';

/// Buildings that have no rooms (gates, courts, small offices) — the "Floors"
/// row is hidden for these.
const List<String> kNoRoomsBuildings = [
  'Warehouse',
  'Study Hub',
  'Sports Complex',
  'Security Safety Office',
  'ROTC Field',
  'Motor Pool',
  'Matina Gate',
  'Maa Gate',
  'Food Courts',
  'Food Court 1',
  'Food Court 2',
  'FEA Covered Court',
  'Ecumenical Chapel',
  'Cagliari Hall',
  'Alumni Office',
];

/// Bottom sheet with building detail + navigate / floor-plan actions.
class BuildingBottomSheet extends StatelessWidget {
  final BuildingModel building;
  final VoidCallback? onNavigate;

  const BuildingBottomSheet({
    super.key,
    required this.building,
    this.onNavigate,
  });

  static Future<void> show(
    BuildContext context,
    BuildingModel building, {
    VoidCallback? onNavigate,
  }) {
    context.read<BuildingCubit>().selectBuilding(building.id);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BuildingBottomSheet(
        building: building,
        onNavigate: onNavigate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.2,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: BlocBuilder<BuildingCubit, BuildingState>(
            builder: (context, state) {
              final loading =
                  state.detailStatus == BuildingStatus.loading;
              final b = state.selectedBuilding ?? building;
              return ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundGray,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(b.name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (b.shortName != null)
                    _pill(b.shortName!, AppColors.accentGold),
                  const SizedBox(height: 14),
                  _image(b),
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 6),
                  if (b.openingHours?.isNotEmpty == true)
                    _infoRow(Icons.access_time, b.openingHours!),
                  if (b.contact?.isNotEmpty == true)
                    _infoRow(Icons.call, b.contact!),
                  if (!kNoRoomsBuildings.contains(b.name))
                    _infoRow(Icons.layers, '${b.floorCount} floor(s)'),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onNavigate?.call();
                    },
                    icon: const Icon(Icons.directions),
                    label: const Text('Navigate Here'),
                  ),
                  FloorPlansButton(buildingId: building.id),
                  const SizedBox(height: 16),
                  if (loading) const LoadingSkeleton(height: 40),
                  if (state.selectedFacilities.isNotEmpty) ...[
                    _sectionTitle('Facilities'),
                    const SizedBox(height: 4),
                    ...state.selectedFacilities.map(
                      (f) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          BuildingIconMap.iconForCategory(f.facilityCategories),
                          color: AppColors.primaryMaroon,
                        ),
                        title: Text(f.roomName),
                        subtitle: f.roomNumber != null
                            ? Text('Room ${f.roomNumber}')
                            : null,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _image(BuildingModel b) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: b.firstImage != null
            ? CachedNetworkImage(
                imageUrl: b.firstImage!,
                fit: BoxFit.cover,
                placeholder: (_, _) => _imgPlaceholder(),
                errorWidget: (_, _, _) => _imgPlaceholder(),
              )
            : _imgPlaceholder(),
      ),
    );
  }

  Widget _imgPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_outlined,
              size: 48, color: Color(0xFFBDBDBD)),
          SizedBox(height: 8),
          Text('No image available',
              style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15));

  Widget _pill(String text, Color color) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }
}
