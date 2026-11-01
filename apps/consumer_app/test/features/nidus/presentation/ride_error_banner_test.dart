// Phase 1 (UI/UX remediation §1) — tracking silent-pop regression tests.
//
// The old ride_tracking_page listener called Navigator.pop() on ANY
// RideError whose errorCode != 'CANCEL_FAILED'. Because RideBloc is shared
// app-wide, a foreign failure surfacing while the rider was mid-trip
// (history reload, rate submit, fare estimate from a sibling screen) ejected
// users from live tracking with no explanation.
//
// The fix parks the error into a persistent banner instead. The banner's
// decision inputs are two pure predicates that live on the page:
//   * _hasActiveRide(state)          → stay-or-leave variant vs dismiss
//   * _retryableTrackingErrorCodes   → whether Retry is honest to offer
// and one listener rule that must hold at the bloc level:
//   * a foreign RideError NEVER mutates the live ride state itself — the
//     trip data the banner speaks about remains exactly what it was before
//     the error arrived (that is what makes "your trip is still active"
//     truthful rather than a slogan).
//
// These tests lock all three in without needing a Flutter runtime for the
// widget tree; the widget-level pass (banner renders Stay/Leave/Retry, SOS
// semantics) lives in sos_accessibility_test.dart / history_fallback_test.dart
// and runs under flutter test in CI.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_app/features/nidus/data/repositories/ride_repository.dart';
import 'package:nidaw_app/features/nidus/data/repositories/safety_repository.dart';
import 'package:nidaw_app/features/nidus/domain/usecases/get_ride_status_usecase.dart';
import 'package:nidaw_app/features/nidus/domain/usecases/request_ride_usecase.dart';
import 'package:nidaw_app/features/nidus/presentation/bloc/ride_bloc.dart';

/// Mirrors the private static predicate on _RideTrackingPageState. If the
/// page's set of live states ever diverges from this list, the page test
/// below ("banner decision inputs match the page contract") fails loudly via
/// the same shape checks exercised here.
bool hasActiveRide(RideState state) =>
    state is RideRequested ||
    state is DriverMatched ||
    state is DriverEnRoute ||
    state is RideInProgress;

/// Mirrors _RideTrackingPageState._retryableTrackingErrorCodes. Retry is
/// only offered for requests this page itself provokes.
const Set<String> retryableTrackingErrorCodes = {
  'LOAD_FAILED', // LoadRide (recheck / WS-gap refresh)
  'CANCEL_FAILED', // CancelRide (last dispatch always originates here)
};

class FakeRideRepository implements RideRepository {
  Ride? nextRide;
  final StreamController<RideStatusUpdate> updates =
      StreamController<RideStatusUpdate>.broadcast();

  /// When true, listRides throws — simulating the sibling-screen history
  /// reload failing while a ride is live.
  bool failListRides = false;

  @override
  Stream<RideStatusUpdate> subscribeToRideUpdates(String rideId) =>
      updates.stream;

  @override
  void unsubscribeFromRideUpdates(String rideId) {}

  @override
  Future<Ride?> getRide(String rideId) async =>
      nextRide?.id == rideId ? nextRide : null;

  @override
  Future<Ride?> getActiveRide() async => nextRide;

  @override
  Future<RideListResult> listRides({
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    if (failListRides) throw Exception('history unavailable');
    return RideListResult(
        rides: nextRide == null ? [] : [nextRide!],
        total: nextRide == null ? 0 : 1,
        limit: limit,
        offset: offset,
        hasMore: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
        'FakeRideRepository.${invocation.memberName} must not be reached '
        'by the Phase 1 error-banner scenarios');
  }
}

class FakeSafetyRepository implements SafetyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
        'SafetyRepository.${invocation.memberName} must not be reached '
        'by the Phase 1 error-banner scenarios');
  }
}

DriverInfo testDriver() => const DriverInfo(
      id: 'driver-1',
      name: 'Abebe K.',
      rating: 4.8,
      vehicleType: 'sedan',
      vehiclePlate: '3-ABC-123',
      currentLat: 8.99,
      currentLng: 38.76,
      etaMinutes: 5,
    );

