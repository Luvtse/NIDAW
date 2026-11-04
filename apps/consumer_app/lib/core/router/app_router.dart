import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../di/injection.dart' show getIt;
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/bloc/onboarding_bloc.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/presentation/pages/onboarding_consent_page.dart';
import '../../features/auth/presentation/pages/legal_consent_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/nidus/presentation/bloc/ride_bloc.dart';
import '../../features/nidus/presentation/pages/ride_request_page.dart';
import '../../features/nidus/presentation/pages/ride_tracking_page.dart';
import '../../features/nidus/presentation/pages/ride_history_page.dart';
import '../../features/nidus/presentation/pages/notification_inbox_page.dart';
import '../../features/nidus/presentation/pages/safety_toolkit_page.dart';
import '../../features/nidus/presentation/widgets/in_app_notification_banner.dart';
import '../notifications/fcm_service.dart';
import '../notifications/notification_router.dart';
import '../notifications/notification_service.dart';
import '../../features/haven/presentation/pages/hotel_search_page.dart';
import '../../features/haven/presentation/bloc/hotel_search_bloc.dart';
import '../../features/haven/presentation/pages/hotel_detail_page.dart';
import '../../features/haven/presentation/pages/booking_page.dart';
import '../../features/vorax/presentation/pages/restaurant_list_page.dart';
import '../../features/vorax/presentation/bloc/restaurant_bloc.dart';
import '../../features/vorax/presentation/pages/menu_page.dart';
import '../../features/vorax/presentation/pages/order_tracking_page.dart';
import '../../features/vorax/presentation/pages/order_history_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile/presentation/pages/settings_page.dart';
import '../../features/profile/presentation/pages/consent_management_page.dart';
import '../../features/security/domain/services/biometric_security_service.dart';
import '../../features/security/presentation/pages/biometric_unlock_page.dart';
import '../../features/wallet/presentation/bloc/wallet_bloc.dart';
import '../../features/wallet/presentation/pages/wallet_page.dart';
import '../../features/nidus/presentation/pages/ar_navigation_page.dart';
import '../../features/nidus/data/repositories/ride_repository.dart'
    show Ride, RideRepository;
import '../../features/nidus/presentation/pages/chat_page.dart';
import '../../features/nidus/presentation/pages/receipt_detail_page.dart';

import '../../l10n/l10n.dart';
import '../flags/ar_navigation_gate.dart';
import '../startup/app_startup_coordinator.dart' show hasStartupCoordinator;

/// Phase 6 (nav consistency): the AR gate + per-install rollout id now live
/// in core/flags/ar_navigation_gate.dart as the single source of truth,
/// shared by this router's redirect and the tracking page's entry button.
/// (Previously both files carried hand-copied copies of this logic — the
/// router had its own `_resolveInstallId` private helper, which is gone.)

// ============================================================================
// ROUTE NAMES (for type-safe navigation)
// ============================================================================

class RouteNames {
  static const String home = 'home';
  static const String login = 'login';
  static const String register = 'register';
  static const String onboarding = 'onboarding';
  static const String rideRequest = 'rideRequest';
  static const String rideTracking = 'rideTracking';
  static const String rideArNavigation = 'rideArNavigation';
  static const String rideHistory = 'rideHistory';
  static const String safetyToolkit = 'safetyToolkit';
  // Phase 6 (nav consistency): chat & receipt were long pushed as raw
  // MaterialPageRoutes from tracking — invisible to deep links, flag gates
  // and web URL sync. They are first-class GoRouter routes now; these names
  // must stay byte-identical to ChatPage.routeName ('nidusChat').
  static const String rideChat = 'nidusChat';
  static const String rideReceipt = 'nidusReceipt';
  static const String hotelSearch = 'hotelSearch';
  static const String hotelDetail = 'hotelDetail';
  static const String booking = 'booking';
  static const String restaurantList = 'restaurantList';
  static const String menu = 'menu';
  static const String orderTracking = 'orderTracking';
  static const String orderHistory = 'orderHistory';
  static const String profile = 'profile';
  static const String settings = 'settings';
  static const String consentManagement = 'consentManagement';
  static const String biometricUnlock = 'biometricUnlock';
  static const String legalDocument = 'legalDocument';
  static const String wallet = 'wallet';
  static const String notificationInbox = 'notificationInbox';
}

// ============================================================================
// APP ROUTER
// ============================================================================

class AppRouter {
  final AuthBloc _authBloc;
  final RideBloc Function() _rideBlocFactory;
  final WalletBloc Function() _walletBlocFactory;

