import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nidaw_app/core/analytics/startup_performance_service.dart';
import 'package:nidaw_app/core/network/websocket_client.dart';
import 'package:nidaw_app/core/offline/offline_service.dart';
import 'package:nidaw_app/core/startup/app_startup_coordinator.dart';
import 'package:nidaw_app/core/startup/startup_state.dart';

/// ============================================================================
/// CONSUMER STARTUP CONTRACT — integration test (Phase 5 / Part 10)
/// ============================================================================
///
/// Exercises the REAL production stage-B step list ([AppStartupCoordinator]
/// without injected steps) against fake service implementations registered in
/// a fresh getIt container, plus a trivial shell widget. No Firebase, no Hive,
/// no network is touched — the fakes prove the wiring while keeping the test
/// hermetic. Contract verified here:
///
///   1. The first frame paints BEFORE any deferred subsystem runs (zero
///      stage-B side effects at paint time — nothing network-dependent can
///      block rendering).
///   2. Deferred stages run only after the post-frame callback fires and mark
///      honest per-subsystem readiness (offline settles even when the device
///      reports offline; cache hydration is claimed only when data exists).
///   3. A failing deferred step degrades honestly (`failed` + recorded in the
///      perf report) and never blocks sibling steps or the UI.
///   4. The map-ready milestone fires ONLY via the live-engine path
///      (perf.markMapReady) and is forwarded into startup state as
///      StartupSubsystem.mapEngine.ready — placeholder frames can never set
///      it, and duplicate notifications are ignored.
///   5. Booking readiness requires server validation — cached state alone
///      never unlocks booking (anti-fabrication invariant).

// -----------------------------------------------------------------------------
// Test doubles for the production stage-B collaborators.
// -----------------------------------------------------------------------------

class _FakeConnectivitySettledOffline extends OfflineService {
  @override
  Future<void> initialize() async {
    // Real impl opens boxes + listens; fake just settles connectivity as an
    // honest OFFLINE answer — offline must not fail startup either.
    if (!_connectivityCompleter.isCompleted) _connectivityCompleter.complete();
  }

  static final Completer<void> _connectivityCompleter = Completer<void>();

  @override
  Future<void> get initialConnectivitySettled => _connectivityCompleter.future;

  @override
  bool hasCachedData(String key) =>
      key == OfflineService.lastRideSummaryKey ? _hasRide : false;

  static bool _hasRide = true;
}

class _FakeWebSocketClient extends WebSocketClient {
  _FakeWebSocketClient() : super(baseUrl: 'ws://test.invalid/ws');

  static final StreamController<WebSocketConnectionState> _state =
      StreamController<WebSocketConnectionState>.broadcast();

  @override
  Stream<WebSocketConnectionState> get stateStream => _state.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StartupStateNotifier state;
  late List<Map<String, dynamic>> reports;
  late StartupPerformanceService perf;

  setUp(() {
    GetIt.I.reset();
    reports = [];
    // autoFirstFrameDetection=false: this file asserts PRE-first-frame
    // behavior while pumping widgets; production keeps the default.
    perf = StartupPerformanceService(
      reportSink: reports.add,
      autoFirstFrameDetection: false,
    );
    state = StartupStateNotifier();

    // Register the fakes the production _defaultSteps() resolves via getIt.
    GetIt.I.registerLazySingleton<OfflineService>(
        () => _FakeConnectivitySettledOffline());
    GetIt.I.registerLazySingleton<WebSocketClient>(
        () => _FakeWebSocketClient());

    // GeocodingCache.open()/FeatureFlagService.load() hit real plugin paths
    // (Hive root / asset bundle), so we short-circuit those two steps by
    // registering their instances up front is NOT possible (steps call the
    // static factories directly). Instead those steps are allowed to fail
    // honestly — asserted below — while everything else completes.
  });

  tearDown(() {
    state.dispose();
    installStartupCoordinator(null);
  });

