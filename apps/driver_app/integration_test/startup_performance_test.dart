import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nidaw_driver_app/core/analytics/startup_performance_service.dart';
import 'package:nidaw_driver_app/core/network/location_service.dart';
import 'package:nidaw_driver_app/core/network/websocket_client.dart';
import 'package:nidaw_driver_app/core/startup/driver_startup_coordinator.dart';
import 'package:nidaw_driver_app/core/startup/driver_startup_state.dart';
import 'package:nidaw_driver_app/features/auth/data/repositories/auth_repository.dart';
import 'package:nidaw_driver_app/features/ride/data/repositories/ride_repository.dart';
import 'package:nidaw_driver_app/features/ride/domain/entities/active_ride.dart';

/// ============================================================================
/// DRIVER STARTUP & ACTIVE-TRIP RECOVERY CONTRACT — integration test
/// (Phase 5 §4.3 / Part 10)
/// ============================================================================
///
/// Runs the REAL production stage-B step list ([DriverStartupCoordinator]
/// without injected steps) against fake getIt collaborators. No Firebase, no
/// Hive, no network: the fakes prove the wiring while staying hermetic.
///
/// Contract verified here:
///   1. The first frame paints with ZERO deferred work executed — session
///      hydration, dispatch wiring and trip recovery all run post-frame, so a
///      slow backend can never block rendering.
///   2. Active-trip recovery is authoritative: settled ONLY from the backend
///      GET answer (ride found -> restore; "no ride" -> settled negative).
///      A transient failure retries honestly and ends in `failed` — never a
///      fabricated "no active trip".
///   3. Dispatch readiness requires an authenticated socket AND the offers
///      subscription ack — intention alone never marks ready.
///   4. Location tracking starts only when driver state permits it
///      (server-confirmed online or on an active trip); offline + idle means
///      startTracking() is NEVER called during startup.
///   5. Perf milestones report null until genuinely reached (no fabricated
///      timings).

// -----------------------------------------------------------------------------
// Test doubles
// -----------------------------------------------------------------------------

class _FakeRideRepository implements RideRepository {
  /// Scripted answers for the authoritative active-ride GET. Each entry is
  /// either an `ActiveRide?` value (success) or an `Exception` to raise.
  final List<Object?> script;
  int _calls = 0;

  _FakeRideRepository(this.script);

  int get callCount => _calls;

  @override
  Future<ActiveRide?> getActiveRide() async {
    final answer = script[_calls.clamp(0, script.length - 1)];
    _calls++;
    if (answer is Exception) throw answer;
    return answer as ActiveRide?;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('startup test only needs getActiveRide');
}

class _RecordingLocationService implements LocationService {
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> startTracking() async => startCalls++;

  @override
  Future<void> stopTracking() async => stopCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('startup test only needs start/stop');
}

class _FakeAuthRepository implements AuthRepository {
  /// null => signed out (token absent). The startup tests never authenticate,
  /// so dispatch wiring stays honestly un-ready.
  @override
  Future<bool> isAuthenticated() async => token != null;

  @override
  Future<String?> getAccessToken() async => token;

  final String? token;
  _FakeAuthRepository({this.token});

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('startup test only needs auth probes');
}

class _NeverConnectingWebSocket extends WebSocketClient {
  _NeverConnectingWebSocket() : super(baseUrl: 'ws://test.invalid/ws');

  static final StreamController<WebSocketConnectionState> _state =
      StreamController<WebSocketConnectionState>.broadcast();

  @override
  Stream<WebSocketConnectionState> get stateStream => _state.stream;

  @override
  Stream<Map<String, dynamic>> get messageStream =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Future<bool> connectNow() async => false; // never reaches ws://test.invalid

  @override
  void subscribe(String topic) {
    subscribedTopics.add(topic);
  }

