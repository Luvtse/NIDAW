import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:hive_flutter/hive_flutter.dart';

import '../analytics/startup_performance_service.dart';
import '../di/injection.dart';
import '../network/location_service.dart';
import '../network/websocket_client.dart';
import '../../features/auth/data/repositories/auth_repository.dart';
import '../../features/ride/data/repositories/ride_repository.dart';
import 'driver_startup_state.dart';

/// ============================================================================
/// DRIVER STARTUP COORDINATOR (Phase 5, §4.3)
/// ============================================================================
///
/// Owns the driver app's "render first, recover safely second" contract:
///
///   Stage A (blocking, before runApp — deliberately tiny):
///     Hive.initFlutter + open ONLY 'driver_auth' (the box that decides
///     login-vs-loading for the first frame) + synchronous lazy DI
///     registration. No Firebase on the critical path unless a plugin
///     requires it; no network; no location; no offer subscription.
///
///   Stage B (post-first-frame):
///     1. Provisional session read from the already-open auth box.
///     2. Authenticated WebSocket connect + `driver:offers` subscription —
///        strictly AFTER a token exists (the WS client itself refuses to
///        connect anonymously; no blind reconnect loops while signed out).
///     3. Active-trip recovery via the authoritative backend GET (bounded
///        retries; exhausted -> honest `failed`, never a fabricated "no trip").
///     4. Availability restore as PROVISIONAL until server-confirmed.
///     5. Location tracking starts only when permissions AND driver state
///        permit it (online or on an active trip).
///
///   Lazy: earnings / profile / documents are resolved by their own screens on
///   first access — this coordinator never touches them.
///
/// The old `Future.delayed(500ms)` offer-subscribe hack in main() is replaced
/// by the event-driven [onAuthenticated] hook: AuthBloc notifies the
/// coordinator after every successful authentication (login/register/session
/// restore), and dispatch wiring happens exactly once per session.
class DriverStartupCoordinator {
  DriverStartupCoordinator({
    required this.state,
    required this.perf,
    @visibleForTesting this.steps,
  });

  final DriverStartupStateNotifier state;
  final StartupPerformanceService perf;

  /// Injectable override for tests: replaces the real stage-B work list.
  final List<DriverDeferredStartupStep>? steps;

  static const String offersTopic = 'driver:offers';

  bool _stageADone = false;
  bool _stageBStarted = false;
  bool _dispatchWired = false;
  bool _tripRecoveryDone = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  StreamSubscription<WebSocketConnectionState>? _wsStateSub;

  /// Topic(s) whose server ack authorizes dispatch actions. Kept generic so
  /// future topics (e.g. zone updates) can extend readiness without callers.
  static const Set<String> _requiredAcks = {offersTopic};
  final Set<String> _ackedTopics = {};

  // --------------------------------------------------------------------------
  // STAGE A — startup-critical path (called from main() BEFORE runApp)
  // --------------------------------------------------------------------------

  Future<void> runStartupCriticalStage() async {
    if (_stageADone) return;
    final sw = perf.startStopwatch('stageA.startupCritical');
    await sw.time('hive.init', () async {
      await Hive.initFlutter();
      // MINIMUM local storage: only the auth box gates the first frame's
      // routing decision. 'driver_cache' / 'driver_settings' open lazily in
      // Stage B / on first use by their owners.
      await Hive.openBox('driver_auth');
    });
    // Synchronous, allocation-only registrations (lazy singletons construct on
    // first resolution — earnings/profile/documents stay untouched).
    registerCoreDependencies(state);
    state.markReady(DriverStartupSubsystem.bootstrap);
    _stageADone = true;
    sw.stop();
    perf.finishStage('stageA.startupCritical');
  }

  // --------------------------------------------------------------------------
  // STAGE B — deferred initialization (scheduled after the first frame)
  // --------------------------------------------------------------------------

  void scheduleDeferredInitialization() {
    // Parity guard with the consumer coordinator: scheduling twice must never
    // enqueue two Stage-B runs (double trip-recovery GETs / double dispatch
    // wiring would break the exactly-once startup contract).
    if (!_stageADone || _stageBStarted) return;
    _stageBStarted = true;
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
    await sw.stopIfRunning();
    perf.finishStage('stageB.deferred');
  }

  Future<void> _runStep(DriverDeferredStartupStep step) async {
    state.markRunning(step.subsystem);
    try {
      await step.body();
      perf.recordPhase(step.subsystem.name, succeeded: true);
    } catch (e, st) {
      debugPrint('[driver-startup] ${step.subsystem.name} failed: $e\n$st');
      // markFailed only when the step didn't already record a more specific
      // terminal state (e.g. trip recovery "settled negative" vs hard fail).
      if (!state.snapshot.isReady(step.subsystem)) {
        state.markFailed(step.subsystem);
      }
      perf.recordPhase(step.subsystem.name, succeeded: false);
    }
  }

