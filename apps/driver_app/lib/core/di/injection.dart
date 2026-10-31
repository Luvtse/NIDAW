import 'package:flutter_bloc/flutter_bloc.dart' show Bloc;
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../network/api_client.dart';
import '../network/websocket_client.dart';
import '../network/location_service.dart';
import '../router/app_router.dart';
import '../startup/driver_startup_state.dart';

import '../../features/auth/data/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/auth/domain/usecases/register_usecase.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';

import '../../features/home/data/repositories/driver_home_repository.dart';
import '../../features/home/domain/usecases/get_driver_stats_usecase.dart';
import '../../features/home/domain/usecases/toggle_availability_usecase.dart';
import '../../features/home/presentation/bloc/driver_home_bloc.dart';

import '../../features/ride/data/repositories/ride_repository.dart';
import '../../features/ride/domain/usecases/accept_ride_usecase.dart';
import '../../features/ride/domain/usecases/start_ride_usecase.dart';
import '../../features/ride/domain/usecases/complete_ride_usecase.dart';
import '../../features/ride/domain/usecases/get_active_ride_usecase.dart';
import '../../features/ride/presentation/bloc/active_ride_bloc.dart';

import '../../features/earnings/data/repositories/earnings_repository.dart';
import '../../features/earnings/domain/usecases/get_daily_earnings_usecase.dart';
import '../../features/earnings/domain/usecases/get_weekly_earnings_usecase.dart';
import '../../features/earnings/presentation/bloc/earnings_bloc.dart';

import '../../features/profile/data/repositories/driver_profile_repository.dart';
import '../../features/documents/data/repositories/document_repository.dart';
import '../../features/profile/presentation/bloc/driver_profile_bloc.dart';

final getIt = GetIt.instance;

/// ============================================================================
/// DRIVER DI (Phase 5, §4.3 / §5.3)
/// ============================================================================
///
/// [registerCoreDependencies] is the STARTUP-CRITICAL registration: purely
/// synchronous closure wiring — nothing is constructed and no I/O happens
/// until first resolution. Lazy singletons for earnings / profile / documents
/// therefore cost zero on the cold path: their repositories only construct
/// when those screens are first opened (§4.3 "initialize ... lazily when
/// first accessed").
///
/// The startup coordinator's Stage A additionally opens ONLY 'driver_auth'
/// before runApp; 'driver_cache'/'driver_settings' open in Stage B. Repos
/// that read those boxes already `await Hive.openBox(...)` defensively, so
/// deferred opening is safe.
void registerCoreDependencies(DriverStartupStateNotifier startupState) {
  getIt.registerLazySingleton<DriverStartupStateNotifier>(
      () => startupState);

  // Network
  getIt.registerLazySingleton<ApiClient>(
    () => ApiClient(baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    )),
  );

  getIt.registerLazySingleton<WebSocketClient>(
    () => WebSocketClient(baseUrl: const String.fromEnvironment(
      'WS_BASE_URL',
      defaultValue: 'ws://localhost:8080/ws',
    )),
  );

  getIt.registerLazySingleton<LocationService>(
    () => LocationService(
      onLocationUpdate: (lat, lng, heading, speed) =>
          getIt<DriverHomeRepository>().updateLocation(lat, lng, heading, speed),
    ),
  );

  // Repositories
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(apiClient: getIt<ApiClient>()),
  );

  getIt.registerLazySingleton<DriverHomeRepository>(
    () => DriverHomeRepositoryImpl(
      apiClient: getIt<ApiClient>(),
      webSocketClient: getIt<WebSocketClient>(),
    ),
  );

  getIt.registerLazySingleton<RideRepository>(
    () => RideRepositoryImpl(
      apiClient: getIt<ApiClient>(),
      webSocketClient: getIt<WebSocketClient>(),
    ),
  );

  // Secondary money/profile surfaces: lazy — constructed on first screen
  // access, never during startup.
  getIt.registerLazySingleton<EarningsRepository>(
    () => EarningsRepositoryImpl(apiClient: getIt<ApiClient>()),
  );

  getIt.registerLazySingleton<DriverProfileRepository>(
    () => DriverProfileRepositoryImpl(apiClient: getIt<ApiClient>()),
  );

  getIt.registerLazySingleton<DocumentRepository>(
    () => DocumentRepositoryImpl(apiClient: getIt<ApiClient>()),
  );

  // Use Cases
  getIt.registerFactory(() => LoginUseCase(getIt<AuthRepository>()));
  getIt.registerFactory(() => RegisterUseCase(getIt<AuthRepository>()));

  getIt.registerFactory(() => GetDriverStatsUseCase(getIt<DriverHomeRepository>()));
  getIt.registerFactory(() => ToggleAvailabilityUseCase(getIt<DriverHomeRepository>()));

  getIt.registerFactory(() => AcceptRideUseCase(getIt<RideRepository>()));
  getIt.registerFactory(() => StartRideUseCase(getIt<RideRepository>()));
  getIt.registerFactory(() => CompleteRideUseCase(getIt<RideRepository>()));
  getIt.registerFactory(() => GetActiveRideUseCase(getIt<RideRepository>()));

  getIt.registerFactory(() => GetDailyEarningsUseCase(getIt<EarningsRepository>()));
  getIt.registerFactory(() => GetWeeklyEarningsUseCase(getIt<EarningsRepository>()));

  // BLoCs
  getIt.registerFactory(() => AuthBloc(
    loginUseCase: getIt<LoginUseCase>(),
    registerUseCase: getIt<RegisterUseCase>(),
    authRepository: getIt<AuthRepository>(),
    webSocketClient: getIt<WebSocketClient>(),
  ));

  getIt.registerFactory(() => DriverHomeBloc(
    getDriverStatsUseCase: getIt<GetDriverStatsUseCase>(),
    driverHomeRepository: getIt<DriverHomeRepository>(),
    toggleAvailabilityUseCase: getIt<ToggleAvailabilityUseCase>(),
    locationService: getIt<LocationService>(),
  ));

  getIt.registerFactory(() => ActiveRideBloc(
    acceptRideUseCase: getIt<AcceptRideUseCase>(),
    startRideUseCase: getIt<StartRideUseCase>(),
    completeRideUseCase: getIt<CompleteRideUseCase>(),
    locationService: getIt<LocationService>(),
    getActiveRideUseCase: getIt<GetActiveRideUseCase>(),
    rideRepository: getIt<RideRepository>(),
  ));

  getIt.registerFactory(() => EarningsBloc(
    getDailyEarningsUseCase: getIt<GetDailyEarningsUseCase>(),
    getWeeklyEarningsUseCase: getIt<GetWeeklyEarningsUseCase>(),
  ));

  getIt.registerFactory(() => DriverProfileBloc(
    profileRepository: getIt<DriverProfileRepository>(),
  ));

  // Router
  getIt.registerLazySingleton(() => AppRouter(authBloc: getIt<AuthBloc>()));
}

/// Back-compatible full configuration for tests and tooling that do not care
/// about frame timing: opens every box and registers everything eagerly.
/// Production main() uses registerCoreDependencies + the startup coordinator.
Future<void> configureDependencies() async {
  await Hive.initFlutter();
  await Hive.openBox('driver_auth');
  await Hive.openBox('driver_cache');
  await Hive.openBox('driver_settings');
  registerCoreDependencies(DriverStartupStateNotifier());
}
