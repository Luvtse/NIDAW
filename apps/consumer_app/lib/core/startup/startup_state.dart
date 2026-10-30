import 'dart:async';

/// ============================================================================
/// STARTUP STATE MACHINE (NIDAW Phase 5 — render first, initialize second)
/// ============================================================================
///
/// The consumer app renders its lightweight shell *before* nonessential
/// services (Firebase/FCM, geocoding cache, feature flags, offline sync,
/// WebSocket) finish initializing. This file is the single observable record
/// of what has been initialized, what failed, and whether it is safe to show
/// authenticated surfaces yet.
///
/// Invariants enforced here (mirrored by startup_state_test.dart):
///  - A subsystem can only move forward: pending -> running -> ready | failed.
///    Re-advancing a `ready` subsystem is an explicit no-op so initialization
///    steps stay idempotent under retry/recovery.
///  - Failures never fabricate readiness. [StartupSnapshot.canShowAuthenticatedUi]
///    stays false until authentication hydration actually completed, and
///    [StartupSnapshot.isBookingReady] requires live (server-validated) state,
///    never cached-only state.
///  - A failed subsystem may be retried (`failed -> running`) — recovery is a
///    first-class transition, matching the deferred-initialization contract.
///  - Cached data is provisional: [StartupSnapshot.cacheHydrated] permits
///    rendering a cached home shell with freshness indicators, but never a
///    booking action or a stale quote treated as confirmation.

enum StartupSubsystem {
  /// Minimum synchronous configuration (locale notifier, error handlers).
  bootstrap,

  /// Hive boxes + last-known session/consent/locale hydration.
  sessionHydration,

  /// Offline service (connectivity stream + pending-operation queue).
  offlineService,

  /// Geocoding Hive cache open (reads are cache-first afterwards).
  geocodingCache,

  /// Bundled feature-flag file load.
  featureFlags,

  /// Firebase + FCM permission/token bootstrap (never first-frame critical).
  pushNotifications,

  /// Authenticated WebSocket connection (started by AuthBloc on login).
  realtimeChannel,
}

enum StartupPhaseStatus { pending, running, ready, failed }

class StartupPhaseException implements Exception {
  final String message;
  const StartupPhaseException(this.message);

  @override
  String toString() => 'StartupPhaseException($message)';
}

/// Immutable snapshot handed to listeners (widgets, perf instrumentation,
/// integration tests). Cheap to copy; safe to compare in tests.
class StartupSnapshot {
  final Map<StartupSubsystem, StartupPhaseStatus> phases;

  /// True once local session hydration completed — the router may render the
  /// auth-gated redirect tree (login/onboarding/home) from validated state.
  final bool sessionHydrated;

  /// True once cached content (session summary, map camera, recent searches)
  /// was read. Renders the cached home shell with freshness indicators.
  final bool cacheHydrated;

  /// True once the backend confirmed the restored session. Provisional cached
  /// state must never be presented as server-validated before this flips.
  final bool serverValidated;

  /// True when connectivity checks ran (online or offline — either is a
  /// settled answer; unknown blocks nothing, it just isn't claimed).
  final bool connectivityKnown;

  const StartupSnapshot({
    required this.phases,
    required this.sessionHydrated,
    required this.cacheHydrated,
    required this.serverValidated,
    required this.connectivityKnown,
  });

  factory StartupSnapshot.initial() => const StartupSnapshot(
        phases: {},
        sessionHydrated: false,
        cacheHydrated: false,
        serverValidated: false,
        connectivityKnown: false,
      );

  StartupPhaseStatus statusOf(StartupSubsystem s) =>
      phases[s] ?? StartupPhaseStatus.pending;

  bool isReady(StartupSubsystem s) =>
      statusOf(s) == StartupPhaseStatus.ready;

  /// Live booking actions (request/track/confirm) require the authoritative
  /// path: hydrated session that the server validated, plus the network-aware
  /// offline service. Cache alone NEVER enables booking.
  bool get isBookingReady =>
      sessionHydrated &&
      serverValidated &&
      isReady(StartupSubsystem.offlineService);

  /// The router may expose authenticated / trip-restoration screens only after
  /// local session validation succeeded (or definitively failed -> login).
  bool get canShowAuthenticatedUi => sessionHydrated;

  /// Any subsystem currently failed — surfaced honestly in UI/perf logs
  /// rather than silently swallowed.
  List<StartupSubsystem> get failedSubsystems => phases.entries
      .where((e) => e.value == StartupPhaseStatus.failed)
      .map((e) => e.key)
      .toList(growable: false);