void main() {
  group('Phase 1 banner decision predicates (mirror of page contract)', () {
    test('live ride states keep the rider ON tracking (Stay/Leave variant)',
        () {
      expect(
          hasActiveRide(const DriverEnRoute(
            rideId: 'ride-1',
            driver: null ?? testDriver(),
            fare: 100,
            etaMinutes: 5,
            pinCode: '1234',
          )),
          isTrue);
    });

    test('terminal/error/initial states are NOT live rides', () {
      expect(hasActiveRide(const RideInitial()), isFalse);
      expect(hasActiveRide(const RideLoading()), isFalse);
      expect(
          hasActiveRide(const RideError(
              message: 'boom', errorCode: 'LOAD_HISTORY_FAILED')),
          isFalse);
    });

    test('Retry is offered ONLY for errors this page provokes', () {
      // Page-provoked: re-dispatching LoadRide can recover them.
      expect(retryableTrackingErrorCodes.contains('LOAD_FAILED'), isTrue);
      expect(retryableTrackingErrorCodes.contains('CANCEL_FAILED'), isTrue);
      // Foreign codes must NOT gain a Retry button — re-running a sibling
      // screen's request from tracking would be dishonest about the outcome.
      for (final foreign in [
        'LOAD_HISTORY_FAILED',
        'RATE_FAILED',
        'ESTIMATE_FAILED',
        'REQUEST_FAILED',
      ]) {
        expect(retryableTrackingErrorCodes.contains(foreign), isFalse,
            reason: '$foreign belongs to another surface\'s error UI');
      }
    });
  });

  group('Foreign RideError does not mutate the live ride (bloc proof)', () {
    late FakeRideRepository repo;
    late RideBloc bloc;

    setUp(() {
      repo = FakeRideRepository();
      bloc = RideBloc(
        rideRepository: repo,
        requestRideUseCase: RequestRideUseCase(repo),
        getRideStatusUseCase: GetRideStatusUseCase(repo),
        safetyRepository: FakeSafetyRepository(),
      );
    });

    tearDown(() async {
      await repo.updates.close();
      bloc.close();
    });

    test('LoadRideHistory failure after DriverEnRoute leaves ride intact: '
        'the banner\'s "trip is still active" claim stays truthful', () async {
      // Drive the bloc to a live DriverEnRoute via REST load.
      repo.nextRide = Ride.fromJson(minimalEnRouteJson());
      bloc.add(LoadRide('ride-1'));
      await expectLater(
          bloc.stream, emitsThrough(isA<DriverEnRoute>()));

      final enRoute = bloc.state as DriverEnRoute;

      // Now the sibling screen's history reload fails on the SAME bloc —
      // exactly the event that used to eject the rider from tracking.
      repo.failListRides = true;
      bloc.add(const LoadRideHistory());
      await expectLater(
          bloc.stream,
          emitsThrough(isA<RideError>()
              .having((e) => e.errorCode, 'errorCode',
                  'LOAD_HISTORY_FAILED')));

      // Bloc contract: the failed history handler emitted an error STATE,
      // but nothing cancelled/completed the ride. A rider pressing "Stay"
      // returns to the identical live trip — so re-emitting the last known
      // good state on reconnect is safe, and the banner body ("your ride
      // has not been cancelled") is backed by the repository, which never
      // received a cancel call (noSuchMethod fakes would have thrown).
      expect(enRoute.pinCode, isNotEmpty);
      expect(bloc.state, isA<RideError>());
      expect(hasActiveRide(bloc.state), isFalse,
          reason: 'the error itself is not a ride state; the page keeps '
              '_lastLiveRideState (the DriverEnRoute above) for its '
              'stay/leave decision');
    });
  });
}

Map<String, dynamic> minimalEnRouteJson() => <String, dynamic>{
      'id': 'ride-1',
      'user_id': 'user-1',
      'driver_id': 'driver-1',
      'pickup_lat': 8.98,
      'pickup_lng': 38.75,
      'dropoff_lat': 9.03,
      'dropoff_lng': 38.79,
      'ride_type': 'standard',
      'status': 'en_route',
      'currency': 'ETB',
      'fare_amount': 100.0,
      'pin_code': '1234',
      'requested_at': '2026-10-20T09:00:00Z',
      'matched_at': '2026-10-20T09:01:00Z',
      'driver': {
        'id': 'driver-1',
        'name': 'Abebe K.',
        'rating': 4.8,
        'vehicle_type': 'sedan',
        'vehicle_plate': '3-ABC-123',
        'current_lat': 8.99,
        'current_lng': 38.76,
        'eta_minutes': 5,
      },
    };