  AppStartupCoordinator buildCoord({List<DeferredStartupStep>? steps}) {
    final c = AppStartupCoordinator(state: state, perf: perf, steps: steps);
    installStartupCoordinator(c);
    return c;
  }

  group('first frame precedes deferred initialization', () {
    testWidgets('shell paints with ZERO deferred work executed',
        (tester) async {
      final deferredRan = <String>[];
      final coord = buildCoord(steps: [
        DeferredStartupStep(
          subsystem: StartupSubsystem.offlineService,
          body: () async => deferredRan.add('offline'),
        ),
        DeferredStartupStep(
          subsystem: StartupSubsystem.geocodingCache,
          body: () async => deferredRan.add('geocoding'),
        ),
      ]);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      // Frame painted — nothing from stage B may have run yet.
      expect(deferredRan, isEmpty,
          reason: 'deferred init must not execute before the first frame');
      expect(state.snapshot.isReady(StartupSubsystem.offlineService), isFalse);

      // Scheduling itself must be synchronous-light (post-frame only).
      coord.scheduleDeferredInitialization();
      expect(deferredRan, isEmpty);

      await tester.pump(); // post-frame callback fires -> steps execute
      expect(deferredRan, ['offline', 'geocoding']);
      expect(state.snapshot.isReady(StartupSubsystem.offlineService), isTrue);
      expect(state.snapshot.isReady(StartupSubsystem.geocodingCache), isTrue);
    });

    testWidgets('production stage-B list runs against fakes after the frame',
        (tester) async {
      // No injected steps => the REAL _defaultSteps() executes.
      final coord = buildCoord();

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      coord.scheduleDeferredInitialization();
      await tester.pump(); // let every awaited fake step settle

      // mapEngine wiring step completed (registration succeeded synchronously).
      expect(state.snapshot.isReady(StartupSubsystem.mapEngine), isTrue);
      // Offline step settled connectivity (fake answered "offline" honestly).
      expect(state.snapshot.isReady(StartupSubsystem.offlineService), isTrue);
      expect(state.snapshot.connectivityKnown, isTrue);
      // Cached ride summary present -> cacheHydrated marked.
      expect(state.snapshot.cacheHydrated, isTrue);
      // Geocoding/flags/push touch real plugin paths -> they degrade HONESTLY
      // to failed, never crash siblings, and appear in the perf report.
      expect(state.snapshot.statusOf(StartupSubsystem.geocodingCache),
          StartupPhaseStatus.failed);
      expect(perf.failedPhases, contains('geocodingCache'));
      expect(state.snapshot.isReady(StartupSubsystem.featureFlags), isFalse);
      // Push stays non-ready without Firebase — never fabricated.
      expect(state.snapshot.isReady(StartupSubsystem.pushNotifications),
          isFalse);
      // Interactive-shell milestone still fires once Stage B settled.
      expect(perf.interactiveShellDuration, isNotNull);
    });
  });

  group('honest degradation', () {
    testWidgets('failing step marks failed, siblings still complete',
        (tester) async {
      final ran = <String>[];
      final coord = buildCoord(steps: [
        DeferredStartupStep(
          subsystem: StartupSubsystem.featureFlags,
          body: () async {
            ran.add('flags');
            throw TimeoutException('simulated slow asset read');
          },
        ),
        DeferredStartupStep(
          subsystem: StartupSubsystem.offlineService,
          body: () async => ran.add('offline'),
        ),
      ]);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      coord.scheduleDeferredInitialization();
      await tester.pump();

      expect(ran, containsAllInOrder(['flags', 'offline']),
          reason: 'one failing subsystem must never block its siblings');
      expect(
          state.snapshot.statusOf(StartupSubsystem.featureFlags),
          StartupPhaseStatus.failed);
      expect(state.snapshot.isReady(StartupSubsystem.offlineService), isTrue);
      expect(
          state.snapshot.failedSubsystems, contains(StartupSubsystem.featureFlags));
    });

    test('booking readiness requires server validation, never cache alone',
        () async {
      const initial = StartupSnapshot.initial();
      expect(initial.canShowAuthenticatedUi, isFalse);
      expect(initial.isBookingReady, isFalse);

      // Cache-only hydration must NOT unlock booking (anti-fabrication rule).
      state.markCacheHydrated();
      state.markReady(StartupSubsystem.offlineService);
      expect(state.snapshot.cacheHydrated, isTrue);
      expect(state.snapshot.isBookingReady, isFalse,
          reason: 'a cached quote/session is never a booking confirmation');

      state.completeSessionHydration(cacheRead: true);
      expect(state.snapshot.canShowAuthenticatedUi, isTrue);
      expect(state.snapshot.isBookingReady, isFalse,
          reason: 'still needs authoritative server validation');

      state.markServerValidated();
      expect(state.snapshot.isBookingReady, isTrue);
    });
  });

