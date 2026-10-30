import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../analytics/startup_performance_service.dart';
import '../config/feature_flag_service.dart';
import '../di/injection.dart';
import '../geocoding/geocoding_cache.dart';
import '../network/websocket_client.dart';
import '../notifications/fcm_service.dart';
import '../offline/offline_service.dart';
import '../../l10n/l10n.dart' show LocaleController;
import 'startup_state.dart';

/// ============================================================================
/// APP STARTUP COORDINATOR (consumer, Phase 5)
/// ============================================================================
///
/// Owns the "render first, initialize second" contract:
///
///   Stage A (blocking, before runApp — must stay tiny):
///     Flutter binding + Hive init + open ONLY the three boxes the first
///     frame and auth hydration need ('auth', 'settings', 'cache'), plus the
///     synchronous registration of lazy singletons. No network, no permission
///     prompts, no external providers, no map engine.
///
///   Stage B (post-first-frame, asynchronous):
///     Offline service, geocoding cache hydration, feature flags, Firebase /
///     FCM push bootstrap, WebSocket readiness. Each step is independently
///     guarded: one failing subsystem degrades honestly (its phase flips to
///     `failed`, a retry is scheduled) and never blocks or re-blocks the UI.
///
/// Nothing here fabricates live data: cached sessions remain provisional
/// until AuthBloc's server round-trip validates them, push availability is
/// only claimed when FCM actually initialized, and booking actions require
/// [StartupSnapshot.isBookingReady] (server-validated, never cache-only).
class AppStartupCoordinator {
  AppStartupCoordinator({
    required this.state,
    required this.perf,
    @visibleForTesting this.steps,
  });

  final StartupStateNotifier state;
  final StartupPerformanceService perf;

  /// Injectable override for tests: replaces the real stage-B work list.
  final List<DeferredStartupStep>? steps;

  bool _stageADone = false;
  bool _stageBStarted = false;
  final List<Timer> _retryTimers = [];
  final List<StreamSubscription<dynamic>> _subs = [];

  /// --------------------------------------------------------------------------
  /// STAGE A — startup-critical path (called from main() BEFORE runApp)
  /// --------------------------------------------------------------------------
  ///
  /// Deliberately excludes: Firebase.initializeApp, FCM permission prompt,
  /// GeocodingCache.open, FeatureFlagService.load, OfflineService.initialize,
  /// any network call. Those all move to Stage B.
  Future<void> runStartupCriticalStage() async {
    if (_stageADone) return;
    final sw = perf.startStopwatch('stageA.startupCritical');
    await sw.time('hive.init', () async {
      await Hive.initFlutter();
      // Only the boxes the first frame + session hydration genuinely need.
      // 'pending_operations'/'cached_data' (OfflineService) and the geocoding
      // box open in Stage B instead.
      await Hive.openBox('auth');
      await Hive.openBox('settings');
      await Hive.openBox('cache');
    });
    // Synchronous, allocation-only registrations (lazy singletons are not
    // constructed here — getIt defers construction to first resolution).
    registerCoreDependencies(state);
    // Restore the persisted locale synchronously so the very first frame
    // already uses the right language (no rebuild storm later). Hive's 'settings'
    // box was opened just above, so readSavedCode() hits the real store;
    // apply.value is a pure in-memory assignment.
    LocaleController.apply.value =
        LocaleController.localeFromCode(LocaleController.readSavedCode());
    state.markReady(StartupSubsystem.bootstrap);
    _stageADone = true;
    sw.stop();
    perf.finishStage('stageA.startupCritical');
  }

