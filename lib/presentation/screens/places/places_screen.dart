import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/facility_category.dart';
import '../../../core/utils/navigation_preference.dart';
import '../../../data/models/building_model.dart';
import '../../../data/models/facility_model.dart';
import 'facility_detail_page.dart';

enum _Status { loading, loaded, error }

/// A facility joined with its building name for display + filtering.
class _FacilityEntry {
  final FacilityModel facility;
  final String buildingName;
  const _FacilityEntry(this.facility, this.buildingName);
}

const _filters = [
  'All',
  'Buildings',
  'Facilities',
  'Laboratory',
  'Cashier',
  'Office',
  'Comfort Room',
  'Lecture Hall',
  'Chapel',
  'Clinic',
  'Library',
  'Canteen',
  'Other',
];

const _knownCategories = {
  'laboratory',
  'cashier',
  'office',
  'comfort room',
  'lecture hall',
  'chapel',
  'clinic',
  'library',
  'canteen',
};

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'All';

  _Status _status = _Status.loading;
  List<BuildingModel> _buildings = const [];
  List<_FacilityEntry> _facilities = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _status = _Status.loading);
    try {
      final supabase = Supabase.instance.client;

      final buildingRows = await supabase
          .from('buildings')
          .select('id, name, short_name, lat, lng, floor_count, '
              'opening_hours, contact, image_url, is_active')
          .eq('is_active', true)
          .order('name');

      final facilityRows = await supabase.from('facilities').select('''
            *,
            buildings(id, name),
            facility_details(
              id, facility_id, office_hours, contact_number,
              services, payment_method, instructions
            )
          ''').order('roomname');

      final buildings = (buildingRows as List)
          .map((e) => BuildingModel.fromMap(e as Map<String, dynamic>))
          .where((b) => b.lat != 0 && b.lng != 0)
          .toList();

      final facilities = <_FacilityEntry>[];
      for (final row in (facilityRows as List)) {
        final m = row as Map<String, dynamic>;
        final detailsRaw = m['facility_details'];
        FacilityDetailsModel? details;
        if (detailsRaw is List && detailsRaw.isNotEmpty) {
          details = FacilityDetailsModel.fromMap(
              detailsRaw.first as Map<String, dynamic>);
        } else if (detailsRaw is Map) {
          details = FacilityDetailsModel.fromMap(
              detailsRaw.cast<String, dynamic>());
        }
        final buildingName =
            (m['buildings'] as Map?)?['name']?.toString() ?? 'Building';
        facilities.add(_FacilityEntry(
          FacilityModel.fromMap(m, details: details),
          buildingName,
        ));
      }

      if (!mounted) return;
      setState(() {
        _buildings = buildings;
        _facilities = facilities;
        _status = _Status.loaded;
      });
    } catch (e) {
      debugPrint('Places load error: $e');
      if (mounted) setState(() => _status = _Status.error);
    }
  }

  void _navigateToBuilding(BuildingModel b) {
    NavigationPreference.setDestination({
      'id': b.id.toString(),
      'name': b.name,
      'subtitle': 'Building',
      'type': 'building',
      'lat': b.lat,
      'lng': b.lng,
      'icon': Icons.business,
      'color': AppColors.primaryMaroon,
    });
    context.go('/map');
  }

  void _openFacility(_FacilityEntry e) {
    final building = _buildings
        .cast<BuildingModel?>()
        .firstWhere((b) => b?.id == e.facility.buildingId, orElse: () => null);
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => FacilityDetailPage(
          facility: e.facility,
          buildingName: e.buildingName,
          building: building,
        ),
      ),
    );
  }

  // ── filtering ────────────────────────────────────────────

  bool get _showBuildings =>
      _filter == 'All' || _filter == 'Buildings';

  bool get _showFacilities =>
      _filter != 'Buildings';

  List<BuildingModel> get _filteredBuildings {
    if (!_showBuildings) return const [];
    final q = _query.toLowerCase();
    return _buildings.where((b) {
      return q.isEmpty ||
          b.name.toLowerCase().contains(q) ||
          (b.shortName ?? '').toLowerCase().contains(q) ||
          (b.displayName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  List<_FacilityEntry> get _filteredFacilities {
    if (!_showFacilities) return const [];
    final q = _query.toLowerCase();
    final f = _filter.toLowerCase();
    return _facilities.where((e) {
      final cat = FacilityCategory.normalize(e.facility.facilityCategories)
          .toLowerCase();

      final categoryOk = _filter == 'All' ||
          _filter == 'Facilities' ||
          (_filter == 'Other' && !_knownCategories.contains(cat)) ||
          cat == f;
      if (!categoryOk) return false;

      return q.isEmpty ||
          e.facility.roomName.toLowerCase().contains(q) ||
          e.buildingName.toLowerCase().contains(q) ||
          cat.contains(q);
    }).toList();
  }

  // ── build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundGray,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Explore Campus',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _searchBar(),
          _filterChips(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.primaryMaroon),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search buildings, facilities...',
                border: InputBorder.none,
              ),
            ),
          ),
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                _search.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
    );
  }

  Widget _filterChips() {
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final f in _filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _filter = f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _filter == f
                          ? AppColors.primaryMaroon
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _filter == f
                            ? AppColors.primaryMaroon
                            : const Color(0xFFD9C9B0),
                      ),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        fontSize: 12,
                        color: _filter == f
                            ? Colors.white
                            : AppColors.textSecondary,
                        fontWeight: _filter == f
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_status == _Status.loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryMaroon),
      );
    }
    if (_status == _Status.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off,
                size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text('Failed to load',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final buildings = _filteredBuildings;
    final facilities = _filteredFacilities;
    final total = buildings.length + facilities.length;

    if (total == 0) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 56, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text('No results found',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 15)),
            SizedBox(height: 4),
            Text('Try a different search',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: total,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i < buildings.length) {
            return _BuildingCard(
              building: buildings[i],
              onNavigate: () => _navigateToBuilding(buildings[i]),
            );
          }
          final e = facilities[i - buildings.length];
          return _FacilityCard(entry: e, onTap: () => _openFacility(e));
        },
      ),
    );
  }
}

