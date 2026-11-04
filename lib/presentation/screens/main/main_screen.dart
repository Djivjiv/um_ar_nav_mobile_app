import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/geofence_service.dart';
import '../../../core/utils/indoor_route_helpers.dart';
import '../../../data/models/indoor_node_model.dart';
import '../../bloc/auth/auth_cubit.dart';
import '../../bloc/search/search_cubit.dart';
import '../../widgets/search_bar_widget.dart';

class _Tab {
  final String route;
  final IconData icon;
  final String label;
  const _Tab(this.route, this.icon, this.label);
}

const _tabs = [
  _Tab('/map', Icons.map, 'Map'),
  _Tab('/ar', Icons.view_in_ar, 'AR'),
  _Tab('/places', Icons.business, 'Places'),
  _Tab('/about', Icons.info_outline, 'About'),
];

class MainScreen extends StatefulWidget {
  final Widget child;
  const MainScreen({super.key, required this.child});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Timer? _visitorTimer;
  bool _showVisitorWarning = false;
  int _visitorRemainingMinutes = 0;

  int _indexFor(String location) {
    final i = _tabs.indexWhere((t) => location.startsWith(t.route));
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _visitorTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkVisitorSessionWarning(),
    );
    // Run one check shortly after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisitorSessionWarning();
      _verifyCampus();
    });
  }

  /// Catch-all campus gate: whatever path reached the map (splash, an
  /// in-session sign-in that the router redirected here, a deep link),
  /// verify the user is on campus unless it was already confirmed this run.
  Future<void> _verifyCampus() async {
    if (!mounted) return;
    if (AppConfig.skipGeofenceCheck || GeofenceService.campusVerified) return;
    final inside = await GeofenceService.currentlyInsideCampus();
    if (!mounted) return;
    if (inside == false) {
      context.go('/outside-campus');
    } else if (inside == true) {
      GeofenceService.campusVerified = true;
    }
  }

  @override
  void dispose() {
    _visitorTimer?.cancel();
    super.dispose();
  }

  /// The last-15-minutes banner. The end of the session itself is handled by
  /// `VisitorExpiryWatcher` and the router.
  void _checkVisitorSessionWarning() {
    if (!mounted) return;
    final state = context.read<AuthCubit>().state;
    if (state is! AuthVisitor) return;

    final minutes = state.session.remaining.inMinutes;
    if (minutes <= 15) {
      setState(() {
        _showVisitorWarning = true;
        _visitorRemainingMinutes = minutes;
      });
    } else if (_showVisitorWarning) {
      setState(() => _showVisitorWarning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexFor(location);
    final onMap = index == 0;

    final authState = context.watch<AuthCubit>().state;
    final initial = authState is AuthAuthenticated
        ? (authState.user.displayName.isNotEmpty
            ? authState.user.displayName[0]
            : 'U')
        : 'V';

    return Scaffold(
      bottomNavigationBar: _BottomNavBar(
        currentIndex: index,
        onTap: (i) => context.go(_tabs[i].route),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (onMap)
            Align(
              alignment: Alignment.topCenter,
              child: FloatingSearchBar(
                avatarInitial: initial,
                onTapSearch: () => _openSearch(context),
                onTapProfile: () => context.push('/profile'),
              ),
            ),
          if (_showVisitorWarning)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  color: AppColors.primaryMaroon,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.timer,
                          color: AppColors.accentGold, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Session expires in $_visitorRemainingMinutes min. '
                          'Login for full access.',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Login',
                            style: TextStyle(
                                color: AppColors.accentGold,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openSearch(BuildContext context) {
    showSearch(
      context: context,
      delegate: AppSearchDelegate(context.read<SearchCubit>()),
    );
  }
}

/// Standard bottom navigation bar fixed to the bottom of the screen
/// (via [Scaffold.bottomNavigationBar], not a floating overlay).
class _BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNavBar({required this.currentIndex, required this.onTap});

  static const _icons = [
    [Icons.map_outlined, Icons.map],
    [Icons.view_in_ar_outlined, Icons.view_in_ar],
    [Icons.business_outlined, Icons.business],
    [Icons.info_outline, Icons.info],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryMaroon,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_tabs.length, (i) {
              return _navItem(
                _icons[i][0],
                _icons[i][1],
                _tabs[i].label,
                i,
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _navItem(
      IconData outline, IconData filled, String label, int index) {
    final isActive = currentIndex == index;
    final color =
        isActive ? AppColors.accentGold : Colors.white.withValues(alpha: 0.7);
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isActive ? filled : outline, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Unified search overlay backed by [SearchCubit], reachable from the
/// floating search bar. Routes to building detail / floor plan on tap.
class AppSearchDelegate extends SearchDelegate<void> {
  final SearchCubit cubit;
  AppSearchDelegate(this.cubit) : super(searchFieldLabel: 'Search buildings, rooms...');

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              query = '';
              cubit.clear();
            },
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  /// Hand the tapped result to the map (which pins it + shows a sheet)
  /// instead of navigating to a detail page.
  void _pick(BuildContext context, Map<String, dynamic> place) {
    cubit.pickPlace(place);
    close(context, null);
  }

  /// Place map for an indoor-node result: the node's real floor, and its
  /// type / id from `linked_table` (room ids and facility ids can collide).
  /// `indoor_node_id` lets indoor routing target this exact node.
  Map<String, dynamic> _indoorNodePlace(IndoorNodeModel n) {
    final dest = indoorNodeDestination(n);
    final isRoom = dest.type == 'room';
    return {
      'type': dest.type,
      'id': dest.id,
      'indoor_node_id': n.id,
      'name': n.displayLabel,
      'subtitle': n.floor != null
          ? 'Indoor location — Floor ${n.floor}'
          : 'Indoor location',
      'building_id': n.buildingId,
      'floor': n.floor,
      'icon': isRoom
          ? Icons.door_front_door_outlined
          : Icons.meeting_room_outlined,
      'color': isRoom ? AppColors.infoBlue : AppColors.accentGold,
    };
  }

  @override
  Widget buildResults(BuildContext context) => _body(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    // Defer so we don't emit into the cubit during this build pass.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => cubit.queryChanged(query));
    return _body(context);
  }

  Widget _body(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: BlocBuilder<SearchCubit, SearchState>(
        builder: (context, state) {
          if (query.trim().isEmpty) {
            return const Center(
              child: Text('Type to search buildings, rooms and facilities',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          if (state.status == SearchStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == SearchStatus.error) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off,
                      size: 56, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  const Text(SearchCubit.failedMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: cubit.retry, child: const Text('Retry')),
                ],
              ),
            );
          }
          if (state.isEmpty) {
            return const Center(
              child: Text('No matches found',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView(
            children: [
              if (state.notice != null)
                ListTile(
                  leading: const Icon(Icons.warning_amber_rounded,
                      color: AppColors.accentGold),
                  title: Text(state.notice!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ),
              for (final b in state.buildings)
                ListTile(
                  leading: const Icon(Icons.location_city,
                      color: AppColors.primaryMaroon),
                  title: Text(b.label),
                  subtitle: const Text('Building'),
                  onTap: () => _pick(context, {
                    'type': 'building',
                    'id': b.id.toString(),
                    'name': b.label,
                    'subtitle': 'Building',
                    'lat': b.lat,
                    'lng': b.lng,
                    'icon': Icons.business,
                    'color': AppColors.primaryMaroon,
                  }),
                ),
              for (final r in state.rooms)
                ListTile(
                  leading: const Icon(Icons.meeting_room_outlined,
                      color: AppColors.accentGold),
                  title: Text(r.label),
                  subtitle: Text(
                      'Room${r.floor != null ? ' · Floor ${r.floor}' : ''}'),
                  onTap: () => _pick(context, {
                    'type': 'room',
                    'id': r.id.toString(),
                    'name': r.label,
                    'subtitle':
                        'Room — Floor ${r.floor ?? 1}',
                    'building_id': r.buildingId,
                    'floor': r.floor,
                    'icon': Icons.door_front_door_outlined,
                    'color': AppColors.infoBlue,
                  }),
                ),
              for (final n in state.indoorNodes)
                ListTile(
                  leading: const Icon(Icons.place_outlined,
                      color: AppColors.infoBlue),
                  title: Text(n.displayLabel),
                  subtitle: Text('Indoor location'
                      '${n.floor != null ? ' · Floor ${n.floor}' : ''}'),
                  onTap: () => _pick(context, _indoorNodePlace(n)),
                ),
            ],
          );
        },
      ),
    );
  }
}
