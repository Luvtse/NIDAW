import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_driver_app/core/analytics/startup_performance_service.dart';
import 'package:nidaw_driver_app/core/startup/driver_startup_coordinator.dart';
import 'package:nidaw_driver_app/core/startup/driver_startup_state.dart';

/// Phase 5 (§4.3, Part 10) driver startup contract tests.
///
/// Verifies the coordinator's *deferred work* semantics without touching
/// Firebase/Hive/getIt: every stage-B step is injectable via [steps], so we
/// can prove —
///   - a failing deferred subsystem is marked failed and recorded honestly
///     (never silently dropped, never blocks sibling steps),
///   - a successful recovery chain settles tripRecovery ready,
///   - `runDeferredInitialization` before Stage A is a safe no-op (ordering
///     guarantee that keeps cold storage I/O off the first-frame path),
///   - perf milestones are monotonic, once-only and reported null when the
///     milestone was never reached (no fabricated timings).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DriverStartupStateNotifier state;
  late List<Map<String, dynamic>> reports;
  late StartupPerformanceService perf;

  setUp(() {
    state = DriverStartupStateNotifier();
    reports = [];
    perf = StartupPerformanceService(reportSink: reports.add);
  });

  tearDown(() {
    state.dispose();
  });

  DriverStartupCoordinator buildCoord(List<DriverDeferredStartupStep> steps) =>
      DriverStartupCoordinator(state: state, perf: perf, steps: steps);

  group('deferred initialization failure recovery', () {
    test('failing step marks subsystem failed, records it, siblings still run',
        () async {
      var siblingRan = false;
      final coord = buildCoord([
        DriverDeferredStartupStep(
          subsystem: DriverStartupSubsystem.sessionHydration,
          body: () async {
            throw const DriverStartupException('corrupt auth box');
          },
        ),
        DriverDeferredStartupStep(
          subsystem: DriverStartupSubsystem.tripRecovery,
          body: () async {
            siblingRan = true;
            state.markNoActiveRide();
          },
        ),
      ]);

      await coord.runDeferredInitialization();

      expect(
          state.snapshot.statusOf(DriverStartupSubsystem.sessionHydration),
          DriverStartupPhaseStatus.failed);
      expect(siblingRan, isTrue,
          reason: 'one deferred failure must not abort the rest of Stage B');
      expect(state.snapshot.tripRecoverySettled, isTrue);
      expect(perf.failedPhases, contains('sessionHydration'));
    });

    test('step that already settled its subsystem is not overwritten by markFailed',
        () async {
      // Body throws AFTER recording a more specific terminal state — the
      // coordinator must keep the settled outcome, not downgrade to failed.
      final coord = buildCoord([
        DriverDeferredStartupStep(
          subsystem: DriverStartupSubsystem.tripRecovery,
          body: () async {
            state.markNoActiveRide();
            throw StateError('late telemetry error after settle');
          },
        ),
      ]);

      await coord.runDeferredInitialization();

      expect(state.snapshot.tripRecoverySettled, isTrue);
      expect(state.snapshot.statusOf(DriverStartupSubsystem.tripRecovery),
          DriverStartupPhaseStatus.ready);
    });

    test('success chain leaves zero failed phases', () async {
      final coord = buildCoord([
        DriverDeferredStartupStep(
          subsystem: DriverStartupSubsystem.sessionHydration,
          body: () async => state.markSessionRestored(),
        ),
        DriverDeferredStartupStep(
          subsystem: DriverStartupSubsystem.tripRecovery,
          body: () async {
            state.markTripRecoveryStarted();
            state.markActiveRideFound('ride-9');
          },
        ),
      ]);

      await coord.runDeferredInitialization();

      expect(perf.failedPhases, isEmpty);
      expect(state.snapshot.activeRideId, 'ride-9');
      expect(state.snapshot.isOnActiveTrip, isTrue);
    });

    test('running deferred work before Stage A is a safe no-op', () async {
      // Ordering guarantee: scheduleDeferredInitialization refuses to fire
      // until the startup-critical stage completed, so a misordered main()
      // can never sneak Hive I/O onto the first-frame path.
      final coord = buildCoord([
        DriverDeferredStartupStep(
          subsystem: DriverStartupSubsystem.tripRecovery,
          body: () async => state.markNoActiveRide(),
        ),
      ]);
      coord.scheduleDeferredInitialization();
      await pumpEventQueue();
      expect(state.snapshot.tripRecoverySettled, isFalse);
    });
  });

  group('performance instrumentation honesty', () {
    test('unreached milestones report null — never fabricated values', () {
      expect(perf.report()['firstFrameMs'], isNull);
      expect(perf.report()['tripRecoveryMs'], isNull);
      expect(perf.report()['dispatchReadyMs'], isNull);
      expect(perf.report()['locationReadyMs'], isNull);
    });

    test('milestones latch once and stay monotonic', () {
      perf.markSessionRestored();
      final t0 = perf.sessionRestoredDuration!;
      perf.markSessionRestored(); // duplicate call ignored
      expect(perf.sessionRestoredDuration, t0);

      perf.markTripRecoverySettled();
      expect(perf.tripRecoveryDuration! >= t0, isTrue);

      perf.markDispatchReady();
      perf.markLocationReady();
      expect(perf.dispatchReadyDuration != null, isTrue);
      expect(perf.locationReadyDuration != null, isTrue);

      final r = perf.report();
      expect(r['sessionRestoredMs'], isNotNull);
      expect(r['tripRecoveryMs'], isNotNull);
      expect(r['failedPhases'], isEmpty);
    });

    test('trip-recovery settlement flushes the report sink exactly once', () {
      perf.markTripRecoverySettled();
      expect(reports.length, 1);
      expect(reports.first['tripRecoveryMs'], isNotNull);
    });

    test('stage stopwatches record named steps', () {
      final sw = perf.startStopwatch('stageX');
      sw.stop();
      perf.finishStage('stageX');
      final stages = perf.report()['stages'] as List;
      expect(stages.any((e) => (e as Map)['stage'] == 'stageX'), isTrue);
    });
  });

  group('coordinator lifecycle reset', () {
    test('reset drops readiness so a fresh login re-proves every subsystem',
        () async {
      final coord = buildCoord([
        DriverDeferredStartupStep(
          subsystem: DriverStartupSubsystem.tripRecovery,
          body: () async => state.markActiveRideFound('ride-1'),
        ),
      ]);
      await coord.runDeferredInitialization();
      expect(state.snapshot.activeRideId, 'ride-1');

      await coord.reset();

      expect(state.snapshot.phases, isEmpty);
      expect(state.snapshot.activeRideId, isNull);
      expect(state.snapshot.serverValidated, isFalse);
    });
  });
}
