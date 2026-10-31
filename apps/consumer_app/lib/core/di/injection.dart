import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get_it/get_it.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

import 'package:dio/dio.dart';

import '../config/feature_flag_service.dart';
import '../geocoding/device_geocoding_adapter.dart';
import '../geocoding/geocoding_cache.dart';
import '../geocoding/geocoding_rate_limiter.dart';
import '../geocoding/geocoding_service.dart';
import '../location/device_location_service.dart';
import '../map/map_tile_provider.dart';
import '../notifications/fcm_service.dart';
import '../notifications/notification_repository.dart';
import '../notifications/notification_service.dart';
import '../network/api_client.dart' hide TokenStorage;
import '../network/websocket_client.dart';
import '../network/event_bus.dart';
import '../offline/offline_service.dart';
import '../router/app_router.dart';
import '../startup/startup_state.dart';
import '../../features/auth/data/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login_usecase.dart'
    show LoginUseCase;
import '../../features/auth/domain/usecases/register_usecase.dart'
    show RegisterUseCase;
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/bloc/legal_consent_bloc.dart';
import '../../features/nidus/data/repositories/chat_repository.dart';
import '../../features/nidus/data/repositories/pre_selfie_repository.dart';
import '../../features/nidus/data/repositories/phase2_money_repository.dart';
import '../../features/nidus/data/repositories/split_fare_repository.dart';
import '../../features/nidus/data/repositories/ride_repository.dart';
import '../../features/nidus/data/repositories/safety_repository.dart';
import '../../features/nidus/domain/usecases/request_ride_usecase.dart';
import '../../features/nidus/domain/usecases/get_ride_status_usecase.dart';
import '../../features/nidus/presentation/bloc/ride_bloc.dart';
import '../../features/haven/data/repositories/hotel_repository.dart';
import '../../features/haven/presentation/bloc/hotel_search_bloc.dart';
import '../../features/vorax/data/repositories/restaurant_repository.dart';
import '../../features/vorax/presentation/bloc/restaurant_bloc.dart';
import '../../features/profile/presentation/bloc/profile_bloc.dart'
    show ProfileBloc, ProfileRepository, UserProfile;
import '../../features/wallet/data/repositories/wallet_repository.dart';
import '../../features/wallet/presentation/bloc/wallet_bloc.dart';

// ============================================================================
// SERVICE LOCATOR
// ============================================================================

final GetIt getIt = GetIt.instance;

// ============================================================================
// INITIALIZATION
// ============================================================================

/// Startup-critical dependency registration. SYNCHRONOUS by contract (Phase 5:
/// "render first, initialize second"): every registration below is a lazy
/// singleton or factory closure — nothing is constructed and no I/O happens
/// until first resolution. The only awaited work left in the pre-runApp path
/// is Hive.initFlutter + opening the three boxes the first frame and session
/// hydration genuinely need ('auth', 'settings', 'cache').
///
/// Deliberately moved OFF the startup-critical path into the deferred Stage B
/// (see core/startup/app_startup_coordinator.dart):
///   - GeocodingCache.open()      -> registerGeocodingCache() after first frame
///   - FeatureFlagService.load()  -> registerFeatureFlags() after first frame
///   - OfflineService.initialize()-> coordinator step (opens its own boxes)
///   - Firebase/FCM bootstrap     -> coordinator step (permission prompts must
///                                    never gate the first frame)
/// Until those phases report `ready` on StartupStateNotifier, consumers render
/// honest provisional states (loading / cached / signed-out), never fabricated
/// live data.
void registerCoreDependencies(StartupStateNotifier startupState) {
  getIt.registerLazySingleton<StartupStateNotifier>(() => startupState);

  // 1. Core services (lazy — construction deferred to first use)
  _registerCoreServices();

  // 2. Network layer
  _registerNetworkLayer();

  // 3. Repositories
  _registerRepositories();

  // 4. Use cases
  _registerUseCases();

  // 5. BLoCs (factories - new instance per screen)
  _registerBlocs();

  // 6. Router
  _registerRouter();

  debugPrint('✅ Startup-critical dependencies registered (deferred init pending)');
}