  // ==========================================================================
  // AUTH-GATED DISPATCH WIRING (§4.3: socket AFTER authentication)
  // ==========================================================================

  /// Called by AuthBloc (via the global accessor) after ANY successful
  /// authentication: session restore, login or registration. Idempotent per
  /// session; [reset] re-arms it on logout.
  Future<void> onAuthenticated() async {
    perf.markSessionRestored();
    state.markServerValidated();
    if (_dispatchWired) return;
    _dispatchWired = true;
    unawaited(_wireDispatch());
  }

  Future<void> _wireDispatch() async {
    try {
      final ws = getIt<WebSocketClient>();
      // Observe connection state so readiness reflects reality, not intent.
      _wsStateSub?.cancel();
      _wsStateSub = ws.stateStream.listen(_handleWsState);

      state.markRunning(DriverStartupSubsystem.realtimeChannel);
      // connectNow refuses to proceed without a token — it never throws into
      // a blind reconnect loop while signed out (unlike the legacy behavior).
      await ws.connectNow();
      if (!ws.isConnected) {
        // Socket still opening (or handshake pending): bounded, cancellable
        // retry — but only while a token exists.
        _scheduleAuthGatedReconnect();
      }
      // Subscription authorization follows connection; the ack (observed in
      // _handleMessage below) flips dispatchSubscription ready.
      ws.subscribe(offersTopic);
      _listenForAcks(ws);
    } catch (e) {
      debugPrint('[driver-startup] dispatch wiring failed: $e');
      state.markFailed(DriverStartupSubsystem.realtimeChannel);
      _scheduleAuthGatedReconnect();
    }
  }

  void _handleWsState(WebSocketConnectionState s) {
    switch (s) {
      case WebSocketConnectionState.connected:
        state.markReady(DriverStartupSubsystem.realtimeChannel);
        _reconnectAttempts = 0;
      case WebSocketConnectionState.connecting:
        state.markRunning(DriverStartupSubsystem.realtimeChannel);
      case WebSocketConnectionState.disconnected:
      case WebSocketConnectionState.error:
        // Not-connected is not a startup failure by itself; dispatch simply
        // isn't ready. Recovery is the auth-gated reconnect below.
        state.markRunning(DriverStartupSubsystem.realtimeChannel);
        state.markRunning(DriverStartupSubsystem.dispatchSubscription);
        _scheduleAuthGatedReconnect();
    }
  }

  /// Track subscription acks so isDispatchReady means "server authorized",
  /// not "we optimistically sent a subscribe frame".
  void _listenForAcks(WebSocketClient ws) {
    _ackSub?.cancel();
    _ackSub = ws.messageStream.listen((msg) {
      final type = msg['type'];
      if (type == 'subscription_ack' || type == 'subscribed') {
        final topic = (msg['topic'] ??
            (msg['payload'] is Map
                ? (msg['payload'] as Map)['topic']
                : null)) as String?;
        if (topic != null) _ackedTopics.add(topic);
        if (_requiredAcks.every(_ackedTopics.contains)) {
          state.markReady(DriverStartupSubsystem.dispatchSubscription);
          perf.markDispatchReady();
        }
      }
    });
  }

  StreamSubscription<Map<String, dynamic>>? _ackSub;