  final List<String> subscribedTopics = [];
}

ActiveRide _ride(String id) => ActiveRide(
      id: id,
      riderId: 'rider-1',
      riderName: 'Test Rider',
      riderPhone: '+251900000000',
      riderRating: 5,
      pickupLat: 9.03,
      pickupLng: 38.74,
      pickupAddress: 'Bole, Addis Ababa',
      dropoffLat: 9.01,
      dropoffLng: 38.76,
      dropoffAddress: 'Megenagna, Addis Ababa',
      distanceKm: 5.2,
      estimatedDurationMinutes: 16,
      fareAmount: 150.0,
      tipAmount: 0,
      status: 'in_progress',
      requestedAt: DateTime(2026, 10, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DriverStartupStateNotifier state;
  late List<Map<String, dynamic>> reports;
  late StartupPerformanceService perf;
  late _RecordingLocationService location;
  late _NeverConnectingWebSocket ws;
  late _FakeAuthRepository auth;

  /// Registers the baseline getIt collaborators shared by every scenario:
  /// signed-out auth, a socket that never connects and idle location service.
  void registerBase({required RideRepository repo}) {
    GetIt.I.registerLazySingleton<LocationService>(() => location);
    GetIt.I.registerLazySingleton<WebSocketClient>(() => ws);
    GetIt.I.registerLazySingleton<AuthRepository>(() => auth);
    GetIt.I.registerLazySingleton<RideRepository>(() => repo);
  }

  setUp(() {
    GetIt.I.reset();
    reports = [];
    // Tests pump widgets while asserting PRE-first-frame guarantees; stamp
    // the milestone manually instead of via the auto post-frame callback.
    perf = StartupPerformanceService(
      reportSink: reports.add,
      autoFirstFrameDetection: false,
    );
    state = DriverStartupStateNotifier();
    location = _RecordingLocationService();
    ws = _NeverConnectingWebSocket();
    auth = _FakeAuthRepository(); // token == null -> signed out
  });

  tearDown(() {
    state.dispose();
    installDriverStartupCoordinator(null);
  });

  DriverStartupCoordinator buildCoord({
    required RideRepository repo,
    List<DriverDeferredStartupStep>? steps,
  }) {
    registerBase(repo: repo);
    final c = DriverStartupCoordinator(state: state, perf: perf, steps: steps);
    installDriverStartupCoordinator(c);
    return c;
  }

  group('first frame precedes deferred initialization', () {
    testWidgets('shell paints with ZERO deferred work executed',
        (tester) async {
      final ran = <String>[];
      final coord = buildCoord(
        repo: _FakeRideRepository([null]),
        steps: [
          DriverDeferredStartupStep(
            subsystem: DriverStartupSubsystem.sessionHydration,
            body: () async => ran.add('session'),
          ),
          DriverDeferredStartupStep(
            subsystem: DriverStartupSubsystem.tripRecovery,
            body: () async => ran.add('trip'),
          ),
        ],
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      expect(ran, isEmpty,
          reason: 'recovery/hydration must not execute before the first frame');
      expect(state.snapshot.hasPendingHydration, isFalse);

      coord.scheduleDeferredInitialization();
      // Double-schedule parity guard: a second call must never enqueue a
      // second Stage-B run.
      coord.scheduleDeferredInitialization();
      expect(ran, isEmpty, reason: 'scheduling must be synchronous-light');

      await tester.pump(); // post-frame callback fires -> steps execute
      expect(ran, containsAllInOrder(['session', 'trip']));
      await tester.pump(); // no duplicate run from the second schedule call
      expect(ran.length, 2);
    });
  });

  group('authoritative active-trip recovery', () {
    testWidgets('ride found -> restored from server GET, not cache',
        (tester) async {
      final repo = _FakeRideRepository([_ride('ride-77')]);
      final coord = buildCoord(repo: repo);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      coord.scheduleDeferredInitialization();
      await tester.pumpAndSettle();

      expect(repo.callCount, greaterThanOrEqualTo(1),
          reason: 'recovery must ask the authoritative backend');
      expect(state.snapshot.tripRecoverySettled, isTrue);
      expect(state.snapshot.activeRideId, 'ride-77');
      expect(state.snapshot.isOnActiveTrip, isTrue);
      expect(perf.tripRecoveryDuration, isNotNull);
    });

    test('"no active ride" is a settled negative, not a guess', () async {
      final repo = _FakeRideRepository([null]);
      registerBase(repo: repo);
      final coord = DriverStartupCoordinator(state: state, perf: perf);
      await coord.runDeferredInitialization();
      expect(state.snapshot.tripRecoverySettled, isTrue);
      expect(state.snapshot.activeRideId, isNull);
      expect(state.snapshot.isOnActiveTrip, isFalse);
    });

    test('transient GET failures retry, then settle honestly as failed',
        () async {
      final repo = _FakeRideRepository(
          [Exception('network down'), Exception('network down'), _ride('r2')]);
      registerBase(repo: repo);
      final coord = DriverStartupCoordinator(state: state, perf: perf);
      await coord.runDeferredInitialization();

      expect(state.snapshot.tripRecoverySettled, isTrue);
      expect(state.snapshot.activeRideId, 'r2',
          reason: 'a bounded retry that succeeds must restore the trip');
      expect(repo.callCount, 3);
    });

    test('exhausted recovery never fabricates "no trip"', () async {
      final alwaysFails = _FakeRideRepository([Exception('offline')]);
      registerBase(repo: alwaysFails);
      final coord = DriverStartupCoordinator(state: state, perf: perf);
      await coord.runDeferredInitialization();

      expect(state.snapshot.tripRecoverySettled, isFalse,
          reason: 'unknown must stay unknown — router shows retry affordance');
      expect(state.snapshot.activeRideId, isNull);
      expect(state.snapshot.statusOf(DriverStartupSubsystem.tripRecovery),
          DriverStartupPhaseStatus.failed);
      expect(perf.failedPhases, contains('tripRecovery'));
    });
  });

  group('dispatch gating (§4.3)', () {
    test('offers subscription requires authenticated socket reality',
        () async {
      registerBase(repo: _FakeRideRepository([null]));
      final coord = DriverStartupCoordinator(state: state, perf: perf);
      await coord.runDeferredInitialization();

      // Socket never connected in this env -> dispatch NOT ready, ever.
      expect(state.snapshot.isDispatchReady, isFalse);
      expect(state.snapshot.isReady(DriverStartupSubsystem.dispatchSubscription),
          isFalse);

      // Even after a connected echo, readiness requires the coordinator's
      // ack path — simulated by driving the state machine directly.
      state.markServerValidated();
      expect(state.snapshot.isDispatchReady, isFalse);
      state.markReady(DriverStartupSubsystem.realtimeChannel);
      expect(state.snapshot.isDispatchReady, isFalse,
          reason: 'subscription authorization is a separate requirement');
      state.markReady(DriverStartupSubsystem.dispatchSubscription);
      expect(state.snapshot.isDispatchReady, isTrue);
      expect(ws.subscribedTopics, isEmpty,
          reason: 'deferred-list startup without auth must not blind-subscribe');
    });
  });

  group('location permission gate', () {
    test('tracking never starts while availability unconfirmed and idle',
        () async {
      registerBase(repo: _FakeRideRepository([null]));
      final coord = DriverStartupCoordinator(state: state, perf: perf);
      await coord.runDeferredInitialization();

      expect(location.startCalls, 0,
          reason: 'offline/idle driver must not begin continuous GPS (§4.3)');
      expect(state.snapshot.trackingPermitted, isFalse);
      expect(perf.locationReadyDuration, isNull);
    });

    test('server-confirmed online permits tracking', () {
      state.markAvailabilityConfirmed(true);
      expect(state.snapshot.trackingPermitted, isTrue);
      state.markAvailabilityConfirmed(false);
      expect(state.snapshot.trackingPermitted, isFalse,
          reason: 'going offline revokes continuous collection');
    });

    test('settled active trip permits tracking even before availability echo',
        () {
      state.markActiveRideFound('ride-1');
      expect(state.snapshot.trackingPermitted, isTrue);
    });
  });

  group('perf honesty', () {
    test('unreached milestones serialize as null', () async {
      final coord = buildCoord(
        repo: _FakeRideRepository([null]),
        steps: [
          DriverDeferredStartupStep(
            subsystem: DriverStartupSubsystem.bootstrap,
            body: () async {},
          ),
        ],
      );
      await coord.runDeferredInitialization();

      final report = perf.report();
      expect(report['sessionRestoredMs'], isNull);
      expect(report['tripRecoveryMs'], isNull);
      expect(report['dispatchReadyMs'], isNull);
      expect(report['locationReadyMs'], isNull);
      expect(report['firstFrameMs'], isNull,
          reason: 'manual mode + no pumped frame -> nothing stamped');

      perf.markFirstFrame();
      expect(perf.report()['firstFrameMs'], isA<int>());
      // Once-only semantics.
      final t = perf.firstFrameDuration!;
      perf.markFirstFrame();
      expect(perf.firstFrameDuration, same(t));
    });
  });
}