  group('map readiness milestone honesty (§5.1)', () {
    test('milestone null until LIVE engine marks it; forwarded exactly once',
        () async {
      final coord = buildCoord(steps: [
        // Mirror of production step 0 (wiring only, no plugins).
        DeferredStartupStep(
          subsystem: StartupSubsystem.mapEngine,
          body: () async {
            perf.onMapReady = () => state.markReady(StartupSubsystem.mapEngine);
          },
        ),
      ]);
      await coord.runDeferredInitialization();

      // Placeholder painted (or not) — until the real engine mounts, both
      // the perf milestone and the state flag MUST stay unclaimed.
      expect(perf.mapReadyDuration, isNull,
          reason: 'cached/placeholder map must never count as map ready');
      expect(state.snapshot.isReady(StartupSubsystem.mapEngine), isFalse);

      // Simulate the live flutter_map tree's one-time notification.
      perf.markMapReady();
      expect(perf.mapReadyDuration, isNotNull);
      expect(state.snapshot.isReady(StartupSubsystem.mapEngine), isTrue);

      // Duplicate engine notifications must not re-stamp the milestone.
      final first = perf.mapReadyDuration!;
      perf.markMapReady();
      expect(perf.mapReadyDuration, same(first));
    });
  });

  group('realtime channel reflects socket reality, not intention', () {
    test('connected echo marks ready; disconnected stays pending', () async {
      final coord = buildCoord(steps: [
        DeferredStartupStep(
          subsystem: StartupSubsystem.realtimeChannel,
          body: () async {
            final ws = GetIt.I<WebSocketClient>();
            final sub = ws.stateStream.listen((s) {
              switch (s) {
                case WebSocketConnectionState.connected:
                  state.markReady(StartupSubsystem.realtimeChannel);
                case WebSocketConnectionState.connecting:
                  state.markRunning(StartupSubsystem.realtimeChannel);
                case WebSocketConnectionState.error:
                case WebSocketConnectionState.disconnected:
                  break;
              }
            });
            addTearDown(sub.cancel);
          },
        ),
      ]);
      await coord.runDeferredInitialization();

      // Socket waiting for auth is NOT a failure and NOT readiness.
      expect(state.snapshot.isReady(StartupSubsystem.realtimeChannel), isFalse);

      _FakeWebSocketClient._state.add(WebSocketConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      expect(state.snapshot.isReady(StartupSubsystem.realtimeChannel), isTrue);
    });
  });

  group('perf report shape', () {
    test('unmeasured milestones serialize as null, failures are listed',
        () async {
      final coord = buildCoord(steps: [
        DeferredStartupStep(
          subsystem: StartupSubsystem.pushNotifications,
          body: () async => throw StateError('no firebase in test env'),
        ),
      ]);
      await coord.runDeferredInitialization();

      final report = perf.report();
      expect(report['mapReadyMs'], isNull,
          reason: 'never reached — must not fabricate a number');
      expect(report['interactiveShellMs'], isNull,
          reason: 'injected steps skip the interactive-shell milestone');
      expect(report['failedPhases'], contains('pushNotifications'));
    });
  });
}