  /// --------------------------------------------------------------------------
  /// STAGE B — deferred initialization (scheduled after the first frame)
  /// --------------------------------------------------------------------------
  ///
  /// Safe to call repeatedly; runs once. Failures inside a step are captured,
  /// marked on [StartupStateNotifier], and retried with bounded backoff.
  void scheduleDeferredInitialization() {
    if (!_stageADone || _stageBStarted) return;
    _stageBStarted = true;
    // Let the shell paint first: wait until the end of this frame, then yield
    // an additional microtask turn so the splash/home frame is committed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(runDeferredInitialization());
    });
  }

  /// Exposed for integration tests (deterministic execution without waiting
  /// on frames) and for the post-frame callback above.
  Future<void> runDeferredInitialization() async {
    final work = steps ?? _defaultSteps();
    final sw = perf.startStopwatch('stageB.deferred');
    for (final step in work) {
      await _runStep(step);
    }
    // Mark the interactive cached shell milestone once Stage B has settled
    // every deferred subsystem (success or honest failure). This is distinct
    // from map readiness — a fast placeholder must not call markMapReady.
    if (steps == null) {
      perf.markInteractiveShell();
    }
    await sw.stopIfRunning();
    perf.finishStage('stageB.deferred');
  }

  Future<void> _runStep(DeferredStartupStep step) async {
    state.markRunning(step.subsystem);
    try {
      await step.body();
      state.markReady(step.subsystem);
      perf.recordPhase(step.subsystem.name, succeeded: true);
    } catch (e, st) {
      debugPrint('[startup] ${step.subsystem.name} failed: $e\n$st');
      state.markFailed(step.subsystem);
      perf.recordPhase(step.subsystem.name, succeeded: false);
      _scheduleRetry(step);
    }
  }

  /// Bounded recovery: at most [maxRetries] attempts, exponential backoff.
  /// Exhaustion leaves the subsystem honestly `failed` — the UI reads that
  /// state instead of pretending initialization succeeded.
  void _scheduleRetry(DeferredStartupStep step) {
    const maxRetries = 3;
    var attempt = 0;
    void scheduleNext() {
      if (attempt >= maxRetries) return;
      attempt++;
      final delay = Duration(seconds: 2 * attempt);
      final timer = Timer(delay, () async {
        if (state.snapshot.isReady(step.subsystem)) return;
        state.markRunning(step.subsystem);
        try {
          await step.body();
          state.markReady(step.subsystem);
          perf.recordPhase('${step.subsystem.name}.retry', succeeded: true);
        } catch (e) {
          debugPrint('[startup] retry $attempt ${step.subsystem.name}: $e');
          state.markFailed(step.subsystem);
          scheduleNext();
        }
      });
      _retryTimers.add(timer);
    }
    scheduleNext();
  }

  // ==========================================================================
  // DEFAULT DEFERRED STEPS (production wiring)
  // ==========================================================================

  List<DeferredStartupStep> _defaultSteps() {
    return [
      // 1. Offline service: opens its own Hive boxes, starts the connectivity
      //    stream and marks connectivity known as soon as the first check
      //    lands (online OR offline — both are settled answers).
      DeferredStartupStep(
        subsystem: StartupSubsystem.offlineService,
        body: () async {
          final offline = getIt<OfflineService>();
          await offline.initialize();
          await offline.initialConnectivitySettled;
          state.markConnectivityKnown();
          // Hydrate last-known ride summary / cached home content markers.
          if (offline.hasCachedData(OfflineService.lastRideSummaryKey)) {
            state.markCacheHydrated();
          }
        },
      ),

      // 2. Geocoding cache: dedicated Hive box opened asynchronously so the
      //    search UI works cache-first the moment it is mounted.
      DeferredStartupStep(
        subsystem: StartupSubsystem.geocodingCache,
        body: () async {
          final cache = await GeocodingCache.open();
          registerGeocodingCache(cache);
        },
      ),

      // 3. Feature flags: bundled asset read — cheap, but still off the
      //    first-frame path. Missing file degrades every flag to disabled.
      DeferredStartupStep(
        subsystem: StartupSubsystem.featureFlags,
        body: () async {
          final flags = await FeatureFlagService.load();
          registerFeatureFlags(flags);
        },
      ),

      // 4. Push substrate: Firebase + FCM permission/token registration.
      //    Returns false on denial — surfaced via in-app banner + inbox,
      //    never blocking anything. Kept last: iOS may show a permission
      //    dialog here, which must NEVER gate the first frame.
      DeferredStartupStep(
        subsystem: StartupSubsystem.pushNotifications,
        body: () async {
          await ensureFirebaseInitialized();
          final granted = await getIt<FcmService>().initialize();
          perf.recordPushPermission(granted);
        },
      ),

      // 5. Realtime channel readiness marker. The socket itself connects via
      //    AuthBloc.onAuthenticated (token-scoped); we only observe its state
      //    stream so the snapshot reflects reality, not intention.
      DeferredStartupStep(
        subsystem: StartupSubsystem.realtimeChannel,
        body: () async {
          final ws = getIt<WebSocketClient>();
          final sub = ws.stateStream.listen((s) {
            switch (s) {
              case WebSocketConnectionState.connected:
                state.markReady(StartupSubsystem.realtimeChannel);
              case WebSocketConnectionState.error:
              case WebSocketConnectionState.disconnected:
                // Not-connected is not a startup failure — the socket simply
                // waits for authentication. Leave the phase running/pending.
                break;
              case WebSocketConnectionState.connecting:
                state.markRunning(StartupSubsystem.realtimeChannel);
            }
          });
          _subs.add(sub);
        },
      ),
    ];
  }

  /// Logout / hot-restart hook: drop retry timers and reset readiness so a
  /// fresh login re-proves every subsystem (never inherits stale readiness).
  Future<void> reset() async {
    for (final t in _retryTimers) {
      t.cancel();
    }
    _retryTimers.clear();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _stageBStarted = false;
    state.reset();
  }

  void dispose() {
    for (final t in _retryTimers) {
      t.cancel();
    }
    _retryTimers.clear();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

/// One unit of Stage-B work with the phase it gates.
@immutable
class DeferredStartupStep {
  const DeferredStartupStep({
    required this.subsystem,
    required this.body,
  });

  final StartupSubsystem subsystem;
  final Future<void> Function() body;
}

// ============================================================================
// PROCESS-LEVEL ACCESSOR
// ============================================================================
//
// main() constructs the coordinator before runApp so widgets, the router and
// integration tests can reach the same StartupStateNotifier instance. Tests
// that build their own coordinator never touch this global.
AppStartupCoordinator? _currentCoordinator;

AppStartupCoordinator get currentStartupCoordinator {
  final c = _currentCoordinator;
  if (c == null) {
    throw StateError(
      'AppStartupCoordinator not installed — main() must run '
      'installStartupCoordinator() before any widget resolves it.',
    );
  }
  return c;
}

StartupStateNotifier get startupState => currentStartupCoordinator.state;

bool get hasStartupCoordinator => _currentCoordinator != null;

void installStartupCoordinator(AppStartupCoordinator coordinator) {
  _currentCoordinator = coordinator;
}
