import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_driver_app/core/startup/driver_startup_state.dart';

/// Phase 5 (§4.3) driver startup-state contract tests.
///
/// Pins the recovery/offline rules: provisional-vs-validated availability,
/// dispatch readiness requiring an authenticated socket AND a subscription
/// ack, honest trip-recovery outcomes (found / none / failed — never a
/// fabricated "no trip"), and the location-tracking permission gate.
void main() {
  group('DriverStartupSnapshot.initial', () {
    test('nothing is claimed at launch', () {
      // Const-compatible: the factory `initial()` is not a const constructor,
      // but the underlying const default map is identical.
      final s = DriverStartupSnapshot.initial();
      expect(s.sessionRestored, isFalse);
      expect(s.serverValidated, isFalse);
      expect(s.availabilityProvisional, isFalse);
      expect(s.availabilityConfirmed, isFalse);
      expect(s.tripRecoverySettled, isFalse);
      expect(s.activeRideId, isNull);
      expect(s.isDispatchReady, isFalse);
      expect(s.trackingPermitted, isFalse);
      expect(s.isOnActiveTrip, isFalse);
      for (final sub in DriverStartupSubsystem.values) {
        expect(s.statusOf(sub), DriverStartupPhaseStatus.pending);
      }
    });
  });

  group('session hydration', () {
    late DriverStartupStateNotifier n;
    setUp(() => n = DriverStartupStateNotifier());
    tearDown(() => n.dispose());

    test('local token found is PROVISIONAL until server validation', () {
      n.markSessionRestored();
      expect(n.snapshot.sessionRestored, isTrue);
      expect(n.snapshot.serverValidated, isFalse);
      // Provisional cache must not unlock dispatch actions.
      expect(n.snapshot.isDispatchReady, isFalse);
      expect(
          n.snapshot.statusOf(DriverStartupSubsystem.sessionHydration),
          DriverStartupPhaseStatus.running);
    });

    test('server validation flips sessionHydration ready + serverValidated',
        () {
      n.markSessionRestored();
      n.markServerValidated();
      expect(n.snapshot.serverValidated, isTrue);
      expect(
          n.snapshot.isReady(DriverStartupSubsystem.sessionHydration), isTrue);
      expect(n.snapshot.canShowAuthenticatedUi, isTrue);
    });

    test('signed-out is a settled outcome (router routes to /login)', () {
      n.markSignedOut();
      expect(n.snapshot.sessionRestored, isFalse);
      expect(n.snapshot.hasPendingHydration, isFalse);
      expect(n.snapshot.canShowAuthenticatedUi, isTrue,
          reason: 'definitive signed-out IS a validated state for routing');
    });
  });

  group('availability provisional -> confirmed', () {
    late DriverStartupStateNotifier n;
    setUp(() => n = DriverStartupStateNotifier());
    tearDown(() => n.dispose());

    test('cached toggle alone never permits tracking', () {
      n.markAvailabilityProvisional();
      expect(n.snapshot.availabilityProvisional, isTrue);
      expect(n.snapshot.availabilityConfirmed, isFalse);
      expect(n.snapshot.trackingPermitted, isFalse);
    });

    test('server echo of ONLINE permits tracking', () {
      n.markAvailabilityConfirmed(true);
      expect(n.snapshot.trackingPermitted, isTrue);
    });

    test('going OFFLINE revokes tracking permission mid-session', () {
      n.markAvailabilityConfirmed(true);
      n.markReady(DriverStartupSubsystem.locationTracking);
      n.markAvailabilityConfirmed(false);
      expect(n.snapshot.trackingPermitted, isFalse);
      expect(
          n.snapshot.isReady(DriverStartupSubsystem.locationTracking), isFalse,
          reason: 'offline drivers stop continuous collection (battery/§4.3)');
    });

    test('active trip permits tracking even when availability offline', () {
      n.markActiveRideFound('ride-1');
      expect(n.snapshot.isOnActiveTrip, isTrue);
      expect(n.snapshot.trackingPermitted, isTrue);
    });
  });

  group('trip recovery settlement honesty', () {
    late DriverStartupStateNotifier n;
    setUp(() => n = DriverStartupStateNotifier());
    tearDown(() => n.dispose());

    test('running -> active ride found settles with the ride id', () {
      n.markTripRecoveryStarted();
      expect(n.snapshot.tripRecoverySettled, isFalse);
      n.markActiveRideFound('ride-42');
      expect(n.snapshot.tripRecoverySettled, isTrue);
      expect(n.snapshot.activeRideId, 'ride-42');
      expect(
          n.snapshot.isReady(DriverStartupSubsystem.tripRecovery), isTrue);
    });

    test('"no active ride" is a settled NEGATIVE, safe for home shell', () {
      n.markTripRecoveryStarted();
      n.markNoActiveRide();
      expect(n.snapshot.tripRecoverySettled, isTrue);
      expect(n.snapshot.activeRideId, isNull);
      expect(n.snapshot.isOnActiveTrip, isFalse);
    });

    test('exhausted retries FAIL honestly — never a fabricated "no trip"', () {
      n.markTripRecoveryStarted();
      n.markTripRecoveryFailed();
      expect(n.snapshot.tripRecoverySettled, isFalse,
          reason: 'unanswered != answered-with-none');
      expect(
          n.snapshot.statusOf(DriverStartupSubsystem.tripRecovery),
          DriverStartupPhaseStatus.failed);
      expect(n.snapshot.failedSubsystems,
          contains(DriverStartupSubsystem.tripRecovery));
    });

    test('clearActiveTrip drops the settled ride on completion', () {
      n.markActiveRideFound('ride-7');
      n.clearActiveTrip();
      expect(n.snapshot.activeRideId, isNull);
      expect(n.snapshot.isOnActiveTrip, isFalse);
    });
  });

  group('dispatch readiness (socket + offers ack required)', () {
    late DriverStartupStateNotifier n;
    setUp(() => n = DriverStartupStateNotifier());
    tearDown(() => n.dispose());

    test('connected socket WITHOUT server ack is not dispatch ready', () {
      n.markServerValidated();
      n.markReady(DriverStartupSubsystem.realtimeChannel);
      expect(n.snapshot.isDispatchReady, isFalse,
          reason: 'optimistic subscribe frame != authorized subscription');
    });

    test('ack without authenticated server validation is not ready', () {
      n.markReady(DriverStartupSubsystem.realtimeChannel);
      n.markReady(DriverStartupSubsystem.dispatchSubscription);
      expect(n.snapshot.isDispatchReady, isFalse);
    });

    test('all three proven -> dispatch ready', () {
      n.markServerValidated();
      n.markReady(DriverStartupSubsystem.realtimeChannel);
      n.markReady(DriverStartupSubsystem.dispatchSubscription);
      expect(n.snapshot.isDispatchReady, isTrue);
    });
  });

  group('reset (logout / hot restart)', () {
    test('drops all readiness so a fresh login re-proves every subsystem',
        () {
      final n = DriverStartupStateNotifier();
      n.markServerValidated();
      n.markAvailabilityConfirmed(true);
      n.markActiveRideFound('ride-1');
      n.markReady(DriverStartupSubsystem.realtimeChannel);
      n.reset();
      final s = n.snapshot;
      expect(s.serverValidated, isFalse);
      expect(s.availabilityConfirmed, isFalse);
      expect(s.tripRecoverySettled, isFalse);
      expect(s.activeRideId, isNull);
      expect(s.isDispatchReady, isFalse);
      expect(s.phases, isEmpty);
      n.dispose();
    });
  });

  group('notification discipline', () {
    test('every state change notifies exactly once per transition', () {
      final n = DriverStartupStateNotifier();
      var count = 0;
      n.addListener(() => count++);
      n.markRunning(DriverStartupSubsystem.bootstrap);
      n.markReady(DriverStartupSubsystem.bootstrap);
      expect(count, 2);
      n.dispose();
    });
  });
}
