import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/utils/geofence_service.dart';
import '../../data/models/outdoor_node_model.dart';
import '../bloc/auth/auth_cubit.dart';
import '../screens/about/about_screen.dart';
import '../screens/ar/ar_screen.dart';
import '../screens/auth/account_status_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/role_selection_screen.dart';
import '../screens/auth/visitor_ended_screen.dart';
import '../screens/auth/visitor_screen.dart';
import '../screens/floor_plan/floor_plan_screen.dart';
import '../screens/geofence/location_permission_screen.dart';
import '../screens/geofence/location_service_screen.dart';
import '../screens/geofence/outside_campus_screen.dart';
import '../screens/main/main_screen.dart';
import '../screens/map/map_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/places/building_detail_screen.dart';
import '../screens/places/places_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/survey/survey_screen.dart';
import '../bloc/navigation/navigation_session_logger.dart';

/// Arguments passed to the turn-by-turn navigation screen.
class TurnByTurnArgs {
  final List<LatLng> path;
  final List<OutdoorNodeModel> nodes;
  final String destinationName;

  const TurnByTurnArgs({
    required this.path,
    required this.nodes,
    this.destinationName = 'your destination',
  });
}

class AppRouter {
  AppRouter._();

  static final _rootKey = GlobalKey<NavigatorState>();
  static final _shellKey = GlobalKey<NavigatorState>();

  /// A blocked account sees only `/account-status`, whatever it asks for.
  static String? blockedRedirect(AuthState state, String loc) {
    if (state is! AuthAccountBlocked) return null;
    return loc == '/account-status' ? null : '/account-status';
  }

  /// A visitor whose session is over sees only `/visitor-ended`, from the
  /// moment its time is up.
  static String? visitorEndedRedirect(AuthState state, String loc) {
    final ended = state is AuthVisitorEnded ||
        (state is AuthVisitor && !state.session.isStillValid);
    if (!ended) return null;
    return loc == visitorEndedRoute ? null : visitorEndedRoute;
  }

  /// The floor plan viewer is not for those who [canSeeIndoorMap] says no to.
  static String? indoorMapRedirect(AuthState state, String loc) =>
      loc.startsWith('/floor-plan') && !canSeeIndoorMap(state) ? '/map' : null;

  static const String visitorEndedRoute = '/visitor-ended';

  static GoRouter build(BuildContext context, {String initialLocation = '/'}) {
    final authCubit = context.read<AuthCubit>();

    return GoRouter(
      navigatorKey: _rootKey,
      initialLocation: initialLocation,
      refreshListenable: _CubitRefresh(authCubit.stream),
      redirect: (context, state) {
        final authState = authCubit.state;
        final loc = state.matchedLocation;

        const publicRoutes = {
          '/',
          '/onboarding',
          '/login',
          '/visitor',
          visitorEndedRoute,
        };

        final isAuthed = authState is AuthAuthenticated;
        final needsRole = authState is AuthNeedsRoleSelection;
        final isVisitor =
            authState is AuthVisitor && authState.session.isStillValid;

        // Splash decides where a cold start goes.
        if (loc == '/') return null;

        final ended = visitorEndedRedirect(authState, loc);
        if (ended != null) return ended;

        final blocked = blockedRedirect(authState, loc);
        if (blocked != null || authState is AuthAccountBlocked) return blocked;

        // Geofence gates are always reachable once past splash.
        if (loc == '/outside-campus' ||
            loc == '/location-permission' ||
            loc == '/location-service-off') {
          return null;
        }

        // Signed in with Google but no role yet → lock to /select-role.
        if (needsRole) {
          return loc == '/select-role' ? null : '/select-role';
        }
        if (!needsRole && loc == '/select-role' && !isAuthed) {
          return '/login';
        }

        if (!isAuthed && !isVisitor) {
          // Signed out — the next session must re-verify campus location.
          GeofenceService.campusVerified = false;
          return publicRoutes.contains(loc) ? null : '/login';
        }

        final noIndoorMap = indoorMapRedirect(authState, loc);
        if (noIndoorMap != null) return noIndoorMap;

        // '/main' is an alias for the map tab.
        if (loc == '/main') return '/map';

        // Signed in trying to view an auth screen → map.
        // '/visitor' is intentionally excluded — it shows the freshly
        // created session's countdown before the user taps "Continue".
        if (isAuthed &&
            (loc == '/login' ||
                loc == '/onboarding' ||
                loc == '/select-role' ||
                loc == '/account-status')) {
          return '/map';
        }
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (c, s) => const SplashScreen()),
        GoRoute(
            path: '/onboarding',
            builder: (c, s) => const OnboardingScreen()),
        GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
        GoRoute(path: '/visitor', builder: (c, s) => const VisitorScreen()),
        GoRoute(
          path: visitorEndedRoute,
          builder: (c, s) => const VisitorEndedScreen(),
        ),
        GoRoute(
          path: '/account-status',
          builder: (c, s) => const AccountStatusScreen(),
        ),
        GoRoute(
          path: '/select-role',
          builder: (c, s) => const RoleSelectionScreen(),
        ),
        GoRoute(path: '/main', redirect: (c, s) => '/map'),
        GoRoute(
          path: '/outside-campus',
          builder: (c, s) => const OutsideCampusScreen(),
        ),
        GoRoute(
          path: '/location-permission',
          builder: (c, s) => const LocationPermissionScreen(),
        ),
        GoRoute(
          path: '/location-service-off',
          builder: (c, s) => const LocationServiceScreen(),
        ),
        ShellRoute(
          navigatorKey: _shellKey,
          builder: (c, s, child) => MainScreen(child: child),
          routes: [
            GoRoute(
                path: '/map',
                pageBuilder: (c, s) =>
                    const NoTransitionPage(child: MapScreen())),
            GoRoute(
                path: '/ar',
                pageBuilder: (c, s) =>
                    const NoTransitionPage(child: ArScreen())),
            GoRoute(
                path: '/places',
                pageBuilder: (c, s) =>
                    const NoTransitionPage(child: PlacesScreen())),
            GoRoute(
                path: '/about',
                pageBuilder: (c, s) =>
                    const NoTransitionPage(child: AboutScreen())),
          ],
        ),
        GoRoute(
          path: '/building/:id',
          parentNavigatorKey: _rootKey,
          builder: (c, s) => BuildingDetailScreen(
            buildingId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
        GoRoute(
          path: '/floor-plan/:floorPlanId',
          parentNavigatorKey: _rootKey,
          builder: (c, s) => FloorPlanScreen(
            buildingId:
                int.tryParse(s.uri.queryParameters['buildingId'] ?? '') ?? 0,
            initialFloorPlanId: s.pathParameters['floorPlanId'],
          ),
        ),
        GoRoute(
          path: '/survey',
          parentNavigatorKey: _rootKey,
          builder: (c, s) => SurveyScreen(
              navigationSessionId:
                  NavigationSessionLogger.tripIdFromRouteExtra(s.extra)),
        ),
        GoRoute(
          path: '/profile',
          parentNavigatorKey: _rootKey,
          builder: (c, s) => const ProfileScreen(),
        ),
      ],
    );
  }
}

/// Bridges a Cubit [Stream] to [Listenable] for go_router refreshes.
class _CubitRefresh extends ChangeNotifier {
  late final StreamSubscription<dynamic> _sub;
  _CubitRefresh(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