/// Deferred initialization entry points that still need to happen before the
/// app is fully usable but MUST NOT block the first frame. Called by the
/// AppStartupCoordinator's Stage B. Kept as thin wrappers so external callers
/// (tests, integration harnesses) have one stable API.
Future<void> configureDeferredDependencies() async {
  final state = getIt<StartupStateNotifier>();
  await _initializeDeferred(state);
}

Future<void> _initializeDeferred(StartupStateNotifier state) async {
  // Geocoding cache (dedicated Hive box; cache-first reads afterwards).
  state.markRunning(StartupSubsystem.geocodingCache);
  try {
    final geocodingCache = await GeocodingCache.open();
    registerGeocodingCache(geocodingCache);
    state.markReady(StartupSubsystem.geocodingCache);
  } catch (e) {
    debugPrint('[startup] geocoding cache open failed: $e');
    state.markFailed(StartupSubsystem.geocodingCache);
    rethrow;
  }

  // Feature flags (bundled asset read; missing file => all flags disabled).
  state.markRunning(StartupSubsystem.featureFlags);
  try {
    final featureFlags = await FeatureFlagService.load();
    registerFeatureFlags(featureFlags);
    state.markReady(StartupSubsystem.featureFlags);
  } catch (e) {
    debugPrint('[startup] feature flag load failed: $e');
    state.markFailed(StartupSubsystem.featureFlags);
    rethrow;
  }
}

/// Late registration hooks used by the startup coordinator once a deferred
/// subsystem actually exists. Idempotent: a retry that re-opens the same box
/// or re-loads the same asset simply replaces the earlier instance.
void registerGeocodingCache(GeocodingCache cache) {
  if (getIt.isRegistered<GeocodingCache>()) {
    // Retry path: replacing an instance must not leave the old Hive box
    // attached; GeocodingCache holds no disposables beyond the shared box.
    getIt.unregister<GeocodingCache>();
  }
  getIt.registerLazySingleton<GeocodingCache>(() => cache);
}

void registerFeatureFlags(FeatureFlagService flags) {
  if (getIt.isRegistered<FeatureFlagService>()) {
    getIt.unregister<FeatureFlagService>();
  }
  getIt.registerLazySingleton<FeatureFlagService>(() => flags);
}

/// Firebase is initialized lazily and ONLY from the deferred push-bootstrap
/// step — the first frame never waits on it. Safe to call repeatedly.
Future<void> ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp();
}

/// Back-compatible full configuration for tests and tooling that do not care
/// about frame timing: registers everything and performs the deferred work
/// eagerly. Production main() uses registerCoreDependencies + the coordinator.
Future<void> configureDependencies() async {
  await Hive.initFlutter();
  await Hive.openBox('auth');
  await Hive.openBox('cache');
  await Hive.openBox('settings');
  registerCoreDependencies(StartupStateNotifier());
  await configureDeferredDependencies();
  debugPrint('✅ All dependencies configured successfully');
}

// ============================================================================
// CORE SERVICES
// ============================================================================