  StartupSnapshot _copyWith({
    Map<StartupSubsystem, StartupPhaseStatus>? phases,
    bool? sessionHydrated,
    bool? cacheHydrated,
    bool? serverValidated,
    bool? connectivityKnown,
  }) {
    return StartupSnapshot(
      phases: phases ?? this.phases,
      sessionHydrated: sessionHydrated ?? this.sessionHydrated,
      cacheHydrated: cacheHydrated ?? this.cacheHydrated,
      serverValidated: serverValidated ?? this.serverValidated,
      connectivityKnown: connectivityKnown ?? this.connectivityKnown,
    );
  }
}

/// Notifier exposing the immutable [StartupSnapshot] plus controlled
/// transitions. Lives entirely in memory — it caches nothing sensitive and
/// deliberately resets per launch/logout: readiness is proven every session.
class StartupStateNotifier extends ChangeNotifier {
  StartupSnapshot _snapshot = StartupSnapshot.initial();

  StartupSnapshot get snapshot => _snapshot;

  /// Completes once [predicate] holds against the current snapshot. Polls on
  /// notification boundaries with a fallback timer so callers can apply their
  /// own timeouts. Never fabricates success: on timeout the future simply
  /// resolves and the caller re-checks [snapshot].
  Future<void> waitUntil(
    bool Function(StartupSnapshot snapshot) predicate, {
    Duration pollInterval = const Duration(milliseconds: 32),
  }) async {
    while (!predicate(_snapshot)) {
      await _nextChangeOrTick(pollInterval);
    }
  }

  Future<void> _nextChangeOrTick(Duration interval) {
    final completer = Completer<void>();
    late void Function() listener;
    listener = () {
      if (!completer.isCompleted) completer.complete();
    };
    addListener(listener);
    unawaited(Future<void>.delayed(interval, () {
      if (!completer.isCompleted) completer.complete();
    }));
    return completer.future.whenComplete(() => removeListener(listener));
  }

  // ==========================================================================
  // CONTROLLED TRANSITIONS
  // ==========================================================================

  void markRunning(StartupSubsystem s) =>
      _setStatus(s, StartupPhaseStatus.running);

  void markReady(StartupSubsystem s) => _setStatus(s, StartupPhaseStatus.ready);

  void markFailed(StartupSubsystem s) =>
      _setStatus(s, StartupPhaseStatus.failed);

  void _setStatus(StartupSubsystem s, StartupPhaseStatus status) {
    final current = _snapshot.statusOf(s);
    if (current == status) return;
    // `ready` is terminal for a launch: repeated initialization steps are
    // idempotent no-ops (offline init, FCM init and WS reconnect all fire
    // more than once across retries and login cycles).
    if (current == StartupPhaseStatus.ready) return;
    final valid = _isLegalTransition(current, status);
    if (!valid) return;
    _snapshot = _snapshot._copyWith(
      phases: {..._snapshot.phases, s: status},
    );
    notifyListeners();
  }

  static bool _isLegalTransition(
      StartupPhaseStatus from, StartupPhaseStatus to) {
    switch (from) {
      case StartupPhaseStatus.pending:
        return to == StartupPhaseStatus.running || to == StartupPhaseStatus.ready;
      case StartupPhaseStatus.running:
        return to == StartupPhaseStatus.ready || to == StartupPhaseStatus.failed;
      case StartupPhaseStatus.failed:
        // Recovery path: a failed subsystem can be retried.
        return to == StartupPhaseStatus.running;
      case StartupPhaseStatus.ready:
        return false;
    }
  }

  /// Session hydration finished successfully (tokens/profile read locally).
  /// Does NOT imply server validation.
  void completeSessionHydration({required bool cacheRead}) {
    markReady(StartupSubsystem.sessionHydration);
    _snapshot = _snapshot._copyWith(
      sessionHydrated: true,
      cacheHydrated: cacheRead || _snapshot.cacheHydrated,
    );
    notifyListeners();
  }

  /// Hydration itself failed (corrupt store): honest failure, but routing to a
  /// signed-out state IS a safe, settled outcome.
  void failSessionHydration() {
    markFailed(StartupSubsystem.sessionHydration);
    _snapshot = _snapshot._copyWith(sessionHydrated: true);
    notifyListeners();
  }

  void markCacheHydrated() {
    if (_snapshot.cacheHydrated) return;
    _snapshot = _snapshot._copyWith(cacheHydrated: true);
    notifyListeners();
  }

  /// The backend accepted the restored token — cached state is now canonical.
  void markServerValidated() {
    if (_snapshot.serverValidated) return;
    _snapshot = _snapshot._copyWith(serverValidated: true);
    notifyListeners();
  }

  void markConnectivityKnown() {
    if (_snapshot.connectivityKnown) return;
    _snapshot = _snapshot._copyWith(connectivityKnown: true);
    notifyListeners();
  }

  void reset() {
    _snapshot = StartupSnapshot.initial();
    notifyListeners();
  }
}