  /// Bounded reconnect, gated on authentication: stops immediately when the
  /// token disappears (logout) instead of hammering the gateway anonymous.
  void _scheduleAuthGatedReconnect() {
    _reconnectTimer?.cancel();
    const maxAttempts = 4;
    if (_reconnectAttempts >= maxAttempts) {
      state.markFailed(DriverStartupSubsystem.realtimeChannel);
      return;
    }
    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);
    _reconnectTimer = Timer(delay, () async {
      try {
        final token =
            await getIt<AuthRepository>().getAccessToken();
        if (token == null) return; // signed out — stop, do not fabricate.
        await getIt<WebSocketClient>().connectNow();
        getIt<WebSocketClient>().subscribe(offersTopic);
      } catch (_) {
        _scheduleAuthGatedReconnect();
      }
    });
  }

  // ==========================================================================
  // ACTIVE-TRIP RECOVERY (§4.3: authoritative backend query after start)
  // ==========================================================================

  Future<void> recoverActiveTrip() async {
    if (_tripRecoveryDone) return;
    state.markTripRecoveryStarted();
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final ride = await getIt<RideRepository>().getActiveRide();
        _tripRecoveryDone = true;
        if (ride != null) {
          state.markActiveRideFound(ride.id);
        } else {
          state.markNoActiveRide();
        }
        perf.markTripRecoverySettled();
        // Trip found => tracking permitted regardless of availability toggle.
        unawaited(syncLocationTrackingWithState());
        return;
      } catch (e) {
        debugPrint('[driver-startup] trip recovery attempt $attempt failed: $e');
        await Future<void>.delayed(
            Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    // Exhausted: honest failure — UI shows retry; we NEVER pretend "no trip".
    state.markTripRecoveryFailed();
  }

  // ==========================================================================
  // LOCATION GATE (§4.3 / §5.2: collect only when permitted)
  // ==========================================================================

  /// Starts continuous collection iff (a) the server confirmed availability
  /// or an active trip was recovered, and (b) permissions allow. Offline
  /// drivers stop collecting — battery and privacy both demand it.
  Future<void> syncLocationTrackingWithState() async {
    try {
      final loc = getIt<LocationService>();
      if (state.snapshot.trackingPermitted) {
        if (!loc.isTracking) {
          state.markRunning(DriverStartupSubsystem.locationTracking);
          await loc.startTracking();
          state.markReady(DriverStartupSubsystem.locationTracking);
          perf.markLocationReady();
        }
      } else if (loc.isTracking) {
        await loc.stopTracking();
        state.markRunning(DriverStartupSubsystem.locationTracking);
      }
    } catch (e) {
      // Permission denied / GPS unavailable: surfaced honestly, retried when
      // the driver toggles online again (DriverHomeBloc calls this too).
      debugPrint('[driver-startup] location sync failed: $e');
      state.markFailed(DriverStartupSubsystem.locationTracking);
    }
  }

  // ==========================================================================
  // DEFAULT DEFERRED STEPS (production wiring)
  // ==========================================================================

  List<DriverDeferredStartupStep> _defaultSteps() {
    return [
      // 1. Provisional session hydration from the pre-opened auth box. The
      //    definitive validation is AuthBloc's CheckAuthStatus round-trip
      //    (which then calls onAuthenticated via the splash/router hook).
      DriverDeferredStartupStep(
        subsystem: DriverStartupSubsystem.sessionHydration,
        body: () async {
          final authenticated =
              await getIt<AuthRepository>().isAuthenticated();
          if (authenticated) {
            state.markSessionRestored();
          } else {
            state.markSignedOut();
          }
        },
      ),
      // 2. Secondary boxes used by home/settings screens — opened off the
      //    first-frame path so cold storage I/O never delays the shell.
      DriverDeferredStartupStep(
        subsystem: DriverStartupSubsystem.tripRecovery,
        body: () async {
          await Hive.openBox('driver_cache');
          await Hive.openBox('driver_settings');
          // Cached availability: provisional marker only (freshness badge in
          // the home shell until the server echo confirms it).
          final settings = Hive.box('driver_settings');
          if (settings.get('availability_online') != null) {
            state.markAvailabilityProvisional();
          }
          // Authoritative active-trip recovery (own retry budget inside).
          await recoverActiveTrip();
        },
      ),
    ];
  }

  // ==========================================================================
  // LIFECYCLE HOOKS
  // ==========================================================================

  /// Logout hook: drop timers/subscriptions and reset readiness so a fresh
  /// login re-proves every subsystem (never inherits stale readiness).
  Future<void> reset() async {
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    await _wsStateSub?.cancel();
    _wsStateSub = null;
    await _ackSub?.cancel();
    _ackSub = null;
    _ackedTopics.clear();
    _dispatchWired = false;
    _tripRecoveryDone = false;
    // Re-arm Stage B so a fresh login session can run deferred init again
    // (parity with the consumer coordinator's reset semantics).
    _stageBStarted = false;
    state.reset();
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _wsStateSub?.cancel();
    _ackSub?.cancel();
  }
}

/// One unit of Stage-B work with the phase it gates.
@immutable
class DriverDeferredStartupStep {
  const DriverDeferredStartupStep({
    required this.subsystem,
    required this.body,
  });

  final DriverStartupSubsystem subsystem;
  final Future<void> Function() body;
}

// ============================================================================
// PROCESS-LEVEL ACCESSOR
// ============================================================================
//
// main() installs the coordinator before runApp so AuthBloc, the router and
// integration tests reach the same instance/state. Tests that construct their
// own coordinator never touch this global.
DriverStartupCoordinator? _currentCoordinator;

DriverStartupCoordinator get currentDriverStartupCoordinator {
  final c = _currentCoordinator;
  if (c == null) {
    throw StateError(
      'DriverStartupCoordinator not installed — main() must run '
      'installDriverStartupCoordinator() before any widget resolves it.',
    );
  }
  return c;
}

DriverStartupStateNotifier get driverStartupState =>
    currentDriverStartupCoordinator.state;

bool get hasDriverStartupCoordinator => _currentCoordinator != null;

void installDriverStartupCoordinator(DriverStartupCoordinator? coordinator) {
  _currentCoordinator = coordinator;
}
