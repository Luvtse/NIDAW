import 'package:flutter/foundation.dart';

/// ============================================================================
/// DRIVER STARTUP STATE (Phase 5, §4.3)
/// ============================================================================
///
/// Honest, in-memory readiness model for the driver app's staged startup:
///
///   Stage A (pre-frame): binding + Hive + ONLY the 'driver_auth' box +
///     synchronous lazy DI registration. Nothing else may block runApp().
///
///   Stage B (post-frame): authenticated WebSocket connect + offer-subscription
///     authorization, active-trip recovery from the authoritative backend,
///     availability restore (provisional until server-confirmed), location
///     tracking start (only when permissions AND driver state permit it).
///
///   Lazy: earnings / profile / documents repositories resolve on first screen
///     access — they are never touched during startup.
///
/// Anti-fabrication rules encoded here:
///  - A cached session/availability is PROVISIONAL until [markServerValidated]
///    or [markAvailabilityConfirmed]; the UI must show a freshness indicator
///    and dispatch actions must be disabled while provisional.
///  - A restored ride is only actionable after [markTripRecoverySettled]
///    (server answered — with an active trip, with none, or explicitly failed;
///    "still asking" is not settled).
///  - Offers received over the socket are only actionable once
///    [isDispatchReady] is true (authenticated socket + subscription ack);
///    a cached offer is never presented as newly available (§4.3 last rule).
enum DriverStartupSubsystem {
  /// Binding, Hive init, 'driver_auth' box, DI registration.
  bootstrap,

  /// Local token/profile read — provisional auth until the server agrees.
  sessionHydration,

  /// Authenticated WebSocket connected (token-scoped subprotocol).
  realtimeChannel,

  /// `driver:offers` subscription authorized by the server.
  dispatchSubscription,

  /// Authoritative GET-active-ride round-trip completed.
  tripRecovery,

  /// Continuous location collection actually running (permission granted and
  /// driver state permits tracking).
  locationTracking,
}

enum DriverStartupPhaseStatus { pending, running, ready, failed }

class DriverStartupException implements Exception {
  final String message;
  const DriverStartupException(this.message);

  @override
  String toString() => 'DriverStartupException($message)';
}

/// Immutable snapshot for widgets, perf instrumentation and tests.
class DriverStartupSnapshot {
  final Map<DriverStartupSubsystem, DriverStartupPhaseStatus> phases;

  /// Local credentials were read from Hive. Does NOT mean the server accepts
  /// them — see [serverValidated].
  final bool sessionRestored;

  /// The backend confirmed the restored token (AuthBloc round-trip).
  final bool serverValidated;

  /// Last-known availability restored from local storage; provisional until
  /// [availabilityConfirmed] by the server.
  final bool availabilityProvisional;

  /// Server echo of the driver's online/offline state.
  final bool availabilityConfirmed;

  /// Trip-recovery query finished. [activeRideId] is the settled answer:
  /// non-null = restore that ride, null = server said there is no active ride.
  final bool tripRecoverySettled;
  final String? activeRideId;

  const DriverStartupSnapshot({
    required this.phases,
    required this.sessionRestored,
    required this.serverValidated,
    required this.availabilityProvisional,
    required this.availabilityConfirmed,
    required this.availabilityOnline,
    required this.tripRecoverySettled,
    this.activeRideId,
  });

  factory DriverStartupSnapshot.initial() => const DriverStartupSnapshot(
        phases: {},
        sessionRestored: false,
        serverValidated: false,
        availabilityProvisional: false,
        availabilityConfirmed: false,
        availabilityOnline: false,
        tripRecoverySettled: false,
      );

  DriverStartupPhaseStatus statusOf(DriverStartupSubsystem s) =>
      phases[s] ?? DriverStartupPhaseStatus.pending;

  bool isReady(DriverStartupSubsystem s) =>
      statusOf(s) == DriverStartupPhaseStatus.ready;