  late final GoRouter _router;

  AppRouter({
    required AuthBloc authBloc,
    required RideBloc Function() rideBlocFactory,
    required WalletBloc Function() walletBlocFactory,
  })  : _authBloc = authBloc,
        _rideBlocFactory = rideBlocFactory,
        _walletBlocFactory = walletBlocFactory {
    _router = GoRouter(
      initialLocation: '/splash',
      debugLogDiagnostics: true,
      // Re-evaluate routes on auth state change. With bloc ^8.1.x the Bloc
      // itself is not a Listenable; the bloc's dedicated authNotifier
      // (ValueNotifier<AuthState>) is the supported refresh signal.
      refreshListenable: _authBloc.authNotifier,
      redirect: _globalRedirect,
      routes: _buildRoutes(),
      errorBuilder: (context, state) => _ErrorPage(error: state.error),
    );
  }

  GoRouter get router => _router;

  // ============================================================================
  // GLOBAL REDIRECT (Auth Guard)
  // ============================================================================

  /// Path segment of the local biometric unlock screen (see _buildRoutes).
  static const String _biometricUnlockPathSegment = 'security/biometric-unlock';

  bool _biometricGatePending() {
    try {
      final service = getIt<BiometricSecurityService>();
      if (!service.isEnabled()) return false;
      final accountId = _authBloc.currentUser?.id;
      if (accountId == null) return false;
      final box = Hive.box('settings');
      final capabilityOk = box.get('biometric_capability_ok') == true;
      if (!capabilityOk) return false;
      return box.get(BiometricSecurityService.settingsBoxKey)?['owner_id'] ==
          accountId;
    } catch (_) {
      // Never brick navigation on a local-security read error.
      return false;
    }
  }

  String? _globalRedirect(BuildContext context, GoRouterState state) {
    final authState = _authBloc.state;
    final isAuthenticated = authState is AuthAuthenticated;
    final isOnboardingComplete = authState is AuthAuthenticated && 
                                  authState.onboardingComplete;

    final isAuthRoute = state.matchedLocation == '/login' ||
                       state.matchedLocation == '/register' ||
                       state.matchedLocation == '/splash';

    // Phase 6 (native biometric security): when the rider enabled the local
    // biometric gate on this device and a persisted session exists, cold
    // starts land on the unlock screen instead of hydrating straight into
    // the app. This is a LOCAL application gate only — tokens stay untouched
    // and every backend operation still requires server-side authorization.
    // Fail-open by construction: an unreadable preference or a device that
    // lost its enrollment simply resumes the normal flow rather than
    // locking anyone out of their own account.
    if (isAuthenticated &&
        state.matchedLocation != '/${_biometricUnlockPathSegment}') {
      try {
        final service = getIt<BiometricSecurityService>();
        final accountId = _authBloc.currentUser?.id;
        if (service.isEnabled() &&
            accountId != null &&
            await service.isGateActive() &&
            await service.ownedBy(accountId)) {
          return '/${_biometricUnlockPathSegment}';
        }
      } catch (_) {
        // Never brick navigation on a local-security read error.
      }
    }

    // Public routes that don't require auth
    final publicRoutes = ['/login', '/register', '/splash', '/legal/'];
    final isPublicRoute = publicRoutes.any((route) => 
        state.matchedLocation.startsWith(route));

    // If not authenticated and trying to access protected route
    if (!isAuthenticated && !isPublicRoute) {
      return '/login';
    }

    // If authenticated but onboarding not complete
    if (isAuthenticated && !isOnboardingComplete && 
        state.matchedLocation != '/onboarding') {
      return '/onboarding';
    }

    // If authenticated and trying to access auth routes
    if (isAuthenticated && isAuthRoute && isOnboardingComplete) {
      return '/home';
    }

    return null; // No redirect needed
  }

  // ============================================================================
  // ROUTE TREE
  // ============================================================================