void _registerCoreServices() {
  // Connectivity
  getIt.registerLazySingleton<Connectivity>(() => Connectivity());

  // Geocoding substrate (§1.3): dedicated Dio instance (Nominatim/Photon are
  // external hosts — never reuse the authenticated API client), Hive-backed
  // cache, and the 1 rps Nominatim rate limiter. The service walks the
  // provider chain Nominatim -> Photon -> device -> cache.
  //
  // Phase 5: the GeocodingCache INSTANCE is registered by the deferred stage
  // (registerGeocodingCache). GeocodingService itself stays lazy and resolves
  // the cache at first use; search UI renders "cache warming" honestly until
  // then instead of blocking startup on an external provider.
  getIt.registerLazySingleton<Dio>(
    () => Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
  );
  getIt.registerLazySingleton<GeocodingRateLimiter>(
    () => GeocodingRateLimiter(requestsPerSecond: 1.0),
  );
  getIt.registerLazySingleton<GeocodingService>(
    () => GeocodingService(
      dio: getIt<Dio>(),
      cache: getIt<GeocodingCache>(),
      nominatimLimiter: getIt<GeocodingRateLimiter>(),
      deviceAutocomplete: DeviceGeocodingAdapter.autocomplete,
      deviceReverse: DeviceGeocodingAdapter.reverse,
    ),
  );

  // Device location substrate (§1.2): stateless wrapper over geolocator.
  getIt.registerLazySingleton<DeviceLocationService>(
    () => const DeviceLocationService(),
  );

  // Map tile substrate (§1.1): one shared provider per session so the
  // MapHealth stream and the Hive tile cache are global. LiveMapWidget
  // consumes this; production builds must swap the templates in
  // MapTileProvider.defaultChain for a licensed OSM mirror.
  getIt.registerLazySingleton<MapTileProvider>(
    () => MapTileProvider.defaultChain(),
  );

  // Feature flags (Global Rule 6): client-side view of the canonical
  // config/feature-flags/flags.json bundled as an app asset. A missing or
  // malformed file degrades every flag to disabled — never an accidental ON.
  // The router consults this for gated surfaces such as /nidus/ar-nav/:rideId.
  //
  // Phase 5: the actual load() moved to the deferred stage
  // (registerFeatureFlags). This lazy factory is a defensive fallback so any
  // early consumer still resolves a valid, all-disabled service instead of
  // throwing; the coordinator's registration replaces it once the real file
  // has been read.
  getIt.registerLazySingleton<FeatureFlagService>(
    () => FeatureFlagService.empty(),
  );

  // Event Bus (cross-feature communication)
  getIt.registerLazySingleton<EventBus>(() => EventBus());

  // Offline Service
  getIt.registerLazySingleton<OfflineService>(() => OfflineService());

  // Token Storage (using Hive)
  getIt.registerLazySingleton<TokenStorage>(() => HiveTokenStorage());
}

// ============================================================================
// NETWORK LAYER
// ============================================================================

void _registerNetworkLayer() {
  // API Client Configuration
  const apiConfig = ApiClientConfig(
    baseUrl: String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    ),
    connectTimeout: Duration(seconds: 15),
    receiveTimeout: Duration(seconds: 30),
    sendTimeout: Duration(seconds: 15),
    enableLogging: kDebugMode,
    maxRetries: 3,
  );

  // API Client (singleton - shared across app)
  getIt.registerLazySingleton<ApiClient>(
    () => ApiClient(
      config: apiConfig,
      tokenStorage: getIt<TokenStorage>(),
    ),
  );

  // WebSocket Client (singleton)
  getIt.registerLazySingleton<WebSocketClient>(
    () => WebSocketClient(
      baseUrl: String.fromEnvironment(
        'WS_BASE_URL',
        defaultValue: 'ws://localhost:8080/ws',
      ),
      tokenProvider: () => Hive.box('auth').get('access_token') as String?,
    ),
  );
}

// ============================================================================
// REPOSITORIES
// ============================================================================