  /// The router may render auth-gated screens only once local hydration has a
  /// definitive result (validated session OR honest signed-out). Never shows
  /// an authenticated screen on unverified cache.
  bool get canShowAuthenticatedUi => sessionRestored || !hasPendingHydration;

  /// Hydration still in flight — splash/loading state, not login, not home.
  bool get hasPendingHydration =>
      statusOf(DriverStartupSubsystem.sessionHydration) ==
          DriverStartupPhaseStatus.running ||
      statusOf(DriverStartupSubsystem.sessionHydration) ==
          DriverStartupPhaseStatus.pending;

  /// Dispatch actions (accept offer, go online/offline against the server)
  /// require an authenticated socket AND an authorized offers subscription.
  bool get isDispatchReady =>
      serverValidated &&
      isReady(DriverStartupSubsystem.realtimeChannel) &&
      isReady(DriverStartupSubsystem.dispatchSubscription);

  /// Continuous GPS collection requires an explicit grant from the startup
  /// state machine: the server confirmed the driver is currently ONLINE, or an
  /// ACTIVE TRIP was recovered from the authoritative backend. Going offline
  /// while idle revokes the grant immediately (battery + §4.3); an
  /// in-progress trip keeps collection alive even when the availability toggle
  /// reads offline, because riders depend on live driver position for safety.
  bool get trackingPermitted => availabilityOnline || isOnActiveTrip;

  /// Whether the LAST server-confirmed availability echo said ONLINE. Distinct
  /// from [availabilityConfirmed], which only records that a definitive server
  /// answer has arrived (online OR offline).
  final bool availabilityOnline;

  bool get isOnActiveTrip =>
      tripRecoverySettled && (activeRideId?.isNotEmpty ?? false);

  List<DriverStartupSubsystem> get failedSubsystems => phases.entries
      .where((e) => e.value == DriverStartupPhaseStatus.failed)
      .map((e) => e.key)
      .toList(growable: false);

  DriverStartupSnapshot _copyWith({
    Map<DriverStartupSubsystem, DriverStartupPhaseStatus>? phases,
    bool? sessionRestored,
    bool? serverValidated,
    bool? availabilityProvisional,
    bool? availabilityConfirmed,
    bool? availabilityOnline,
    bool? tripRecoverySettled,
    String? activeRideId,
    bool clearActiveRide = false,
  }) {
    return DriverStartupSnapshot(
      phases: phases ?? this.phases,
      sessionRestored: sessionRestored ?? this.sessionRestored,
      serverValidated: serverValidated ?? this.serverValidated,
      availabilityProvisional:
          availabilityProvisional ?? this.availabilityProvisional,
      availabilityConfirmed:
          availabilityConfirmed ?? this.availabilityConfirmed,
      availabilityOnline: availabilityOnline ?? this.availabilityOnline,
      tripRecoverySettled: tripRecoverySettled ?? this.tripRecoverySettled,
      activeRideId: clearActiveRide
          ? null
          : (activeRideId ?? this.activeRideId),
    );
  }
}

/// Controlled transitions on top of [DriverStartupSnapshot]. Single source of
/// truth for the driver startup contract; lives in memory only.
class DriverStartupStateNotifier extends ChangeNotifier {
  DriverStartupSnapshot _snapshot = DriverStartupSnapshot.initial();

  DriverStartupSnapshot get snapshot => _snapshot;

  void _setStatus(
      DriverStartupSubsystem s, DriverStartupPhaseStatus status) {
    final phases = Map<DriverStartupSubsystem, DriverStartupPhaseStatus>.of(
        _snapshot.phases)..[s] = status;
    _emit(_snapshot._copyWith(phases: phases));
  }

  void markRunning(DriverStartupSubsystem s) =>
      _setStatus(s, DriverStartupPhaseStatus.running);

  void markReady(DriverStartupSubsystem s) =>
      _setStatus(s, DriverStartupPhaseStatus.ready);

  void markFailed(DriverStartupSubsystem s) =>
      _setStatus(s, DriverStartupPhaseStatus.failed);