  List<RouteBase> _buildRoutes() {
    return [
      // Splash screen (initial loading)
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const _SplashPage(),
      ),

      // ====================================================================
      // AUTH ROUTES (unauthenticated)
      // ====================================================================
      GoRoute(
        path: '/login',
        name: RouteNames.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        name: RouteNames.register,
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/onboarding',
        name: RouteNames.onboarding,
        // OnboardingBloc is a ChangeNotifier driver (not a Bloc), so the
        // page owns its lifecycle: the route builds it and disposes it via
        // OnboardingConsentPage.dispose().
        builder: (context, state) => OnboardingConsentPage(
          bloc: getIt<OnboardingBloc>(),
        ),
      ),

      // ====================================================================
      // LEGAL DOCUMENT ROUTES (public)
      // ====================================================================
      GoRoute(
        path: '/legal/:documentType',
        name: RouteNames.legalDocument,
        builder: (context, state) {
          final docType = state.pathParameters['documentType']!;
          return LegalConsentPage(
            documentType: docType,
            documentTitle: _getDocumentTitle(docType),
          );
        },
      ),

      // ====================================================================
      // SHELL ROUTE (authenticated area with bottom nav)
      // ====================================================================
      ShellRoute(
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
          // Home
          GoRoute(
            path: '/home',
            name: RouteNames.home,
            builder: (context, state) => const HomePage(),
          ),

          // ==================================================================
          // NIDUS (Rides)
          // ==================================================================
          GoRoute(
            path: '/nidus/request',
            name: RouteNames.rideRequest,
            builder: (context, state) => BlocProvider(
              create: (_) => _rideBlocFactory(),
              child: const RideRequestPage(),
            ),
          ),
          GoRoute(
            path: '/nidus/tracking/:rideId',
            name: RouteNames.rideTracking,
            builder: (context, state) {
              final rideId = state.pathParameters['rideId']!;
              // Phase 6: the tracking page owns its bloc and hands it to the
              // Safety Toolkit route via `extra` (see _pushSafetyToolkit in
              // ride_tracking_page.dart), so the toolkit must NOT create a
              // fresh one when pushed from an active trip.
              return BlocProvider(
                create: (_) => _rideBlocFactory(),
                child: RideTrackingPage(rideId: rideId),
              );
            },
          ),
          // AR walking navigation (§1.5): previously an unrouted orphan file.
          // Double-gated: the compile-time kill switch
          // (--dart-define=FEATURE_AR_NAVIGATION=false) AND the runtime
          // `ar_navigation` flag from config/feature-flags/flags.json
          // (enabled=true, rollout 50%, staging/production targeting). When
          // either gate is off — or when the required destination query
          // params are absent — we redirect back to tracking instead of
          // rendering a dead-end screen. No fabricated coordinates: the
          // caller (tracking page's "Walk to pickup (AR)" button) supplies
          // the real pickup position from live ride state.
          GoRoute(
            path: '/nidus/ar-nav/:rideId',
            name: RouteNames.rideArNavigation,
            redirect: (context, state) async {
              // Phase 6: single source of truth. ArNavigationGate.resolve()
              // applies the compile switch AND the runtime flag against the
              // same install bucket the tracking-page entry button uses
              // (previously this redirect and the button each carried a
              // hand-copied version of the logic).
              if (!await ArNavigationGate.resolve()) {
                return '/nidus/tracking/${state.pathParameters['rideId']}';
              }
              final hasDestination =
                  state.uri.queryParameters.containsKey('lat') &&
                      state.uri.queryParameters.containsKey('lng');
              if (!hasDestination) {
                return '/nidus/tracking/${state.pathParameters['rideId']}';
              }
              return null;
            },
            builder: (context, state) {
              final lat = double.parse(
                  state.uri.queryParameters['lat'] ?? 'nan');
              final lng = double.parse(
                  state.uri.queryParameters['lng'] ?? 'nan');
              final name = state.uri.queryParameters['name'] ??
                  'Pickup point';
              return ARNavigationPage(
                destinationLat: lat,
                destinationLng: lng,
                destinationName: name,
              );
            },
          ),
          GoRoute(
            path: '/nidus/history',
            name: RouteNames.rideHistory,
            builder: (context, state) => const RideHistoryPage(),
          ),
          // Phase 6 (nav consistency): the toolkit is pushed from tracking
          // via context.pushNamed so it shares the live RideBloc instead of
          // a fresh one — SafetyToolkitPage operates on the trip in progress
          // (SOS, live location share); a bloc that knows nothing about the
          // ride would render dead actions. The route still works as a deep
          // link: without `extra` we fall back to a freshly created bloc
          // (the page itself degrades honestly when no ride is loaded).
          GoRoute(
            path: '/nidus/safety',
            name: RouteNames.safetyToolkit,
            builder: (context, state) {
              final sharedBloc = state.extra;
              if (sharedBloc is RideBloc) {
                return BlocProvider.value(
                  value: sharedBloc,
                  child: const SafetyToolkitPage(),
                );
              }
              return BlocProvider(
                create: (_) => _rideBlocFactory(),
                child: const SafetyToolkitPage(),
              );
            },
          ),

          // ==================================================================
          // PHASE 6 (nav consistency): chat & receipt were long pushed as
          // raw MaterialPageRoutes from the tracking page — invisible to
          // deep links, flag gates and web URL sync. They are first-class
          // GoRouter routes now.
          // ==================================================================
          GoRoute(
            path: ChatPage.pathTemplate, // '/nidus/chat/:rideId'
            name: RouteNames.rideChat,
            builder: (context, state) => ChatPage(
              rideId: state.pathParameters['rideId']!,
            ),
          ),
          // Receipt deep-links must NOT assume a live bloc: the ride entity
          // arrives either via `extra` (fast path from tracking, which holds
          // the completed Ride in hand) or by loading GET /rides/{id}
          // through the repository (cold deep link / web URL).
          GoRoute(
            path: '/nidus/receipt/:rideId',
            name: RouteNames.rideReceipt,
            builder: (context, state) => _ReceiptRoute(
              rideId: state.pathParameters['rideId']!,
              preloadedRide: state.extra is Ride ? state.extra as Ride : null,
            ),
          ),
          GoRoute(
            path: '/nidus/notifications',
            name: RouteNames.notificationInbox,
            builder: (context, state) =>
                const NotificationInboxPage(),
          ),

          // ==================================================================
          // HAVEN (Hotels)
          // ==================================================================
          GoRoute(
            path: '/haven/search',
            name: RouteNames.hotelSearch,
            builder: (context, state) => BlocProvider(
              create: (_) => GetIt.I<HotelSearchBloc>(),
              child: const HotelSearchPage(),
            ),
          ),
          GoRoute(
            path: '/haven/hotel/:hotelId',
            name: RouteNames.hotelDetail,
            builder: (context, state) {
              final hotelId = state.pathParameters['hotelId']!;
              return HotelDetailPage(hotelId: hotelId);
            },
          ),
          GoRoute(
            path: '/haven/booking/:hotelId',
            name: RouteNames.booking,
            builder: (context, state) {
              final hotelId = state.pathParameters['hotelId']!;
              return BookingPage(hotelId: hotelId);
            },
          ),

          // ==================================================================
          // VORAX (Food)
          // ==================================================================
          GoRoute(
            path: '/vorax/restaurants',
            name: RouteNames.restaurantList,
            builder: (context, state) => BlocProvider(
              create: (_) => GetIt.I<RestaurantBloc>(),
              child: const RestaurantListPage(),
            ),
          ),
          GoRoute(
            path: '/vorax/restaurant/:restaurantId/menu',
            name: RouteNames.menu,
            builder: (context, state) {
              final restaurantId = state.pathParameters['restaurantId']!;
              return MenuPage(restaurantId: restaurantId);
            },
          ),
          GoRoute(
            path: '/vorax/orders',
            name: RouteNames.orderHistory,
            builder: (context, state) => const OrderHistoryPage(),
          ),
          GoRoute(
            path: '/vorax/order/:orderId/tracking',
            name: RouteNames.orderTracking,
            builder: (context, state) {
              final orderId = state.pathParameters['orderId']!;
              return OrderTrackingPage(orderId: orderId);
            },
          ),

          // ==================================================================
          // PROFILE & SETTINGS
          // ==================================================================
          GoRoute(
            path: '/profile',
            name: RouteNames.profile,
            builder: (context, state) => const ProfilePage(),
          ),
          GoRoute(
            path: '/settings',
            name: RouteNames.settings,
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/settings/consent',
            name: RouteNames.consentManagement,
            builder: (context, state) => const ConsentManagementPage(),
          ),

          // ==================================================================
          // WALLET (Ledger — Phase H Step 1)
          // ==================================================================
          GoRoute(
            path: '/wallet',
            name: RouteNames.wallet,
            builder: (context, state) {
              final disputeRideId = state.uri.queryParameters['disputeRideId'];
              return BlocProvider(
                create: (_) => _walletBlocFactory()..add(const LoadWallet()),
                child: WalletPage(disputeRideId: disputeRideId),
              );
            },
          ),
        ],
      ),
    ];
  }

  String _getDocumentTitle(String documentType) {
    switch (documentType) {
      case 'terms_of_service':
        return 'Terms of Service';
      case 'privacy_policy':
        return 'Privacy Policy';
      case 'cookie_policy':
        return 'Cookie Policy';
      case 'driver_terms':
        return 'Driver Terms';
      case 'payment_terms':
        return 'Payment Terms';
      case 'token_terms':
        return 'Token Terms';
      default:
        return 'Legal Document';
    }
  }
}

