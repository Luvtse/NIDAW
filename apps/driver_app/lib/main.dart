import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/analytics/startup_performance_service.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/startup/driver_startup_coordinator.dart';
import 'core/startup/driver_startup_state.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/earnings/presentation/bloc/earnings_bloc.dart';
import 'features/home/presentation/bloc/driver_home_bloc.dart';
import 'features/profile/presentation/bloc/driver_profile_bloc.dart';
import 'features/ride/presentation/bloc/active_ride_bloc.dart';

/// ============================================================================
/// NIDAW DRIVER ENTRY POINT (Phase 5 — render first, recover safely second)
/// ============================================================================
///
/// The pre-runApp path is deliberately tiny (§4.3):
///   1. Flutter binding + performance anchor (no I/O).
///   2. Stage A: Hive init + ONLY the 'driver_auth' box (the minimum local
///      storage required to restore authentication and trip state) +
///      synchronous lazy DI registration. Firebase stays on the pre-frame
///      path ONLY because firebase_messaging's native plugin registration
///      requires the app instance before any FCM API call; it performs no
///      network round-trip there. Everything else moves after the first frame.
///   3. runApp immediately — the native splash hands over to the lightweight
///      Flutter shell.
///
/// Post-first-frame (coordinator Stage B + auth-gated events):
///   - Provisional session hydration from the already-open auth box.
///   - Authenticated WebSocket connect + `driver:offers` subscription. The
///     legacy `Future.delayed(500ms)` subscribe hack is GONE: dispatch wiring
///     is triggered by AuthBloc through DriverStartupCoordinator.onAuthenticated
///     exactly when a token exists — never earlier, never blindly retried
///     while signed out.
///   - Active-trip recovery from the authoritative backend GET (bounded
///     retries; exhausted -> honest failure UI, never a fabricated "no trip").
///   - Availability restored as PROVISIONAL until server-confirmed.
///   - Location tracking starts only when permissions AND driver state permit.
///   - Earnings / profile / documents screens resolve their repositories
///     lazily on first access — they are untouched during startup.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final perf = StartupPerformanceService();
  final startupState = DriverStartupStateNotifier();
  final coordinator =
      DriverStartupCoordinator(state: startupState, perf: perf);
  installDriverStartupCoordinator(coordinator);

  try {
    // Documented platform requirement: FirebaseCore must exist before any
    // messaging plugin call. No FCM handler registration or permission
    // prompt happens here — those stay deferred with the notification owner.
    await Firebase.initializeApp();
    await coordinator.runStartupCriticalStage();
  } catch (e, st) {
    // Stage A failure (e.g. corrupt Hive storage) must NOT blank the app:
    // report honestly and still render — the router shows a retry/login state
    // rather than an infinite splash. Deferred stages surface their own
    // errors per subsystem.
    debugPrint('[driver-startup] critical stage failed: $e\n$st');
    startupState.markFailed(DriverStartupSubsystem.bootstrap);
    rethrow;
  }

  runApp(NidawDriverApp(startupState: startupState));

  // Post-first-frame initialization (secondary boxes, provisional session
  // read, authoritative trip recovery). Scheduled after runApp so the shell
  // paints first; safe to call repeatedly (guarded internally).
  coordinator.scheduleDeferredInitialization();
}

class NidawDriverApp extends StatelessWidget {
  const NidawDriverApp({super.key, required this.startupState});

  /// Injected from main() so widgets/tests share the exact notifier the
  /// coordinator mutates (also available through getIt for deep consumers).
  final DriverStartupStateNotifier startupState;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => getIt<AuthBloc>()..add(const CheckAuthStatus()),
        ),
        BlocProvider(
          create: (_) => getIt<DriverHomeBloc>(),
        ),
        BlocProvider(
          create: (_) => getIt<ActiveRideBloc>(),
        ),
        BlocProvider(
          create: (_) => getIt<EarningsBloc>(),
        ),
        BlocProvider(
          create: (_) => getIt<DriverProfileBloc>(),
        ),
      ],
      child: MaterialApp.router(
        title: 'NIDAW Driver',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        routerConfig: getIt<AppRouter>().router,
      ),
    );
  }
}
