import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/analytics/startup_performance_service.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/startup/app_startup_coordinator.dart';
import 'core/startup/startup_state.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/legal_consent_bloc.dart';
import 'features/nidus/presentation/bloc/ride_bloc.dart';
import 'features/profile/presentation/bloc/profile_bloc.dart';
import 'l10n/l10n.dart';

/// ============================================================================
/// NIDAW CONSUMER ENTRY POINT (Phase 5 — render first, initialize second)
/// ============================================================================
///
/// The pre-runApp path is deliberately tiny:
///   1. Flutter binding + performance anchor (no I/O).
///   2. Stage A (`runStartupCriticalStage`): Hive init, the three boxes the
///      first frame and session hydration genuinely need ('auth', 'settings',
///      'cache'), synchronous lazy DI registration and locale restore.
///   3. `runApp` immediately — the native splash hands over to the lightweight
///      Flutter shell.
/// Everything else — OfflineService, geocoding cache, feature flags, Firebase/
/// FCM push bootstrap (permission prompts!), WebSocket readiness — runs AFTER
/// the first frame via the coordinator's Stage B, each step independently
/// guarded with bounded retries. Slow networks or a failing secondary service
/// can therefore never prevent the initial screen from rendering, and nothing
/// is fabricated while they initialize: the UI reads honest readiness from
/// [StartupStateNotifier] instead.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final perf = StartupPerformanceService();
  final startupState = StartupStateNotifier();
  final coordinator =
      AppStartupCoordinator(state: startupState, perf: perf);
  installStartupCoordinator(coordinator);

  try {
    await coordinator.runStartupCriticalStage();
  } catch (e, st) {
    // Stage A failure (e.g. corrupt Hive storage) must NOT blank the app:
    // register what we can, report the failure honestly and still render —
    // the router shows a signed-out/retry state rather than an infinite
    // splash. Deferred stages will surface their own errors per subsystem.
    debugPrint('[startup] critical stage failed: $e\n$st');
    startupState.failSessionHydration();
    rethrow;
  }

  perf.markAppMounted();
  runApp(NidawApp(startupState: startupState));

  // Post-first-frame initialization (Firebase/FCM, offline sync, geocoding
  // cache, feature flags, realtime readiness). Scheduled after runApp so the
  // shell paints first; safe to call repeatedly (runs once).
  coordinator.scheduleDeferredInitialization();
}

class NidawApp extends StatelessWidget {
  const NidawApp({super.key, required this.startupState});

  /// Injected from main() so widgets/tests share the exact notifier the
  /// coordinator mutates (also available through getIt for deep consumers).
  final StartupStateNotifier startupState;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => getIt<AuthBloc>()..add(const CheckAuthStatus()),
        ),
        BlocProvider(
          create: (_) => getIt<LegalConsentBloc>(),
        ),
        BlocProvider(
          create: (_) => getIt<RideBloc>(),
        ),
        BlocProvider(
          create: (_) => getIt<ProfileBloc>(),
        ),
      ],
      // §4.3 Localization: the settings language switcher writes through
      // LocaleController.saveCode(), which pushes onto this notifier. The
      // root rebuilds with the new locale immediately; null = system default.
      child: ValueListenableBuilder<Locale?>(
        valueListenable: LocaleController.apply,
        builder: (context, savedLocale, _) {
          return MaterialApp.router(
            title: 'NIDAW',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.system,
            routerConfig: getIt<AppRouter>().router,
            locale: savedLocale,
            supportedLocales: LocaleController.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          );
        },
      ),
    );
  }
}