// ============================================================================
// APP SHELL (Bottom Navigation Bar)
// ============================================================================

class _AppShell extends StatefulWidget {
  final Widget child;

  const _AppShell({required this.child});

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  StreamSubscription<AuthState>? _authBindSub;

  @override
  void initState() {
    super.initState();
    // Bind the notification hub to the signed-in user (§1.4): WS topic
    // subscription + inbox unread count follow auth state; logout unbinds so
    // stale rows never surface for the next user.
    final authBloc = getIt<AuthBloc>();
    final notifications = getIt<NotificationService>();
    void apply(AuthState s) => notifications.bindUser(
          s is AuthAuthenticated ? s.user.id : null,
        );
    apply(authBloc.state);
    _authBindSub = authBloc.stream.listen(apply);

    // Route taps on notification surfaces (banner/tray/killed-launch) through
    // the single router (§1.4 step 5).
    getIt<FcmService>().taps.listen((tap) {
      final location = tap.deepLink != null && tap.notification == null
          ? NotificationRouter.resolveFromRawData({'deep_link': tap.deepLink!})
          : (tap.notification != null
              ? NotificationRouter.resolveLocation(tap.notification!)
              : null);
      if (location != null) context.go(location);
    });
  }

  @override
  void dispose() {
    _authBindSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          widget.child,
          // Slide-down in-app banner overlaying every shell route.
          InAppNotificationBanner(
            service: getIt<NotificationService>(),
            onNavigate: (ctx, location) => ctx.go(location),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final currentLocation = GoRouterState.of(context).matchedLocation;
    
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _calculateSelectedIndex(currentLocation),
      onTap: (index) => _onItemTapped(context, index),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.directions_car_outlined),
          activeIcon: Icon(Icons.directions_car),
          label: 'Rides',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.restaurant_outlined),
          activeIcon: Icon(Icons.restaurant),
          label: 'Food',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.hotel_outlined),
          activeIcon: Icon(Icons.hotel),
          label: 'Stays',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet_outlined),
          activeIcon: Icon(Icons.account_balance_wallet),
          label: 'Wallet',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }

  int _calculateSelectedIndex(String location) {
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/nidus')) return 1;
    if (location.startsWith('/vorax')) return 2;
    if (location.startsWith('/haven')) return 3;
    if (location.startsWith('/wallet')) return 4;
    if (location.startsWith('/profile') || location.startsWith('/settings')) return 5;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.goNamed(RouteNames.home);
        break;
      case 1:
        context.goNamed(RouteNames.rideRequest);
        break;
      case 2:
        context.goNamed(RouteNames.restaurantList);
        break;
      case 3:
        context.goNamed(RouteNames.hotelSearch);
        break;
      case 4:
        context.goNamed(RouteNames.wallet);
        break;
      case 5:
        context.goNamed(RouteNames.profile);
        break;
    }
  }
}

