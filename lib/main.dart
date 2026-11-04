import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/required_keys.dart';
import 'core/config/supabase_config.dart';
import 'core/network/connectivity_service.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/screen_capture.dart';
import 'data/offline_sync.dart';
import 'data/repositories/about_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/building_repository.dart';
import 'data/repositories/facility_repository.dart';
import 'data/repositories/feedback_repository.dart';
import 'data/repositories/floor_plan_repository.dart';
import 'data/repositories/indoor_navigation_repository.dart';
import 'data/repositories/outdoor_ar_repository.dart';
import 'data/repositories/outdoor_navigation_repository.dart';
import 'data/repositories/room_repository.dart';
import 'data/repositories/survey_repository.dart';
import 'presentation/bloc/auth/auth_cubit.dart';
import 'presentation/bloc/building/building_cubit.dart';
import 'presentation/bloc/navigation/indoor_nav_cubit.dart';
import 'presentation/bloc/navigation/outdoor_nav_cubit.dart';
import 'presentation/bloc/search/search_cubit.dart';
import 'presentation/routes/app_router.dart';
import 'presentation/screens/setup/setup_required_screen.dart';
import 'presentation/widgets/account_access_watcher.dart';
import 'presentation/widgets/offline_banner.dart';
import 'presentation/widgets/visitor_expiry_watcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ScreenCapture.apply();

  final missing = missingKeys();
  if (missing.isNotEmpty) {
    runApp(SetupRequiredApp(missing: missing));
    return;
  }

  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // ignore: deprecated_member_use
      anonKey: SupabaseConfig.anonKey,
    );
    // Session persistence is kept: the splash screen enforces the 8-hour
    // login window and signs out if it has elapsed.
  } catch (e) {
    debugPrint('Supabase init failed: $e');
  }

  // One shared instance of each data repository, so the background offline
  // sync refreshes the same in-memory copies the screens read.
  OfflineSync? sync;
  try {
    sync = OfflineSync(
      buildings: BuildingRepository(),
      rooms: RoomRepository(),
      facilities: FacilityRepository(),
      floorPlans: FloorPlanRepository(),
      indoor: IndoorNavigationRepository(),
      outdoor: OutdoorNavigationRepository(),
      outdoorAr: OutdoorArRepository(),
      about: AboutRepository(),
      survey: SurveyRepository(),
    )..start();
  } catch (e) {
    debugPrint('Offline sync not started: $e');
  }

  runApp(UmArNavApp(sync: sync));
}

class UmArNavApp extends StatelessWidget {
  /// Null only if Supabase failed to initialise.
  final OfflineSync? sync;

  const UmArNavApp({super.key, this.sync});

  @override
  Widget build(BuildContext context) {
    final s = sync;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => AuthRepository()),
        RepositoryProvider(create: (_) => s?.buildings ?? BuildingRepository()),
        RepositoryProvider(create: (_) => s?.rooms ?? RoomRepository()),
        RepositoryProvider(
            create: (_) => s?.facilities ?? FacilityRepository()),
        RepositoryProvider(
            create: (_) => s?.floorPlans ?? FloorPlanRepository()),
        RepositoryProvider(
            create: (_) => s?.outdoor ?? OutdoorNavigationRepository()),
        RepositoryProvider(
            create: (_) => s?.outdoorAr ?? OutdoorArRepository()),
        RepositoryProvider(
            create: (_) => s?.indoor ?? IndoorNavigationRepository()),
        RepositoryProvider(create: (_) => s?.survey ?? SurveyRepository()),
        RepositoryProvider(create: (_) => FeedbackRepository()),
        RepositoryProvider(create: (_) => s?.about ?? AboutRepository()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) => AuthCubit(ctx.read<AuthRepository>()),
          ),
          BlocProvider(
            create: (ctx) => BuildingCubit(
              ctx.read<BuildingRepository>(),
              ctx.read<RoomRepository>(),
              ctx.read<FacilityRepository>(),
            ),
          ),
          BlocProvider(
            create: (ctx) =>
                OutdoorNavCubit(ctx.read<OutdoorNavigationRepository>()),
          ),
          BlocProvider(
            create: (ctx) =>
                IndoorNavCubit(ctx.read<IndoorNavigationRepository>()),
          ),
          BlocProvider(
            create: (ctx) => SearchCubit(
              ctx.read<BuildingRepository>(),
              ctx.read<RoomRepository>(),
              ctx.read<IndoorNavigationRepository>(),
              ctx.read<FacilityRepository>(),
            ),
          ),
        ],
        child: Builder(
          builder: (context) {
            final router = AppRouter.build(context);
            return MaterialApp.router(
              title: 'UM-AR Nav',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              routerConfig: router,
              builder: (context, child) => AccountAccessWatcher(
                child: VisitorExpiryWatcher(
                  child: OfflineBanner(
                    connectivity: ConnectivityService.instance,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