void _registerRepositories() {
  // Auth Repository
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      apiClient: getIt<ApiClient>(),
      tokenStorage: getIt<TokenStorage>(),
    ),
  );

  // User/Profile Repository — thin adapter over ApiClient mapping the
  // auth/me payload onto the profile feature's UserProfile entity.
  getIt.registerLazySingleton<ProfileRepository>(
    () => ProfileRepositoryImpl(api: getIt<ApiClient>()),
  );

  // Ride Repository
  getIt.registerLazySingleton<RideRepository>(
    () => RideRepositoryImpl(
      apiClient: getIt<ApiClient>(),
      webSocketClient: getIt<WebSocketClient>(),
    ),
  );

  // Phase 2 money surface (§3.1 payment-method registry + cash confirm,
  // §3.2 promotions). Registered right after RideRepository so any widget
  // can resolve it via getIt without extra plumbing.
  getIt.registerLazySingleton<Phase2MoneyRepository>(
    () => Phase2MoneyRepository(apiClient: getIt<ApiClient>()),
  );

  // §3.3 Split fare surface (create invites, status, tokenized accept).
  getIt.registerLazySingleton<SplitFareRepository>(
    () => SplitFareRepository(apiClient: getIt<ApiClient>()),
  );

  // Safety Repository (SOS, trip sharing, trusted contacts)
  getIt.registerLazySingleton<SafetyRepository>(
    () => SafetyRepositoryImpl(
      apiClient: getIt<ApiClient>(),
      webSocketClient: getIt<WebSocketClient>(),
    ),
  );

  // Hotel Repository
  getIt.registerLazySingleton<HotelRepository>(
    () => HotelRepositoryImpl(apiClient: getIt<ApiClient>()),
  );

  // Restaurant Repository
  getIt.registerLazySingleton<RestaurantRepository>(
    () => RestaurantRepositoryImpl(apiClient: getIt<ApiClient>()),
  );

  // Wallet (Ledger) Repository — Phase H Step 1
  getIt.registerLazySingleton<WalletRepository>(
    () => WalletRepositoryImpl(apiClient: getIt<ApiClient>()),
  );

  // Notifications Repository (§1.4): /notifications/devices, /inbox, /:id/read
  getIt.registerLazySingleton<NotificationRepository>(
    () => NotificationRepository(api: getIt<ApiClient>()),
  );

  // Chat Repository (§2.1): /api/v1/chat REST + chat.ride.{rideId} WS topic.
  // Server-side kill switch FEATURE_CHAT makes these endpoints 404 when off;
  // the repository surfaces that as ChatUnavailableException and the UI shows
  // a real unavailable state with retry — never fake messages or canned text.
  getIt.registerLazySingleton<ChatRepository>(
    () => ChatRepository(
      api: getIt<ApiClient>(),
      ws: getIt<WebSocketClient>(),
    ),
  );

  // Pre-selfie repository (§2.3): driver upload + rider signed-URL redeem.
  // Server-side kill switch FEATURE_PRE_SELFIE makes these endpoints 404/503;
  // the repository maps that to typed exceptions so the UI shows a real
  // unavailable state with retry — never a placeholder photo or fake URL.
  getIt.registerLazySingleton<PreSelfieRepository>(
    () => PreSelfieRepositoryImpl(api: getIt<ApiClient>()),
  );
}

// ============================================================================
// USE CASES
// ============================================================================

void _registerUseCases() {
  // Auth
  getIt.registerFactory(() => LoginUseCase(getIt<AuthRepository>()));
  getIt.registerFactory(() => RegisterUseCase(getIt<AuthRepository>()));

  // Rides
  getIt.registerFactory(() => RequestRideUseCase(getIt<RideRepository>()));
  getIt.registerFactory(() => GetRideStatusUseCase(getIt<RideRepository>()));

  // Notifications substrate (§1.4). FcmService is a lazy singleton created
  // after Firebase.initializeApp() in main(); initialize() is idempotent and
  // safe to call from any first consumer. NotificationService merges the WS
  // topic, FCM foreground messages, and the HTTP inbox into one stream the
  // banner + bell badge subscribe to.
  getIt.registerLazySingleton<FcmService>(
    () => FcmService(repository: getIt<NotificationRepository>()),
  );
  getIt.registerLazySingleton<NotificationService>(
    () => NotificationService(
      repository: getIt<NotificationRepository>(),
      webSocket: getIt<WebSocketClient>(),
      fcm: getIt<FcmService>(),
    ),
  );
}

// ============================================================================
// BLOCS
// ============================================================================

