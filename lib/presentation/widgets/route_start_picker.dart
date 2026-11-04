import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config/campus_bounds.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/building_model.dart';
import '../../data/models/outdoor_node_model.dart';
import '../../data/repositories/building_repository.dart';
import '../bloc/navigation/outdoor_nav_cubit.dart';

/// Returns the user's position, or null when it can't be had.
typedef LocateUser = Future<LatLng?> Function();


/// One GPS fix, or null when location services are off, permission is
/// refused, or no fix arrives in time. Never throws.
Future<LatLng?> currentUserLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return LatLng(p.latitude, p.longitude);
  } catch (e) {
    debugPrint('📍 Route start: no GPS fix ($e)');
    return null;
  }
}

const String noLocationReason = "We couldn't get your location.";
const String offCampusReason = "You don't seem to be on campus right now.";

/// Marks the route planner's GPS start. Typed as a building with no id, like
/// any other start that isn't in a known building.
const String myLocationKey = 'my_location';

bool isMyLocation(Map<String, dynamic>? place) =>
    place?[myLocationKey] == true;

/// The "My location" row of the route planner, before GPS is asked.
const Map<String, dynamic> myLocationPlace = {
  myLocationKey: true,
  'type': 'building',
  'name': 'My location',
  'subtitle': 'Start from where you are now',
  'icon': Icons.my_location,
  'color': AppColors.infoBlue,
};

/// The path node nearest the user, or the reason there is none.
Future<({OutdoorNodeModel? node, String? problem})> locateStartNode(
  OutdoorNavCubit nav, {
  LocateUser locate = currentUserLocation,
}) async {
  if (!await nav.ensureGraph()) {
    return (node: null, problem: nav.state.error);
  }
  final here = await locate();
  if (here == null) return (node: null, problem: noLocationReason);
  final id = nav.nearestNodeIdWithin(here, maxOnCampusGpsMeters);
  if (id == null) return (node: null, problem: offCampusReason);
  return (node: nav.repo.nodes.firstWhere((n) => n.id == id), problem: null);
}

/// Starts a route to [destination] from the user's GPS position (nearest
/// path node). Without a usable fix it asks the user to pick the building
/// they are starting from. Returns false when the user cancelled — no
/// route was requested.
Future<bool> startRouteToBuilding(
  BuildContext context,
  BuildingModel destination, {
  LocateUser locate = currentUserLocation,
}) async {
  final nav = context.read<OutdoorNavCubit>();
  final buildings = context.read<BuildingRepository>();
  if (!await nav.ensureGraph()) return true; // the error is in nav.state

  final here = await locate();
  final gpsNode =
      here == null ? null : nav.nearestNodeIdWithin(here, maxOnCampusGpsMeters);
  if (gpsNode != null) {
    await nav.routeToBuilding(destination,
        fromNodeId: gpsNode, fromLabel: 'Your location');
    return true;
  }

  if (!context.mounted) return false;
  final start = await showModalBottomSheet<BuildingModel>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _StartPointSheet(
      destination: destination,
      buildings: buildings,
      reason: here == null ? noLocationReason : offCampusReason,
    ),
  );
  if (start == null) return false;

  final startNode =
      nav.startNodeForBuilding(start, towards: destination.location);
  await nav.routeToBuilding(destination,
      fromNodeId: startNode, fromLabel: start.label);
  return true;
}

class _StartPointSheet extends StatefulWidget {
  final BuildingModel destination;
  final BuildingRepository buildings;
  final String reason;

  const _StartPointSheet({
    required this.destination,
    required this.buildings,
    required this.reason,
  });

  @override
  State<_StartPointSheet> createState() => _StartPointSheetState();
}

class _StartPointSheetState extends State<_StartPointSheet> {
  late Future<List<BuildingModel>> _load = widget.buildings.getBuildings();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Where are you starting from?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${widget.reason} Pick the building you are at or nearest to.',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<BuildingModel>>(
                future: _load,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primaryMaroon));
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Could not load the building list.'),
                          TextButton(
                            onPressed: () => setState(() =>
                                _load = widget.buildings.getBuildings()),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  final list = snap.data!
                      .where((b) => b.id != widget.destination.id)
                      .toList();
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.location_city,
                          color: AppColors.primaryMaroon),
                      title: Text(list[i].label),
                      onTap: () => Navigator.pop(context, list[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
