import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/about_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/building_repository.dart';
import 'data/repositories/facility_repository.dart';
import 'data/repositories/floor_plan_repository.dart';
import 'data/repositories/indoor_navigation_repository.dart';
import 'data/repositories/outdoor_navigation_repository.dart';
import 'data/repositories/room_repository.dart';
import 'data/repositories/survey_repository.dart';
import 'presentation/bloc/auth/auth_cubit.dart';
import 'presentation/bloc/building/building_cubit.dart';
import 'presentation/bloc/navigation/indoor_nav_cubit.dart';
import 'presentation/bloc/navigation/outdoor_nav_cubit.dart';
import 'presentation/bloc/search/search_cubit.dart';
import 'presentation/routes/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const UmArNavApp());
}

class UmArNavApp extends StatelessWidget {
  const UmArNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => AuthRepository()),
        RepositoryProvider(create: (_) => BuildingRepository()),
        RepositoryProvider(create: (_) => RoomRepository()),
        RepositoryProvider(create: (_) => FacilityRepository()),
        RepositoryProvider(create: (_) => FloorPlanRepository()),
        RepositoryProvider(create: (_) => OutdoorNavigationRepository()),
        RepositoryProvider(create: (_) => IndoorNavigationRepository()),
        RepositoryProvider(create: (_) => SurveyRepository()),
        RepositoryProvider(create: (_) => AboutRepository()),
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
            );
          },
        ),
      ),
    );
  }
}