  // ---- Session ------------------------------------------------------------

  /// Local token found in Hive — provisional. Router must keep showing the
  /// loading shell until the server validates (or rejects) it.
  void markSessionRestored() {
    _setStatus(DriverStartupSubsystem.sessionHydration,
        DriverStartupPhaseStatus.running);
    _emit(_snapshot._copyWith(sessionRestored: true));
  }

  void markServerValidated() {
    _setStatus(DriverStartupSubsystem.sessionHydration,
        DriverStartupPhaseStatus.ready);
    _emit(_snapshot._copyWith(
      sessionRestored: true,
      serverValidated: true,
    ));
  }

  /// Definitive signed-out (no token, or server rejected it): honest failure
  /// of hydration so the router routes to /login without waiting forever.
  void markSignedOut() {
    _setStatus(DriverStartupSubsystem.sessionHydration,
        DriverStartupPhaseStatus.ready);
    _emit(_snapshot._copyWith(
      sessionRestored: false,
      serverValidated: false,
    ));
  }

  // ---- Availability ---------------------------------------------------------

  /// Cached online/offline toggle read locally — display with a "stale"
  /// indicator; do not treat as server truth.
  void markAvailabilityProvisional() =>
      _emit(_snapshot._copyWith(availabilityProvisional: true));

  void markAvailabilityConfirmed(bool online) {
    // Online grants tracking permission; offline revokes it UNLESS a settled
    // active trip still requires live position for rider safety (coordinator
    // will stop continuous collection — battery + §4.3 "only when permitted").
    // Read the pre-emit snapshot: `isOnActiveTrip` must reflect the settled
    // trip-recovery answer, not availability flags being written right now.
    final keepsTracking = !online && _snapshot.isOnActiveTrip;
    _emit(_snapshot._copyWith(
      availabilityProvisional: true,
      availabilityConfirmed: true,
      availabilityOnline: online,
    ));
    if (!keepsTracking &&
        _snapshot.isReady(DriverStartupSubsystem.locationTracking)) {
      // Offline while idle: revoke continuous collection immediately (§4.3).
      _setStatus(DriverStartupSubsystem.locationTracking,
          DriverStartupPhaseStatus.pending);
    }
  }

  // ---- Trip recovery --------------------------------------------------------

  void markTripRecoveryStarted() =>
      _setStatus(DriverStartupSubsystem.tripRecovery,
          DriverStartupPhaseStatus.running);

  /// Server answered with an active ride — restore its route immediately.
  void markActiveRideFound(String rideId) {
    _setStatus(DriverStartupSubsystem.tripRecovery,
        DriverStartupPhaseStatus.ready);
    _emit(_snapshot._copyWith(
      tripRecoverySettled: true,
      activeRideId: rideId,
    ));
  }

  /// Server answered "no active ride" — settled negative, safe for home shell.
  void markNoActiveRide() {
    _setStatus(DriverStartupSubsystem.tripRecovery,
        DriverStartupPhaseStatus.ready);
    _emit(_snapshot._copyWith(
      tripRecoverySettled: true,
      clearActiveRide: true,
    ));
  }

  /// Recovery exhausted without an answer: stay honest — the driver sees a
  /// retry affordance, never a fabricated "no trip" state.
  void markTripRecoveryFailed() =>
      _setStatus(DriverStartupSubsystem.tripRecovery,
          DriverStartupPhaseStatus.failed);

  /// Ride ended (locally observed completion): clear the settled trip.
  void clearActiveTrip() =>
      _emit(_snapshot._copyWith(clearActiveRide: true));

  // ---- Reset ----------------------------------------------------------------

  /// Logout / hot restart: drop all readiness so a fresh login re-proves
  /// every subsystem instead of inheriting stale state.
  void reset() {
    _snapshot = DriverStartupSnapshot.initial();
    notifyListeners();
  }

  void _emit(DriverStartupSnapshot next) {
    _snapshot = next;
    notifyListeners();
  }
}
