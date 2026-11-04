import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../di/injection.dart' show getIt;
import '../startup/driver_startup_coordinator.dart'
    show hasDriverStartupCoordinator;
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/presentation/pages/onboarding_page.dart';

import '../../features/home/presentation/pages/driver_home_page.dart';

import '../../features/ride/presentation/pages/ride_acceptance_page.dart';
import '../../features/ride/presentation/pages/ride_navigation_page.dart';
import '../../features/ride/presentation/pages/ride_completion_page.dart';

import '../../features/earnings/presentation/pages/earnings_overview_page.dart';
import '../../features/earnings/presentation/pages/earnings_detail_page.dart';

import '../../features/documents/presentation/pages/documents_page.dart';

import '../../features/profile/presentation/pages/driver_profile_page.dart';
import '../../features/profile/presentation/pages/vehicle_info_page.dart';
import '../../features/profile/presentation/pages/settings_page.dart';

import '../../features/security/domain/services/driver_biometric_security_service.dart';
import '../../features/security/presentation/pages/driver_biometric_unlock_page.dart';

/// Bridges [AuthBloc] state changes to a [Listenable] for GoRouter's
/// `refreshListenable`.
///
/// With the pinned `bloc: ^8.1.x` dependency, `BlocBase` does not implement
/// `Listenable`, so it cannot be passed to `refreshListenable` directly.
/// This adapter subscribes to the bloc's public stream and notifies GoRouter
/// to re-evaluate its redirects whenever the auth state changes. It only
/// listens; it never mutates bloc state, and all other AuthBloc consumers
/// continue to use `add(...)`/`state` exclusively.
class _AuthRefreshListenable extends ChangeNotifier {
  StreamSubscription<AuthState>? _sub;

  _AuthRefreshListenable(AuthBloc bloc) {
    _sub = bloc.stream.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}

class AppRouter {
  final AuthBloc _authBloc;
  late final GoRouter _router;

  AppRouter({required AuthBloc authBloc}) : _authBloc = authBloc {
    _router = GoRouter(
      initialLocation: '/splash',
      refreshListenable: _AuthRefreshListenable(_authBloc),
      redirect: _globalRedirect,
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) => _SplashPage(authBloc: _authBloc),
        ),
        
        // Auth routes
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterPage(),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingPage(),
        ),

        // Home
        GoRoute(
          path: '/home',
          builder: (context, state) => const DriverHomePage(),
        ),

        // Ride routes
        GoRoute(
          path: '/ride/accept/:rideId',
          builder: (context, state) => RideAcceptancePage(
            rideId: state.pathParameters['rideId']!,
          ),
        ),
        GoRoute(
          path: '/ride/navigate/:rideId',
          builder: (context, state) => RideNavigationPage(
            rideId: state.pathParameters['rideId']!,
          ),
        ),
        GoRoute(
          path: '/ride/complete/:rideId',
          builder: (context, state) => RideCompletionPage(
            rideId: state.pathParameters['rideId']!,
          ),
        ),

        // Earnings
        GoRoute(
          path: '/earnings',
          builder: (context, state) => const EarningsOverviewPage(),
        ),
        GoRoute(
          path: '/earnings/detail',
          builder: (context, state) => const EarningsDetailPage(),
        ),

        // Documents
        GoRoute(
          path: '/documents',
          builder: (context, state) => const DocumentsPage(),
        ),

        // Profile
        GoRoute(
          path: '/profile',
          builder: (context, state) => const DriverProfilePage(),
        ),
        GoRoute(
          path: '/profile/vehicle',
          builder: (context, state) => const VehicleInfoPage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),

        // SECURITY (Phase 6 — local biometric gate): full-screen route shown
        // at cold start when the driver enabled biometric unlock on this
        // device. Unlocking only gates entry to the already-restored local
        // session; server authorization is unchanged and still flows
        // exclusively through session tokens + professional approval.
        GoRoute(
          path: '/$_biometricUnlockPath',
          builder: (context, state) =>
              const DriverBiometricUnlockPage(),
        ),
      ],
    );
  }

  /// Path of the local biometric unlock screen (see the route above).
  static const String _biometricUnlockPath = 'security/biometric-unlock';

  Future<String?> _globalRedirect(
      BuildContext context, GoRouterState state) async {
    final authState = _authBloc.state;
    final isAuthenticated = authState is AuthAuthenticated;
    final isOnboardingComplete = authState is AuthAuthenticated && 
                                  authState.onboardingComplete;

    final isAuthRoute = state.matchedLocation == '/login' ||
                       state.matchedLocation == '/register' ||
                       state.matchedLocation == '/splash';

    // Phase 6 (native biometric security): when the driver enabled the local
    // biometric gate on this device and a persisted session exists, cold
    // starts land on the unlock screen instead of hydrating straight into
    // the app. This is a LOCAL application gate only — tokens stay untouched
    // and every backend operation (including Go Online) still requires
    // server-side authentication AND professional approval. Fail-open by
    // construction: an unreadable preference or a device that lost its
    // enrollment simply resumes the normal flow rather than locking anyone
    // out of their own account.
    if (isAuthenticated && state.matchedLocation != '/$_biometricUnlockPath') {
      try {
        final service = getIt<DriverBiometricSecurityService>();
        final accountId = (authState as AuthAuthenticated).driver.id;
        if (service.isAppGateEnabled() &&
            await service.isAppGateActive() &&
            await service.ownedBy(accountId)) {
          return '/$_biometricUnlockPath';
        }
      } catch (_) {
        // Never brick navigation on a local-security read error.
      }
    }
    if (!isAuthenticated && !isAuthRoute) {
      return '/login';
    }

    if (isAuthenticated && !isOnboardingComplete && 
        state.matchedLocation != '/onboarding') {
      return '/onboarding';
    }

    if (isAuthenticated && isAuthRoute && isOnboardingComplete) {
      return '/home';
    }

    return null;
  }

  GoRouter get router => _router;
}

class _SplashPage extends StatefulWidget {
  final AuthBloc authBloc;

  const _SplashPage({required this.authBloc});

  @override
  State<_SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<_SplashPage> {
  AuthBloc get _authBloc => widget.authBloc;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Phase 5 (§4.3, render first / recover second): the artificial 2-second
    // timer is removed. Session restoration must be gated on real state, not
    // wall-clock time. When main() installed the DriverStartupCoordinator we
    // hand off at the very next frame boundary (shell painted); auth/trip
    // recovery proceeds from validated local storage and server responses.
    // Without a coordinator (widget tests / tooling), dispatch immediately so
    // auth flows still progress.
    if (!hasDriverStartupCoordinator) {
      _kickoffAuth();
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    _kickoffAuth();
  }

  void _kickoffAuth() {
    if (!mounted) return;
    // CheckAuthStatus is idempotent under retries (re-read of the already-open
    // driver_auth box + one bounded server round-trip). Routing decisions
    // remain driven by AuthBloc state — never by a delay.
    _authBloc.add(const CheckAuthStatus());
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car, size: 100, color: Colors.green),
            SizedBox(height: 24),
            Text(
              'NIDAW Driver',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 48),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}