void _registerBlocs() {
  // Auth BLoC (singleton - manages global auth state)
  getIt.registerLazySingleton<AuthBloc>(
    () => AuthBloc(
      loginUseCase: getIt<LoginUseCase>(),
      registerUseCase: getIt<RegisterUseCase>(),
      authRepository: getIt<AuthRepository>(),
      onAuthenticated: () => getIt<WebSocketClient>().connect(),
      onLogout: () => getIt<WebSocketClient>().disconnect(),
    ),
  );

  // Legal Consent BLoC (singleton - tracks consent across app)
  getIt.registerLazySingleton<LegalConsentBloc>(
    () => LegalConsentBloc(getIt<ApiClient>()),
  );

  // Ride BLoC (factory - new instance per ride screen)
  getIt.registerFactory<RideBloc>(
    () => RideBloc(
      rideRepository: getIt<RideRepository>(),
      requestRideUseCase: getIt<RequestRideUseCase>(),
      getRideStatusUseCase: getIt<GetRideStatusUseCase>(),
      safetyRepository: getIt<SafetyRepository>(),
      // §2.3 role detection: resolves the signed-in account id from the
      // global AuthBloc so the bloc can split DriverEnRoute into the
      // rider-side verification view vs. the driver-side capture flow.
      currentUserIdResolver: () => getIt<AuthBloc>().currentUser?.id,
      // §4.5: RideCheck anomaly detector is gated at runtime by the
      // `ridecheck_anomaly` flag (default off; kill switch documented in
      // config/feature-flags/flags.json). Injecting the loaded service lets
      // the bloc check it per position sample without reaching for getIt.
      featureFlags: getIt<FeatureFlagService>(),
    ),
  );

  // Hotel Search BLoC (factory)
  getIt.registerFactory<HotelSearchBloc>(
    () => HotelSearchBloc(hotelRepository: getIt<HotelRepository>()),
  );

  // Restaurant BLoC (factory)
  getIt.registerFactory<RestaurantBloc>(
    () => RestaurantBloc(restaurantRepository: getIt<RestaurantRepository>()),
  );

  // Profile BLoC (singleton - global user state)
  getIt.registerLazySingleton<ProfileBloc>(
    () => ProfileBloc(userRepository: getIt<ProfileRepository>()),
  );

  // Wallet BLoC (factory - new instance per wallet screen)
  getIt.registerFactory<WalletBloc>(
    () => WalletBloc(repository: getIt<WalletRepository>()),
  );
}

// ============================================================================
// ROUTER
// ============================================================================

void _registerRouter() {
  getIt.registerLazySingleton<AppRouter>(
    () => AppRouter(
      authBloc: getIt<AuthBloc>(),
      rideBlocFactory: getIt<RideBloc>,
      walletBlocFactory: getIt<WalletBloc>,
    ),
  );
}

// ============================================================================
// TOKEN STORAGE IMPLEMENTATION
// ============================================================================

/// Token storage using Hive (encrypted in production)
class HiveTokenStorage implements TokenStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  late final _authBox = Hive.box('auth');

  @override
  Future<String?> getAccessToken() async {
    return _authBox.get(_accessTokenKey) as String?;
  }

  @override
  Future<String?> getRefreshToken() async {
    return _authBox.get(_refreshTokenKey) as String?;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _authBox.put(_accessTokenKey, accessToken);
    await _authBox.put(_refreshTokenKey, refreshToken);
  }

  @override
  Future<void> clearTokens() async {
    await _authBox.delete(_accessTokenKey);
    await _authBox.delete(_refreshTokenKey);
  }
}

// ============================================================================
// CLEANUP
// ============================================================================

/// Reset all dependencies (useful for testing)
Future<void> resetDependencies() async {
  await getIt.reset();
}

/// Dispose singleton resources on app shutdown
Future<void> disposeDependencies() async {
  if (getIt.isRegistered<ApiClient>()) {
    getIt<ApiClient>().dispose();
  }
  if (getIt.isRegistered<WebSocketClient>()) {
    getIt<WebSocketClient>().dispose();
  }
  if (getIt.isRegistered<EventBus>()) {
    getIt<EventBus>().dispose();
  }
  if (getIt.isRegistered<OfflineService>()) {
    getIt<OfflineService>().dispose();
  }
  if (getIt.isRegistered<NotificationService>()) {
    await getIt<NotificationService>().dispose();
  }
}