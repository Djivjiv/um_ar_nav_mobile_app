import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/facility_category.dart';
import '../../../core/utils/navigation_preference.dart';
import '../../../data/models/building_model.dart';
import '../../../data/models/facility_model.dart';

class FacilityDetailPage extends StatelessWidget {
  final FacilityModel facility;
  final String buildingName;
  final BuildingModel? building;

  const FacilityDetailPage({
    super.key,
    required this.facility,
    required this.buildingName,
    this.building,
  });

  String get _category =>
      FacilityCategory.normalize(facility.facilityCategories);

  String get _officeHours =>
      (facility.details?.officeHours?.trim().isNotEmpty ?? false)
          ? facility.details!.officeHours!
          : (facility.officeHours ?? '');

  String get _contact => facility.details?.contactNumber ?? '';
  String get _location => facility.location ?? '';
  List<String> get _services => facility.details?.services ?? const [];
  List<String> get _payments => facility.details?.paymentMethods ?? const [];
  List<String> get _instructions =>
      facility.details?.instructions ?? const [];

  void _navigate(BuildContext context) {
    if (building == null) return;
    final floorPart = facility.floor?.trim().isNotEmpty == true
        ? ' — Floor ${facility.floor}'
        : '';
    // Destination is the FACILITY (its name), routed via its building.
    NavigationPreference.setDestination({
      'id': facility.id.toString(),
      'name': facility.roomName,
      'subtitle': '$buildingName$floorPart',
      'type': 'facility',
      'building_id': facility.buildingId,
      'floor': facility.floor,
      'icon': Icons.meeting_room_outlined,
      'color': FacilityCategory.color(_category),
    });
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/map');
  }

  @override
  Widget build(BuildContext context) {
    final color = FacilityCategory.color(_category);
    final floorText = facility.floor?.trim().isNotEmpty == true
        ? ' · Floor ${facility.floor}'
        : '';

    return Scaffold(
      backgroundColor: AppColors.backgroundGray,
      appBar: AppBar(title: Text(facility.roomName)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header card
            _card(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(FacilityCategory.icon(_category),
                        color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(facility.roomName,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text('$buildingName$floorText',
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.accentGold,
                                fontWeight: FontWeight.w500)),
                        if (facility.roomNumber?.trim().isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _pill('Room ${facility.roomNumber}'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Information
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Information'),
                  const SizedBox(height: 8),
                  if (_officeHours.isNotEmpty) ...[
                    _infoRow(Icons.access_time, 'Office Hours', _officeHours),
                    const Divider(height: 16),
                  ],
                  if (_contact.isNotEmpty) ...[
                    _infoRow(Icons.phone, 'Contact', _contact),
                    const Divider(height: 16),
                  ],
                  if (_location.isNotEmpty)
                    _infoRow(Icons.location_on, 'Location', _location),
                  if (_officeHours.isEmpty &&
                      _contact.isEmpty &&
                      _location.isEmpty)
                    const Text('No additional information.',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                ],
              ),
            ),

            if (_services.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Services'),
                    const SizedBox(height: 8),
                    ..._services.map(
                      (s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: AppColors.accentGold, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(s,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_payments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Payment Methods'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _payments.map(_pill).toList(),
                    ),
                  ],
                ),
              ),
            ],

            if (_instructions.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Instructions'),
                    const SizedBox(height: 8),
                    ..._instructions.asMap().entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${e.key + 1}.',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryMaroon)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(e.value,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary)),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: building == null ? null : () => _navigate(context),
                icon: const Icon(Icons.directions,
                    color: AppColors.accentGold),
                label: const Text('Navigate Here',
                    style: TextStyle(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryMaroon,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryMaroon));

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.accentGold),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, color: AppColors.accentGold)),
      );

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primaryMaroon),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}