// ============================================================================
// SPLASH PAGE
// ============================================================================

class _SplashPage extends StatefulWidget {
  const _SplashPage();

  @override
  State<_SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<_SplashPage> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Phase 5 (render first, initialize second): NO artificial 2-second wait
    // and NO eager OfflineService.initialize() here — offline initialization
    // belongs to the startup coordinator's deferred Stage B. The splash only
    // has to hand off to AuthBloc promptly so session hydration can begin;
    // routing stays gated on real AuthBloc state, never on a timer.
    if (!hasStartupCoordinator) {
      // Widget tests / tooling that mount the router without main()'s
      // coordinator: dispatch immediately so auth flows still progress.
      _kickoffAuth();
      return;
    }
    // Production: wait for the very next frame boundary (shell painted), then
    // dispatch. No network or storage work happens before this point.
    await WidgetsBinding.instance.endOfFrame;
    _kickoffAuth();
  }

  void _kickoffAuth() {
    if (!mounted) return;
    // AuthBloc triggers the redirect based on validated state; CheckAuthStatus
    // is idempotent under retries (re-reading Hive + one server round-trip).
    GetIt.instance<AuthBloc>().add(const CheckAuthStatus());
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FlutterLogo(size: 100),
            SizedBox(height: 24),
            Text(
              'NIDAW',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text('Building the Future of Urban Life'),
            SizedBox(height: 48),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ERROR PAGE
// ============================================================================

class _ErrorPage extends StatelessWidget {
  final Exception? error;

  const _ErrorPage({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page Not Found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Oops! Page not found',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                error?.toString() ?? 'The page you\'re looking for doesn\'t exist.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.goNamed(RouteNames.home),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PHASE 6 (nav consistency): receipt deep-link loader
// ============================================================================

/// Route-level wrapper for `/nidus/receipt/:rideId`.
///
/// Receipt deep-links must NOT assume a live bloc: the ride entity arrives
/// either via `extra` (fast path from tracking, which holds the completed
/// Ride in hand) or by loading GET /rides/{id} through the repository
/// (cold deep link / web URL). While loading we show an honest skeleton —
/// never a false 'not found' (Phase-1 rule: pre-load states are skeletons,
/// not empty/error copy). On null/failure we surface a localized, retryable
/// error state rather than silently popping.
class _ReceiptRoute extends StatefulWidget {
  const _ReceiptRoute({required this.rideId, this.preloadedRide});

  final String rideId;
  final Ride? preloadedRide;

  @override
  State<_ReceiptRoute> createState() => _ReceiptRouteState();
}

class _ReceiptRouteState extends State<_ReceiptRoute> {
  late Future<Ride?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Ride?> _load() async {
    try {
      return await getIt<RideRepository>().getRide(widget.rideId);
    } catch (_) {
      // Failure and absence render the same honest, retryable state; the
      // raw error is intentionally swallowed at the primary surface (it may
      // leak transport details), matching the Phase-1 error-copy rule.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preloadedRide != null) {
      return ReceiptDetailPage(ride: widget.preloadedRide!);
    }
    return FutureBuilder<Ride?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: SafeArea(child: _ReceiptLoadingSkeleton()),
          );
        }
        final ride = snapshot.data;
        if (ride == null) {
          final l10n = context.l10n;
          return Scaffold(
            appBar: AppBar(title: Text(l10n.receiptTitle)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.receiptLoadFailedTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.receiptLoadFailedBody,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => setState(() => _future = _load()),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.commonRetry),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return ReceiptDetailPage(ride: ride);
      },
    );
  }
}

/// Minimal static skeleton mirroring the receipt layout while the ride
/// loads (no shimmer dependency here — keeps the router file light; the
/// history page's richer skeleton stays where it lives).
class _ReceiptLoadingSkeleton extends StatelessWidget {
  const _ReceiptLoadingSkeleton();

  Widget _bar(BuildContext context, double width, {double height = 16}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _bar(context, 160, height: 28),
        const SizedBox(height: 24),
        _bar(context, double.infinity, height: 96),
        const SizedBox(height: 16),
        _bar(context, 220),
        const SizedBox(height: 12),
        _bar(context, 180),
        const SizedBox(height: 12),
        _bar(context, 200),
        const SizedBox(height: 24),
        _bar(context, double.infinity, height: 48),
      ],
    );
  }
}

// ============================================================================
// EXTENSION METHODS FOR CONVENIENCE
// ============================================================================

extension NavigationHelper on BuildContext {
  /// Navigate to home
  void goHome() => GoRouter.of(this).goNamed(RouteNames.home);
  
  /// Navigate to ride request
  void goRideRequest() => GoRouter.of(this).goNamed(RouteNames.rideRequest);
  
  /// Navigate to ride tracking
  void goRideTracking(String rideId) => 
      GoRouter.of(this).go('/nidus/tracking/$rideId');
  
  /// Navigate to hotel search
  void goHotelSearch() => GoRouter.of(this).goNamed(RouteNames.hotelSearch);
  
  /// Navigate to restaurant list
  void goRestaurants() => GoRouter.of(this).goNamed(RouteNames.restaurantList);
  
  /// Navigate to profile
  void goProfile() => GoRouter.of(this).goNamed(RouteNames.profile);

  /// Navigate to the ledger wallet
  void goWallet() => GoRouter.of(this).goNamed(RouteNames.wallet);

  /// Open the wallet with the dispute form pre-filled for a completed ride.
  void goWalletDispute(String rideId) =>
      GoRouter.of(this).go('/wallet?disputeRideId=$rideId');
  
  /// Navigate to login
  void goLogin() => GoRouter.of(this).goNamed(RouteNames.login);
  
  /// Logout and redirect to login
  void logout() {
    GetIt.instance<AuthBloc>().add(LogoutRequested());
    GoRouter.of(this).goNamed(RouteNames.login);
  }
}