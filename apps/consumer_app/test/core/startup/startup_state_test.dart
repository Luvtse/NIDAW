import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_app/core/startup/startup_state.dart';

/// Phase 5 (§4.1/§4.2) startup-state contract tests.
///
/// These pin the anti-fabrication rules of the consumer startup model:
/// readiness is proven per launch, cached state is never presented as live,
/// booking requires server validation, and failed subsystems recover through
/// explicit retry transitions only.
void main() {
  group('StartupSnapshot.initial', () {
    test('nothing is ready or claimed at launch', () {
      const s = StartupSnapshot.initial();
      expect(s.sessionHydrated, isFalse);
      expect(s.cacheHydrated, isFalse);
      expect(s.serverValidated, isFalse);
      expect(s.connectivityKnown, isFalse);
      expect(s.isBookingReady, isFalse);
      expect(s.canShowAuthenticatedUi, isFalse);
      expect(s.failedSubsystems, isEmpty);
      for (final sub in StartupSubsystem.values) {
        expect(s.statusOf(sub), StartupPhaseStatus.pending);
      }
    });
  });

  group('StartupStateNotifier transitions', () {
    late StartupStateNotifier n;
    late int notifications;

    setUp(() {
      n = StartupStateNotifier();
      notifications = 0;
      n.addListener(() => notifications++);
    });

    tearDown(() => n.dispose());

    test('legal chain pending -> running -> ready emits notifications', () {
      n.markRunning(StartupSubsystem.offlineService);
      expect(n.snapshot.statusOf(StartupSubsystem.offlineService),
          StartupPhaseStatus.running);
      n.markReady(StartupSubsystem.offlineService);
      expect(n.snapshot.isReady(StartupSubsystem.offlineService), isTrue);
      expect(notifications, 2);
    });

    test('ready is terminal for the launch (idempotent re-init ignored)', () {
      n.markReady(StartupSubsystem.geocodingCache);
      final before = notifications;
      // Offline init / FCM init / WS reconnect fire more than once; a second
      // "ready" must be a silent no-op, not a regression to running.
      n.markRunning(StartupSubsystem.geocodingCache);
      n.markFailed(StartupSubsystem.geocodingCache);
      expect(n.snapshot.isReady(StartupSubsystem.geocodingCache), isTrue);
      expect(notifications, before);
    });

    test('illegal pending -> failed jump is ignored', () {
      n.markFailed(StartupSubsystem.featureFlags);
      expect(n.snapshot.statusOf(StartupSubsystem.featureFlags),
          StartupPhaseStatus.pending,
          reason: 'failure without an attempt cannot be recorded');
    });

    test('failed -> running recovery path is legal', () {
      n.markRunning(StartupSubsystem.pushNotifications);
      n.markFailed(StartupSubsystem.pushNotifications);
      expect(n.snapshot.failedSubsystems,
          contains(StartupSubsystem.pushNotifications));
      n.markRunning(StartupSubsystem.pushNotifications);
      n.markReady(StartupSubsystem.pushNotifications);
      expect(n.snapshot.isReady(StartupSubsystem.pushNotifications), isTrue);
      expect(n.snapshot.failedSubsystems, isEmpty);
    });
  });

  group('session hydration outcomes', () {
    test('successful hydration marks sessionHydrated + cache flag', () {
      final n = StartupStateNotifier();
      n.markRunning(StartupSubsystem.sessionHydration);
      n.completeSessionHydration(cacheRead: true);
      expect(n.snapshot.sessionHydrated, isTrue);
      expect(n.snapshot.cacheHydrated, isTrue);
      expect(n.snapshot.canShowAuthenticatedUi, isTrue);
      n.dispose();
    });

    test('corrupt store fails honestly but still settles routing', () {
      final n = StartupStateNotifier();
      n.failSessionHydration();
      expect(n.snapshot.statusOf(StartupSubsystem.sessionHydration),
          StartupPhaseStatus.failed);
      // Login screen is a SAFE settled outcome — the router must not spin.
      expect(n.snapshot.sessionHydrated, isTrue);
      expect(n.snapshot.serverValidated, isFalse);
      n.dispose();
    });

    test('markCacheHydrated is monotonic (never un-hydrates)', () {
      final n = StartupStateNotifier();
      n.markCacheHydrated();
      n.markCacheHydrated();
      expect(n.snapshot.cacheHydrated, isTrue);
      n.dispose();
    });
  });

  group('booking gate (cache alone NEVER enables booking)', () {
    test('hydrated + cached but NOT server-validated -> not booking ready',
        () {
      final n = StartupStateNotifier();
      n.completeSessionHydration(cacheRead: true);
      n.markReady(StartupSubsystem.offlineService);
      expect(n.snapshot.cacheHydrated, isTrue);
      expect(n.snapshot.isBookingReady, isFalse,
          reason: 'a stale cached quote must never enable live booking');
      n.markServerValidated();
      expect(n.snapshot.isBookingReady, isTrue);
      n.dispose();
    });

    test('server-validated without offline service -> not booking ready', () {
      final n = StartupStateNotifier();
      n.completeSessionHydration(cacheRead: false);
      n.markServerValidated();
      expect(n.snapshot.isBookingReady, isFalse);
      n.markReady(StartupSubsystem.offlineService);
      expect(n.snapshot.isBookingReady, isTrue);
      n.dispose();
    });

    test('connectivity known is a settled answer either way', () {
      final n = StartupStateNotifier();
      expect(n.snapshot.connectivityKnown, isFalse);
      n.markConnectivityKnown();
      expect(n.snapshot.connectivityKnown, isTrue);
      n.dispose();
    });
  });

  group('waitUntil', () {
    test('resolves when predicate becomes true via transition', () async {
      final n = StartupStateNotifier();
      var done = false;
      final future = n
          .waitUntil((s) => s.isReady(StartupSubsystem.realtimeChannel))
          .then((_) => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(done, isFalse);
      n.markReady(StartupSubsystem.realtimeChannel);
      await future.timeout(const Duration(seconds: 2));
      expect(done, isTrue);
      n.dispose();
    });

    test('returns immediately when predicate already holds', () async {
      final n = StartupStateNotifier();
      n.markReady(StartupSubsystem.bootstrap);
      await n
          .waitUntil((s) => s.isReady(StartupSubsystem.bootstrap))
          .timeout(const Duration(seconds: 1));
      n.dispose();
    });
  });

  group('reset (logout / hot restart)', () {
    test('drops every readiness flag so a fresh login re-proves state', () {
      final n = StartupStateNotifier();
      n.completeSessionHydration(cacheRead: true);
      n.markServerValidated();
      n.markConnectivityKnown();
      n.markReady(StartupSubsystem.offlineService);
      n.reset();
      final s = n.snapshot;
      expect(s.sessionHydrated, isFalse);
      expect(s.cacheHydrated, isFalse);
      expect(s.serverValidated, isFalse);
      expect(s.connectivityKnown, isFalse);
      expect(s.isBookingReady, isFalse);
      expect(s.phases, isEmpty);
      n.dispose();
    });
  });
}