// ────────────────────────── Building card ──────────────────────────

class _BuildingCard extends StatelessWidget {
  final BuildingModel building;
  final VoidCallback onNavigate;

  const _BuildingCard({
    required this.building,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 160,
            width: double.infinity,
            child: building.firstImage != null
                ? CachedNetworkImage(
                    imageUrl: building.firstImage!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => _placeholder(),
                    errorWidget: (_, _, _) => _placeholder(),
                  )
                : _placeholder(),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(building.label,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    if (!kNoRooms)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundGray,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${building.floorCount} floor(s)',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary)),
                      ),
                  ],
                ),
                if ((building.openingHours ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(building.openingHours!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: onNavigate,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Navigate'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get kNoRooms => kNoRoomsBuildingsPlaces.contains(building.name);

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF5F5F5),
      child: const Center(
        child: Icon(Icons.business_outlined,
            color: Color(0xFFBDBDBD), size: 42),
      ),
    );
  }
}

/// Buildings with no rooms — the floor-count pill is hidden for these.
const List<String> kNoRoomsBuildingsPlaces = [
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

// ────────────────────────── Facility card ──────────────────────────

class _FacilityCard extends StatelessWidget {
  final _FacilityEntry entry;
  final VoidCallback onTap;

  const _FacilityCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final f = entry.facility;
    final category = FacilityCategory.normalize(f.facilityCategories);
    final color = FacilityCategory.color(category);
    final floor = f.floor?.trim().isNotEmpty == true
        ? ' · Floor ${f.floor}'
        : '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(FacilityCategory.icon(category),
                        color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.roomName,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text('${entry.buildingName}$floor',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                        if (f.roomNumber?.trim().isNotEmpty == true)
                          Text('Room ${f.roomNumber}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.accentGold,
                                  fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(category,
                        style: TextStyle(
                            fontSize: 10,
                            color: color,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              if (_officeHours.isNotEmpty)
                _line(Icons.access_time, _officeHours),
              if (_contact.isNotEmpty) _line(Icons.phone, _contact),
            ],
          ),
        ),
      ),
    );
  }

  String get _officeHours =>
      (entry.facility.details?.officeHours?.trim().isNotEmpty ?? false)
          ? entry.facility.details!.officeHours!
          : (entry.facility.officeHours ?? '');

  String get _contact => entry.facility.details?.contactNumber ?? '';

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(icon, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
}
