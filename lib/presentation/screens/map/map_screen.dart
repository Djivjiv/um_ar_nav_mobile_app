import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/maptiler_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/navigation_phase_manager.dart';
import '../../../core/utils/navigation_preference.dart';
import '../../../data/models/building_model.dart';
import '../../../data/models/outdoor_node_model.dart';
import '../../../domain/services/dijkstra_service.dart';
import '../../bloc/building/building_cubit.dart';
import '../../bloc/navigation/outdoor_nav_cubit.dart';
import '../../bloc/search/search_cubit.dart';
import '../../widgets/building_bottom_sheet.dart';
import '../../widgets/navigation_path_painter.dart';
import '../../widgets/route_info_panel.dart';
import '../../widgets/um_map_widget.dart';
import '../../../services/unity_bridge_service.dart';
import '../ar/ar_navigation_screen.dart';
import '../ar/unity_ar_screen.dart';
import '../navigation/multi_phase_nav_screen.dart';
import 'search_destination_page.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _map = MapController();

  // ── Route planner state ──
  List<Map<String, dynamic>> _allDestinations = [];
  bool _isLoadingDestinations = false;
  Map<String, dynamic>? _selectedFrom;
  Map<String, dynamic>? _selectedTo;

  /// Room → room in the SAME building: no outdoor leg, so the review panel
  /// is driven from here instead of the OutdoorNavCubit.
  NavigationRoute? _indoorRoute;

  // ── Selected-place pin (from the search bar) ──
  Map<String, dynamic>? _selectedPlace;
  double? _selectedPlaceLat;
  double? _selectedPlaceLng;
  String? _buildingImageUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BuildingCubit>().loadBuildings();
      context.read<OutdoorNavCubit>().ensureGraph();
      _consumePendingDestination();
    });
  }

  /// If another screen (e.g. Places) stashed a destination, open the route
  /// planner here with it pre-filled as the "To".
  Future<void> _consumePendingDestination() async {
    if (!NavigationPreference.hasPendingDestination) return;
    final dest = NavigationPreference.getAndClear();
    if (dest == null || !mounted) return;
    setState(() => _selectedTo = dest);
    await _showRoutePlanner(keepTo: true);
  }

  void _recenterMap() {
    _map.move(MapTilerConfig.campusCenter, 17.5);
  }

  String? _buildingNameFor(dynamic id) {
    if (id == null || _buildings.isEmpty) return null;
    for (final b in _buildings) {
      if (b.id.toString() == id.toString()) return b.name;
    }
    return null;
  }

  /// Builds a [NavigationRoute] from the current endpoints + Dijkstra result
  /// and launches the multi-phase navigation flow.
  Future<void> _onStartNavigation(OutdoorNavState navState) async {
    if (!navState.hasRoute) return;

    final from = _selectedFrom ??
        {'type': 'building', 'name': navState.from?.label ?? 'Start'};
    final to = _selectedTo ??
        {'type': 'building', 'name': navState.to?.label ?? 'Destination'};

    final phases =
        NavigationRoute.determinePhases(from: from, to: to);

    // Destination building id + elevator check.
    final destBuildingId = to['type'] == 'building'
        ? to['id']?.toString()
        : to['building_id']?.toString();

    var hasElevator = false;
    if (destBuildingId != null) {
      try {
        final rows = await Supabase.instance.client
            .from('indoor_nodes')
            .select('id')
            .eq('building_id', destBuildingId)
            .eq('label', 'elevator')
            .limit(1);
        hasElevator = (rows as List).isNotEmpty;
      } catch (_) {}
    }
    if (!mounted) return;

    final fromBuildingId = from['type'] == 'building'
        ? from['id']?.toString()
        : from['building_id']?.toString();

    int? destFloor;
    final rawFloor = to['floor'];
    if (rawFloor is int) {
      destFloor = rawFloor;
    } else if (rawFloor != null) {
      destFloor = int.tryParse(rawFloor.toString());
    }

    final route = NavigationRoute(
      from: from,
      to: to,
      phases: phases,
      originBuildingId: fromBuildingId,
      originBuildingName: from['type'] == 'building'
          ? (from['name'] as String?)
          : _buildingNameFor(fromBuildingId),
      originRoomName: from['name'] as String?,
      destBuildingId: destBuildingId,
      destBuildingName: to['type'] == 'building'
          ? (to['name'] as String?)
          : _buildingNameFor(destBuildingId),
      destRoomName: to['name'] as String?,
      destFloor: destFloor,
      outdoorPath: navState.path,
      fromName: navState.from?.label,
      toName: navState.to?.label,
      distanceMeters: navState.distanceMeters,
      estimatedMinutes: navState.walkMinutes,
      hasElevator: hasElevator,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => MultiPhaseNavScreen(navigationRoute: route),
      ),
    );
  }

  Future<void> _onStartARNavigation(OutdoorNavState navState) async {
    if (!navState.hasRoute || navState.path.length < 2) return;
    final fromName =
        navState.from?.label ?? _selectedFrom?['name'] as String? ?? 'Start';
    final toName = navState.to?.label ??
        _selectedTo?['name'] as String? ??
        'Destination';
    final buildingId =
        _selectedTo != null ? _buildingIdFor(_selectedTo!)?.toString() : null;
    final useUnity = await UnityBridgeService.instance.isAvailable();
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => useUnity
            ? UnityArScreen(
                routePoints: navState.path,
                buildingId: buildingId ?? '',
                destinationName: toName,
                fromName: fromName,
                distanceMeters: navState.distanceMeters,
                destinationLatLng: navState.path.last,
              )
            : ARNavigationScreen(
                routePoints: navState.path,
                fromName: fromName,
                toName: toName,
                distanceMeters: navState.distanceMeters,
                destinationLatLng: navState.path.last,
              ),
      ),
    );
  }

  // ───────────────────── Selected place (search) ─────────────────────

  List<BuildingModel> get _buildings =>
      context.read<BuildingCubit>().state.buildings;

  Future<void> _onPlaceSelected(Map<String, dynamic> place) async {
    double? lat;
    double? lng;

    // The building this place belongs to (for coords + image).
    final buildingIdKey = place['type'] == 'building'
        ? place['id']
        : place['building_id'];
    BuildingModel? building;
    if (buildingIdKey != null && _buildings.isNotEmpty) {
      building = _buildings.firstWhere(
        (b) => b.id.toString() == buildingIdKey.toString(),
        orElse: () => _buildings.first,
      );
    }

    if (place['type'] == 'building') {
      lat = (place['lat'] as num?)?.toDouble() ?? building?.lat;
      lng = (place['lng'] as num?)?.toDouble() ?? building?.lng;
    } else {
      lat = building?.lat;
      lng = building?.lng;
    }

    if (lat == null || lng == null) return;

    _buildingImageUrl =
        (building?.firstImage?.isNotEmpty == true) ? building!.firstImage : null;

    setState(() {
      _selectedPlace = place;
      _selectedPlaceLat = lat;
      _selectedPlaceLng = lng;
    });
    _map.move(LatLng(lat, lng), 18.0);

    // Load facilities for the building so the sheet can list them.
    final bId = _buildingIdFor(place);
    if (bId != null) context.read<BuildingCubit>().selectBuilding(bId);

    if (!mounted) return;
    _showPlaceBottomSheet(place, lat, lng);
  }

  void _clearSelectedPlace() {
    if (!mounted) return;
    setState(() {
      _selectedPlace = null;
      _selectedPlaceLat = null;
      _selectedPlaceLng = null;
    });
  }

  void _showPlaceBottomSheet(
      Map<String, dynamic> place, double lat, double lng) {
    final type = place['type'] as String;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.3,
        maxChildSize: 0.75,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: (place['color'] as Color)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(place['icon'] as IconData,
                          color: place['color'] as Color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(place['name'] as String,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary)),
                          Text(place['subtitle'] as String,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: type == 'building'
                            ? const Color(0xFFF5E6E6)
                            : type == 'room'
                                ? const Color(0xFFE6EEF9)
                                : const Color(0xFFFFF8E7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        type == 'building'
                            ? 'Building'
                            : type == 'room'
                                ? 'Room'
                                : 'Facility',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: type == 'building'
                              ? AppColors.primaryMaroon
                              : type == 'room'
                                  ? AppColors.infoBlue
                                  : AppColors.accentGold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: (_buildingImageUrl != null &&
                          _buildingImageUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: _buildingImageUrl!,
                          width: double.infinity,
                          height: 180,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: double.infinity,
                            height: 180,
                            color: const Color(0xFFF5F5F5),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primaryMaroon,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) =>
                              _noImageWidget(),
                        )
                      : _noImageWidget(),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                // Info rows
                if (type == 'building') ...[
                  if (_buildingField(place['id'], (b) => b.openingHours) !=
                      'N/A') ...[
                    _detailRow(Icons.access_time, 'Hours',
                        _buildingField(place['id'], (b) => b.openingHours)),
                    const SizedBox(height: 8),
                  ],
                  if (_buildingField(place['id'], (b) => b.contact) !=
                      'N/A') ...[
                    _detailRow(Icons.phone, 'Contact',
                        _buildingField(place['id'], (b) => b.contact)),
                    const SizedBox(height: 8),
                  ],
                  if (!kNoRoomsBuildings.contains(_buildingName(place['id'])))
                    _detailRow(Icons.layers, 'Floors',
                        _buildingFloors(place['id'])),
                ] else ...[
                  _detailRow(
                    Icons.business,
                    'Building',
                    place['subtitle'].toString().split('—').first.trim(),
                  ),
                  const SizedBox(height: 8),
                  _detailRow(Icons.stairs, 'Floor',
                      'Floor ${place['floor'] ?? 1}'),
                ],
                // Facilities section (before the buttons for this sheet)
                if (type == 'building')
                  BlocBuilder<BuildingCubit, BuildingState>(
                    builder: (context, state) {
                      if (state.selectedFacilities.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          const Text('Facilities',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          ...state.selectedFacilities.map(
                            (f) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.meeting_room_outlined,
                                  color: AppColors.primaryMaroon),
                              title: Text(f.roomName),
                              subtitle: f.roomNumber != null
                                  ? Text('Room ${f.roomNumber}')
                                  : null,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 20),
                // Navigate Here
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _selectedTo = place);
                      _showRoutePlanner(keepTo: true);
                    },
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
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    ).whenComplete(_clearSelectedPlace);
  }

  Widget _noImageWidget() {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
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

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primaryMaroon),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
            Text(value.isEmpty ? 'N/A' : value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }

  String _buildingField(
      dynamic id, String? Function(BuildingModel) pick) {
    if (_buildings.isEmpty) return 'N/A';
    final b = _buildings.firstWhere(
      (b) => b.id.toString() == id.toString(),
      orElse: () => _buildings.first,
    );
    return pick(b) ?? 'N/A';
  }

  String _buildingFloors(dynamic id) {
    if (_buildings.isEmpty) return 'N/A';
    final b = _buildings.firstWhere(
      (b) => b.id.toString() == id.toString(),
      orElse: () => _buildings.first,
    );
    return '${b.floorCount} ${b.floorCount == 1 ? "floor" : "floors"}';
  }

  String _buildingName(dynamic id) {
    if (_buildings.isEmpty) return '';
    return _buildings
        .firstWhere(
          (b) => b.id.toString() == id.toString(),
          orElse: () => _buildings.first,
        )
        .name;
  }

  // ───────────────────────── Destinations ─────────────────────────

  Future<void> _loadDestinations() async {
    if (_allDestinations.isNotEmpty) return;
    setState(() => _isLoadingDestinations = true);

    final supabase = Supabase.instance.client;
    final destinations = <Map<String, dynamic>>[];

    try {
      final buildings = await supabase
          .from('buildings')
          .select('id, name, short_name, lat, lng')
          .not('lat', 'is', null)
          .order('name');

      for (final b in buildings) {
        destinations.add({
          'id': b['id'].toString(),
          'name': b['name']?.toString() ?? 'Building',
          'subtitle': 'Building',
          'type': 'building',
          'lat': b['lat'],
          'lng': b['lng'],
          'icon': Icons.business,
          'color': AppColors.primaryMaroon,
        });
      }

      final rooms = await supabase
          .from('rooms')
          .select('id, roomname, floor, building_id, buildings(name)')
          .order('roomname');

      for (final r in rooms) {
        final buildingName =
            (r['buildings'] as Map?)?['name']?.toString() ??
                'Unknown Building';
        destinations.add({
          'id': r['id'].toString(),
          'name': r['roomname']?.toString() ?? 'Room',
          'subtitle': '$buildingName — Floor ${r['floor'] ?? '—'}',
          'type': 'room',
          'building_id': r['building_id'],
          'floor': r['floor'],
          'icon': Icons.door_front_door_outlined,
          'color': AppColors.infoBlue,
        });
      }

      final facilities = await supabase
          .from('facilities')
          .select(
              'id, roomname, room_number, floor, building_id, buildings(name)')
          .order('roomname');

      for (final f in facilities) {
        final buildingName =
            (f['buildings'] as Map?)?['name']?.toString() ??
                'Unknown Building';
        final roomNumber = f['room_number']?.toString() ?? '';
        final displayName = roomNumber.isNotEmpty
            ? '$roomNumber — ${f['roomname'] ?? ''}'
            : (f['roomname']?.toString() ?? 'Facility');
        destinations.add({
          'id': f['id'].toString(),
          'name': displayName,
          'subtitle': '$buildingName — Floor ${f['floor'] ?? '—'}',
          'type': 'facility',
          'building_id': f['building_id'],
          'floor': f['floor'],
          'icon': Icons.meeting_room_outlined,
          'color': AppColors.accentGold,
        });
      }

      if (!mounted) return;
      setState(() {
        _allDestinations = destinations;
        _isLoadingDestinations = false;
      });
    } catch (e) {
      debugPrint('Load destinations error: $e');
      if (mounted) setState(() => _isLoadingDestinations = false);
    }
  }

  // ───────────────────────── Route planner sheet ─────────────────────────

  Future<void> _showRoutePlanner({bool keepTo = false}) async {
    // Always reset the origin; keep a pre-filled destination when asked.
    _selectedFrom = null;
    if (!keepTo) _selectedTo = null;
    if (_indoorRoute != null) setState(() => _indoorRoute = null);
    if (_allDestinations.isEmpty) {
      await _loadDestinations();
    }
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Text('Plan a Route',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoadingDestinations
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primaryMaroon))
                      : SingleChildScrollView(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('From',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              _buildPickerButton(
                                selected: _selectedFrom,
                                hint: 'Select starting point',
                                onTap: () async {
                                  final result =
                                      await _showSearchSheet(context);
                                  if (result != null) {
                                    setSheetState(
                                        () => _selectedFrom = result);
                                  }
                                },
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: GestureDetector(
                                  onTap: () => setSheetState(() {
                                    final temp = _selectedFrom;
                                    _selectedFrom = _selectedTo;
                                    _selectedTo = temp;
                                  }),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.backgroundGray,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: const Color(0xFFD9C9B0)),
                                    ),
                                    child: const Icon(Icons.swap_vert,
                                        color: AppColors.primaryMaroon,
                                        size: 20),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text('To',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              _buildPickerButton(
                                selected: _selectedTo,
                                hint: 'Select destination',
                                onTap: () async {
                                  final result =
                                      await _showSearchSheet(context);
                                  if (result != null) {
                                    setSheetState(
                                        () => _selectedTo = result);
                                  }
                                },
                              ),
                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton.icon(
                                  onPressed: (_selectedFrom != null &&
                                          _selectedTo != null)
                                      ? () {
                                          Navigator.pop(context);
                                          _findRoute(_selectedFrom!,
                                              _selectedTo!);
                                        }
                                      : null,
                                  icon: const Icon(Icons.directions,
                                      color: AppColors.accentGold),
                                  label: const Text('Find Route',
                                      style: TextStyle(
                                          color: AppColors.accentGold,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        AppColors.primaryMaroon,
                                    disabledBackgroundColor:
                                        Colors.grey[300],
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPickerButton({
    required Map<String, dynamic>? selected,
    required String hint,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.backgroundGray,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected != null
                ? AppColors.primaryMaroon
                : const Color(0xFFD9C9B0),
            width: selected != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected != null
                  ? selected['icon'] as IconData
                  : Icons.search,
              color: selected != null
                  ? selected['color'] as Color
                  : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selected != null
                        ? selected['name'] as String
                        : hint,
                    style: TextStyle(
                      fontSize: 14,
                      color: selected != null
                          ? AppColors.textPrimary
                          : const Color(0xFF9E9E9E),
                      fontWeight: selected != null
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (selected != null)
                    Text(
                      selected['subtitle'] as String,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_drop_down,
                color: AppColors.textSecondary, size: 24),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showSearchSheet(BuildContext context) {
    // Push on the ROOT navigator so the full-screen search page covers the
    // shell (the floating search bar, bottom nav and DEV banner live there),
    // instead of the shell navigator where the map's overlays stay on top.
    return Navigator.of(context, rootNavigator: true)
        .push<Map<String, dynamic>>(
      MaterialPageRoute<Map<String, dynamic>>(
        fullscreenDialog: true,
        builder: (_) => SearchDestinationPage(
          destinations: _allDestinations,
        ),
      ),
    );
  }

  // ───────────────────────── Routing ─────────────────────────

  LatLng? _latLngFor(Map<String, dynamic> dest) {
    if (dest['type'] == 'building' && dest['lat'] != null) {
      final lat = (dest['lat'] as num).toDouble();
      final lng = (dest['lng'] as num).toDouble();
      return LatLng(lat, lng);
    }
    final buildingId = _buildingIdFor(dest);
    if (buildingId == null) return null;
    return context.read<BuildingCubit>().buildingById(buildingId)?.location;
  }

  int? _buildingIdFor(Map<String, dynamic> dest) {
    if (dest['type'] == 'building') {
      return int.tryParse(dest['id'].toString());
    }
    final raw = dest['building_id'];
    if (raw is int) return raw;
    return int.tryParse(raw.toString());
  }

  void _routeSnack(String message) {
    debugPrint('❌ $message');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primaryMaroon,
      ),
    );
  }

  /// Picks the entrance of [buildingId] that is closest to [fromNodeId] by
  /// actual path (Dijkstra) distance, not GPS straight line. Returns `null`
  /// when the building has no entrance nodes so the caller can fall back to
  /// nearest-by-GPS.
  /// Among several origin entrances, the one whose shortest path to
  /// [toNodeId] is shortest (Dijkstra distance).
  String _bestEntranceTowards(
      List<OutdoorNodeModel> entrances, String? toNodeId) {
    if (entrances.length == 1 || toNodeId == null) {
      return entrances.first.id;
    }
    final nav = context.read<OutdoorNavCubit>();
    var best = entrances.first.id;
    var bestDist = double.infinity;
    for (final e in entrances) {
      final result = DijkstraService.findShortestPath(
        startNodeId: e.id,
        endNodeId: toNodeId,
        nodes: nav.repo.nodes,
        edges: nav.repo.edges,
      );
      final d = result?.distanceMeters ?? double.infinity;
      debugPrint('   FROM entrance ${e.id} '
          '(${e.entranceLabel ?? e.name ?? "?"}): '
          '${d.isFinite ? d.toStringAsFixed(0) : "∞"}m');
      if (d < bestDist) {
        bestDist = d;
        best = e.id;
      }
    }
    debugPrint('✅ FROM best entrance: $best '
        '(${bestDist.isFinite ? bestDist.toStringAsFixed(0) : "∞"}m)');
    return best;
  }

  Future<String?> _findBestEntrance({
    required String fromNodeId,
    required int buildingId,
  }) async {
    final nav = context.read<OutdoorNavCubit>();
    final entrances = nav.repo.nodes
        .where((n) => n.buildingId == buildingId && n.isEntrance)
        .toList();

    debugPrint('🏢 Building $buildingId has ${entrances.length} entrance(s):');
    for (final e in entrances) {
      debugPrint('   ${e.id} — ${e.entranceLabel ?? e.name ?? "?"}');
    }

    if (entrances.isEmpty) return null;
    if (entrances.length == 1) return entrances.first.id;

    // findPathToBuilding runs Dijkstra from the start and returns the path to
    // the FIRST entrance it reaches — i.e. the nearest one by graph distance.
    final result = DijkstraService.findPathToBuilding(
      startNodeId: fromNodeId,
      buildingId: buildingId,
      nodes: nav.repo.nodes,
      edges: nav.repo.edges,
    );
    if (result == null || result.nodeIds.isEmpty) return null;

    final best = result.nodeIds.last;
    debugPrint('✅ Best entrance (by path): $best — '
        '${result.distanceMeters.toStringAsFixed(0)}m');
    return best;
  }

  static int? _floorOf(Map<String, dynamic> m) {
    final raw = m['floor'];
    if (raw is int) return raw;
    if (raw != null) return int.tryParse(raw.toString());
    return null;
  }

  /// Rough indoor distance (metres) + walk seconds between two rooms in the
  /// same building — straight-line node-to-node on the origin floor, scaled by
  /// `building_floors.scale_factor`, plus ~15 m per floor when they differ.
  Future<({double meters, int seconds})> _indoorRouteEstimate({
    required String buildingId,
    String? fromRoomId,
    String? toRoomId,
    required int fromFloor,
    required int toFloor,
  }) async {
    var meters = 0.0;
    try {
      final supabase = Supabase.instance.client;
      final floorPlan = await supabase
          .from('building_floors')
          .select('id, scale_factor')
          .eq('building_id', buildingId)
          .eq('floor_number', fromFloor <= 1 ? 1 : fromFloor)
          .eq('is_active', true)
          .maybeSingle();

      if (floorPlan != null) {
        final rows = await supabase
            .from('indoor_nodes')
            .select('x, y, is_entrance, is_navigable, linked_room_id')
            .eq('floor_plan_id', floorPlan['id']);
        final nodes = (rows as List)
            .cast<Map<String, dynamic>>()
            .where((n) => n['is_navigable'] != false)
            .toList();

        if (nodes.isNotEmpty) {
          Map<String, dynamic>? linked(String? roomId) {
            if (roomId == null) return null;
            for (final n in nodes) {
              if (n['linked_room_id']?.toString() == roomId) return n;
            }
            return null;
          }

          Map<String, dynamic> entranceOrFirst() {
            for (final n in nodes) {
              if (n['is_entrance'] == true) return n;
            }
            return nodes.first;
          }

          final fromNode = linked(fromRoomId) ?? entranceOrFirst();
          final toNode = linked(toRoomId) ?? nodes.last;

          double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
          final dx = d(fromNode['x']) - d(toNode['x']);
          final dy = d(fromNode['y']) - d(toNode['y']);
          final pixels = math.sqrt(dx * dx + dy * dy);

          final scale = (floorPlan['scale_factor'] as num?)?.toDouble() ?? 0;
          meters = pixels * (scale > 0 && scale < 0.5 ? scale : 0.05);
        }
      }
    } catch (e) {
      debugPrint('Indoor distance calc: $e');
    }

    if (fromFloor != toFloor) {
      meters += (toFloor - fromFloor).abs() * 15.0;
    }
    return (meters: meters, seconds: (meters / 0.8).ceil());
  }

  Future<bool> _buildingHasElevator(String buildingId) async {
    try {
      final rows = await Supabase.instance.client
          .from('indoor_nodes')
          .select('id')
          .eq('building_id', buildingId)
          .eq('label', 'elevator')
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (e) {
      debugPrint('Elevator check failed: $e');
      return false;
    }
  }

  Future<void> _findRoute(
      Map<String, dynamic> from, Map<String, dynamic> to) async {
    debugPrint('🗺 Finding route...');
    debugPrint('   From: ${from['name']}  (type: ${from['type']})');
    debugPrint('   To:   ${to['name']}  (type: ${to['type']})');

    setState(() => _indoorRoute = null);

    // ── Same building, indoor → indoor: skip the outdoor leg entirely. ──
    final fromType = (from['type'] ?? 'building').toString();
    final toType = (to['type'] ?? 'building').toString();
    final fromBId = _buildingIdFor(from);
    final toBId = _buildingIdFor(to);
    final sameBuilding = fromBId != null && toBId != null && fromBId == toBId;
    final bothIndoor = (fromType == 'room' || fromType == 'facility') &&
        (toType == 'room' || toType == 'facility');

    if (sameBuilding && bothIndoor) {
      final fromFloor = _floorOf(from);
      final toFloor = _floorOf(to);
      debugPrint('🏢 Same building ($fromBId) — indoor navigation only '
          '(floor $fromFloor → $toFloor)');

      final estimate = await _indoorRouteEstimate(
        buildingId: fromBId.toString(),
        fromRoomId:
            from['type'] != 'building' ? from['id']?.toString() : null,
        toRoomId: to['type'] != 'building' ? to['id']?.toString() : null,
        fromFloor: fromFloor ?? 1,
        toFloor: toFloor ?? 1,
      );
      if (!mounted) return;
      debugPrint('   Estimate: ${estimate.meters.toStringAsFixed(0)}m / '
          '${estimate.seconds}s');

      final route = NavigationRoute(
        from: from,
        to: to,
        phases: NavigationRoute.determinePhases(from: from, to: to),
        originFloor: fromFloor,
        originBuildingId: fromBId.toString(),
        originBuildingName: _buildingNameFor(fromBId),
        originRoomName: from['name'] as String?,
        destBuildingId: toBId.toString(),
        destBuildingName: _buildingNameFor(toBId),
        destRoomName: to['name'] as String?,
        destFloor: toFloor,
        fromName: from['name'] as String?,
        toName: to['name'] as String?,
        hasElevator: await _buildingHasElevator(toBId.toString()),
        startInTopView: fromFloor == toFloor,
        distanceMeters: estimate.meters,
        estimatedMinutes: (estimate.seconds / 60).ceil(),
      );
      if (!mounted) return;
      setState(() => _indoorRoute = route);
      return;
    }

    final nav = context.read<OutdoorNavCubit>();
    await nav.ensureGraph();
    if (!mounted) return;

    debugPrint('   Graph loaded: ${nav.repo.nodes.length} nodes, '
        '${nav.repo.edges.length} edges');
    if (nav.repo.nodes.isEmpty) {
      _routeSnack('Campus map is still loading. Please try again.');
      return;
    }

    // Resolve BOTH endpoints to a LatLng, then snap each to its nearest
    // graph node. This does not depend on outdoor_nodes.building_id /
    // is_entrance being populated.
    final fromLatLng = _latLngFor(from);
    final toLatLng = _latLngFor(to);
    debugPrint('   fromLatLng: $fromLatLng');
    debugPrint('   toLatLng:   $toLatLng');
    if (fromLatLng == null || toLatLng == null) {
      _routeSnack('Could not resolve those locations on the map.');
      return;
    }

    // A rough destination node used only to score the origin's entrances.
    final toBuildingId = _buildingIdFor(to);
    String? roughToNodeId;
    if (toBuildingId != null) {
      final toEnt = nav.repo.nodes
          .where((n) => n.buildingId == toBuildingId && n.isEntrance)
          .toList();
      if (toEnt.isNotEmpty) roughToNodeId = toEnt.first.id;
    }
    roughToNodeId ??=
        nav.repo.nearestNode(toLatLng.latitude, toLatLng.longitude)?.id;

    // ── FROM node ──
    // building / room / facility all belong to a building — start at an
    // entrance of that building. With several entrances, pick the one whose
    // path to the destination is shortest; else nearest by GPS.
    String? fromNodeId;
    final fromBuildingId = _buildingIdFor(from);
    if (fromBuildingId != null) {
      final entrances = nav.repo.nodes
          .where((n) => n.buildingId == fromBuildingId && n.isEntrance)
          .toList();
      debugPrint('🏢 FROM building $fromBuildingId: '
          '${entrances.length} entrance(s)');
      if (entrances.length == 1) {
        fromNodeId = entrances.first.id;
        debugPrint('✅ FROM single entrance: $fromNodeId');
      } else if (entrances.length > 1) {
        fromNodeId = _bestEntranceTowards(entrances, roughToNodeId);
      }
    }
    fromNodeId ??=
        nav.repo.nearestNode(fromLatLng.latitude, fromLatLng.longitude)?.id;

    // ── TO node ──
    // For a building destination OR a room/facility, resolve the target
    // building and pick the entrance nearest to the start by actual path
    // (Dijkstra) distance; else nearest by GPS.
    String? toNodeId;
    if (fromNodeId != null && toBuildingId != null) {
      final entrances = nav.repo.nodes
          .where((n) => n.buildingId == toBuildingId && n.isEntrance)
          .toList();
      debugPrint('   TO: building $toBuildingId has '
          '${entrances.length} entrance(s)');
      if (entrances.isNotEmpty) {
        toNodeId = await _findBestEntrance(
          fromNodeId: fromNodeId,
          buildingId: toBuildingId,
        );
        if (!mounted) return;
      }
    }
    toNodeId ??=
        nav.repo.nearestNode(toLatLng.latitude, toLatLng.longitude)?.id;

    debugPrint('   start node: $fromNodeId');
    debugPrint('   end node:   $toNodeId');
    if (fromNodeId == null || toNodeId == null) {
      _routeSnack('The campus path network is not available yet.');
      return;
    }
    if (fromNodeId == toNodeId) {
      _routeSnack('Start and destination are at the same place.');
      return;
    }

    debugPrint('🧭 Running Dijkstra: $fromNodeId → $toNodeId');
    await nav.findRouteBetween(
      fromNodeId: fromNodeId,
      toNodeId: toNodeId,
      fromName: from['name'] as String,
      toName: to['name'] as String,
    );
    if (!mounted) return;
    final s = nav.state;
    debugPrint('   result: status=${s.status} hasRoute=${s.hasRoute} '
        'points=${s.path.length} error=${s.error}');
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Search overlay hands a picked place here → pin + camera + sheet.
          BlocListener<SearchCubit, SearchState>(
            listenWhen: (a, b) => b.pickedPlace != null,
            listener: (context, state) {
              final place = state.pickedPlace!;
              context.read<SearchCubit>().consumePickedPlace();
              _onPlaceSelected(place);
            },
            child: const SizedBox.shrink(),
          ),
          BlocBuilder<BuildingCubit, BuildingState>(
            builder: (context, bState) {
              return BlocConsumer<OutdoorNavCubit, OutdoorNavState>(
                listener: (context, navState) {
                  if (navState.status == OutdoorNavStatus.error &&
                      navState.error != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(navState.error!)),
                    );
                  }
                  if (navState.hasRoute) {
                    _fitRoute(navState.path);
                  }
                },
                builder: (context, navState) {
                  final polylines = navState.hasRoute
                      ? NavigationPathPainter.build(navState.path)
                      : <Polyline>[];
                  final markers = <Marker>[
                    if (navState.hasRoute)
                      ...NavigationPathPainter.endpointMarkers(navState.path),
                    if (_selectedPlace != null &&
                        _selectedPlaceLat != null &&
                        _selectedPlaceLng != null)
                      _placePin(),
                  ];

                  return UmMapWidget(
                    controller: _map,
                    buildings: bState.buildings,
                    polylines: polylines,
                    extraMarkers: markers,
                    onBuildingTap: _onBuildingTap,
                  );
                },
              );
            },
          ),

          // Loading / error overlays for buildings.
          BlocBuilder<BuildingCubit, BuildingState>(
            builder: (context, s) {
              if (s.status == BuildingStatus.loading && s.buildings.isEmpty) {
                return const Positioned(
                  top: 76,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Chip(label: Text('Loading campus...')),
                    ),
                  ),
                );
              }
              if (s.status == BuildingStatus.error) {
                return Positioned(
                  top: 76,
                  left: 16,
                  right: 16,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.errorRed),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s.error ?? 'Failed to load')),
                          TextButton(
                            onPressed: () => context
                                .read<BuildingCubit>()
                                .loadBuildings(forceRefresh: true),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // Recenter + route-planner FABs, just above the bottom nav bar.
          // Hidden while the route info panel is showing.
          BlocBuilder<OutdoorNavCubit, OutdoorNavState>(
            builder: (context, navState) {
              if (navState.hasRoute) return const SizedBox.shrink();
              return Positioned(
                right: 16,
                bottom: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton(
                      heroTag: 'navigate',
                      onPressed: _showRoutePlanner,
                      backgroundColor: AppColors.primaryMaroon,
                      child: const Icon(Icons.directions,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'recenter',
                      onPressed: _recenterMap,
                      backgroundColor: Colors.white,
                      child: const Icon(Icons.my_location,
                          color: AppColors.primaryMaroon),
                    ),
                  ],
                ),
              );
            },
          ),

          // Route info panel.
          BlocBuilder<OutdoorNavCubit, OutdoorNavState>(
            builder: (context, navState) {
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                left: 12,
                right: 12,
                // Sit just above the bottom nav bar (the Stack's bottom edge
                // is the top of MainScreen's bottomNavigationBar).
                bottom: navState.hasRoute ? 12 : -400,
                child: navState.hasRoute
                    ? RouteInfoPanel(
                        state: navState,
                        onStart: () => _onStartNavigation(navState),
                        onARNavigation: () => _onStartARNavigation(navState),
                        onClear: () =>
                            context.read<OutdoorNavCubit>().clearRoute(),
                      )
                    : const SizedBox.shrink(),
              );
            },
          ),

          // Indoor-only (room → room, same building) review panel.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
            left: 12,
            right: 12,
            bottom: _indoorRoute != null ? 12 : -400,
            child: _indoorRoute != null
                ? _indoorRoutePanel(_indoorRoute!)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _indoorStat(String value, String label, Color color,
      {double fontSize = 20}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _indoorRoutePanel(NavigationRoute route) {
    final sameFloor = route.originFloor == route.destFloor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF5E6E6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.business,
                    size: 14, color: AppColors.primaryMaroon),
                SizedBox(width: 4),
                Text('Indoor Navigation',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primaryMaroon,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.radio_button_checked,
                  color: AppColors.successGreen, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text('From: ${route.fromName ?? ''}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on,
                  color: AppColors.primaryMaroon, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text('To: ${route.toName ?? ''}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            children: [
              const Icon(Icons.business_outlined,
                  color: AppColors.primaryMaroon, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(route.destBuildingName ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
              ),
              Text(
                sameFloor
                    ? 'Floor ${route.destFloor ?? 1}'
                    : 'Floor ${route.originFloor ?? 1} → '
                        'Floor ${route.destFloor ?? 1}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _indoorStat(
                (route.distanceMeters ?? 0) > 0
                    ? '${route.distanceMeters!.toStringAsFixed(0)}m'
                    : '---',
                'distance',
                AppColors.textPrimary,
              ),
              Container(width: 1, height: 30, color: Colors.grey[300]),
              _indoorStat(
                (route.estimatedMinutes ?? 0) > 0
                    ? '${route.estimatedMinutes} min'
                    : '< 1 min',
                'walk',
                AppColors.accentGold,
              ),
              Container(width: 1, height: 30, color: Colors.grey[300]),
              _indoorStat(
                sameFloor
                    ? 'Floor ${route.originFloor ?? 1}'
                    : 'F${route.originFloor ?? 1}→F${route.destFloor ?? 1}',
                'floors',
                AppColors.infoBlue,
                fontSize: 16,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() => _indoorRoute = null);
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        MultiPhaseNavScreen(navigationRoute: route),
                  ),
                );
              },
              icon: const Icon(Icons.navigation,
                  color: AppColors.accentGold),
              label: const Text('Start Navigation',
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: () => setState(() => _indoorRoute = null),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryMaroon,
                side: const BorderSide(color: AppColors.primaryMaroon),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Clear Route'),
            ),
          ),
        ],
      ),
    );
  }

  Marker _placePin() {
    final place = _selectedPlace!;
    return Marker(
      point: LatLng(_selectedPlaceLat!, _selectedPlaceLng!),
      width: 40,
      height: 50,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryMaroon,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black38,
                    blurRadius: 6,
                    offset: Offset(0, 3)),
              ],
            ),
            child: Icon(place['icon'] as IconData,
                color: AppColors.accentGold, size: 18),
          ),
          Container(width: 2, height: 8, color: AppColors.primaryMaroon),
        ],
      ),
    );
  }

  void _onBuildingTap(BuildingModel b) {
    BuildingBottomSheet.show(
      context,
      b,
      onNavigate: () {
        // Open the route planner with this building pre-filled as the
        // destination; the user still picks the starting point.
        setState(() {
          _selectedTo = {
            'id': b.id.toString(),
            'name': b.name,
            'subtitle': 'Building',
            'type': 'building',
            'lat': b.lat,
            'lng': b.lng,
            'icon': Icons.business,
            'color': AppColors.primaryMaroon,
          };
        });
        _showRoutePlanner(keepTo: true);
      },
    );
  }

  void _fitRoute(List<LatLng> path) {
    if (path.length < 2) return;
    final bounds = LatLngBounds.fromPoints(path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(48, 120, 48, 340),
        ),
      );
    });
  }
}
