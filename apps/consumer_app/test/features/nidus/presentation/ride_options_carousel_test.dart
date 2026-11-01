// Phase 2 — Dead-code resolution (RECONNECT): bloc-level tests for the
// ride-options carousel path.
//
// The LoadRideOptions event, RideOptionsLoaded/RideOptionsFailed states and
// their handlers existed in the bloc but were never dispatched from any UI
// (git-grepped: zero references outside ride_bloc.dart). The reconnect wires
// ride_request_page.dart to this path; these tests lock the contract the page
// now depends on:
//
//  1. Success: options fetch → RideOptionsLoaded carrying the list AND the
//     last server-confirmed single-type estimate (footer price must survive
//     the wholesale state replacement).
//  2. Failure: repository throw → RideOptionsFailed with a message the retry
//     strip can surface, still carrying the prior estimate so the footer
//     doesn't blink out.
//  3. Empty list → treated as failure ("No ride options…"), never a silent
//     empty carousel.
//  4. Re-anchor: refreshed list missing the selected type → bloc emits
//     RideOptionSelectionChanged and RideOptionsLoaded.selectedType follows
//     the data (highlight == type RequestRide will ship).
//  5. SelectRideOption updates the highlight without touching options.
//  6. GetFareEstimate folds the refreshed estimate into RideOptionsLoaded
//     instead of clobbering the carousel with a bare FareEstimateLoaded.
//
// Fakes follow the ride_bloc_eta_test.dart pattern: unneeded members throw
// via noSuchMethod so accidental coupling is loud.

import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_app/features/nidus/data/repositories/ride_repository.dart';
import 'package:nidaw_app/features/nidus/data/repositories/safety_repository.dart';
import 'package:nidaw_app/features/nidus/domain/usecases/get_ride_status_usecase.dart';
import 'package:nidaw_app/features/nidus/domain/usecases/request_ride_usecase.dart';
import 'package:nidaw_app/features/nidus/presentation/bloc/ride_bloc.dart';

class FakeRideRepository implements RideRepository {
  /// Canned response for getRideOptionEstimates. When non-null it is
  /// returned; when [optionsThrows] is set the call throws instead.
  List<RideOptionEstimate>? nextOptions;
  bool optionsThrows = false;
  int optionCalls = 0;

  FareEstimate? nextEstimate;
  int estimateCalls = 0;

  @override
  Future<List<RideOptionEstimate>> getRideOptionEstimates({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    optionCalls++;
    if (optionsThrows) throw Exception('estimates endpoint down');
    return nextOptions ?? const [];
  }

  @override
  Future<FareEstimate?> getFareEstimate({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? rideType,
  }) async {
    estimateCalls++;
    return nextEstimate;
  }

  @override
  Stream<RideStatusUpdate> subscribeToRideUpdates(String rideId) =>
      const Stream.empty();

  @override
  void unsubscribeFromRideUpdates(String rideId) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
        'FakeRideRepository.${invocation.memberName} must not be reached '
        'by the Phase 2 ride-options scenarios');
  }
}

class FakeSafetyRepository implements SafetyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
        'SafetyRepository.${invocation.memberName} must not be reached '
        'by the Phase 2 ride-options scenarios');
  }
}

FareEstimate estimate({double total = 120}) => FareEstimate(
      rideType: 'standard',
      baseFare: 40,
      distanceFare: total - 40,
      timeFare: 0,
      subtotal: total,
      surgeMultiplier: 1.0,
      totalFare: total,
      currency: 'ETB',
      distanceKm: 7.2,
      durationMinutes: 18,
      estimatedPickupMinutes: 4,
    );

RideOptionEstimate option(String type, {bool available = true}) =>
    RideOptionEstimate(
      rideType: type,
      displayName: type,
      totalFare: 100,
      surgeMultiplier: 1.0,
      currency: 'ETB',
      etaMinutes: 5,
      available: available,
    );

void main() {
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

  tearDown(() {
    bloc.close();
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  group('LoadRideOptions success (reconnect contract)', () {
    test('emits RideOptionsLoaded with the fetched list', () async {
      repo.nextOptions = [option('standard'), option('shared')];
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();

      final s = bloc.state;
      expect(s, isA<RideOptionsLoaded>());
      final loaded = s as RideOptionsLoaded;
      expect(loaded.options.map((o) => o.rideType), ['standard', 'shared']);
      expect(loaded.selectedType, 'standard');
      expect(loaded.estimate, isNull);
    });

    test('carries the last successful fare estimate so the footer survives',
        () async {
      repo.nextEstimate = estimate(total: 150);
      bloc.add(const GetFareEstimate(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();
      expect(bloc.state, isA<FareEstimateLoaded>());

      repo.nextOptions = [option('standard')];
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();

      final loaded = bloc.state as RideOptionsLoaded;
      expect(loaded.estimate?.totalFare, 150);
    });
  });

  group('LoadRideOptions failure (retry-strip reachability)', () {
    test('repository throw → RideOptionsFailed with message + prior estimate',
        () async {
      repo.nextEstimate = estimate(total: 90);
      bloc.add(const GetFareEstimate(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();

      repo.optionsThrows = true;
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();

      final s = bloc.state;
      expect(s, isA<RideOptionsFailed>());
      final failed = s as RideOptionsFailed;
      // Message surfaces verbatim as the strip's secondary detail line.
      expect(failed.message, contains('estimates endpoint down'));
      expect(failed.estimate?.totalFare, 90);
    });

    test('empty option list → RideOptionsFailed, never a silent empty carousel',
        () async {
      repo.nextOptions = [];
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();

      final s = bloc.state;
      expect(s, isA<RideOptionsFailed>());
      expect((s as RideOptionsFailed).message,
          contains('No ride options are currently available'));
    });

    test('retry after failure succeeds → RideOptionsLoaded again', () async {
      repo.optionsThrows = true;
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();
      expect(bloc.state, isA<RideOptionsFailed>());

      // Same dispatch the page's Retry button performs (_loadRideOptions).
      repo.optionsThrows = false;
      repo.nextOptions = [option('standard')];
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();
      expect(bloc.state, isA<RideOptionsLoaded>());
      expect(repo.optionCalls, 2);
    });
  });

  group('Re-anchor: selection follows data', () {
    test('dropped selected type triggers RideOptionSelectionChanged and the '
        'loaded snapshot is tagged with it (page mirrors via state.event)',
        () async {
      // First load: standard + shared, rider picks shared.
      repo.nextOptions = [option('standard'), option('shared')];
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
        selectedType: 'shared',
      ));
      await pump();
      expect((bloc.state as RideOptionsLoaded).selectedType, 'shared');

      // Refresh: shared disappeared from the list.
      repo.nextOptions = [option('standard'), option('xl')];
      final transitions = <RideState>[];
      final sub = bloc.stream.listen(transitions.add);

      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
        selectedType: 'shared',
      ));
      await pump();
      await sub.cancel();

      final loaded = bloc.state as RideOptionsLoaded;
      // Re-anchor landed on the first available option of the fresh list.
      expect(loaded.selectedType, 'standard');
      expect(loaded.options.map((o) => o.rideType), ['standard', 'xl']);
      // The snapshot rides with the RideOptionSelectionChanged event so the
      // page's _handleRideState moves its highlight in lockstep — this is
      // the exact branch the reconnect depends on.
      expect(loaded.event, isA<RideOptionSelectionChanged>());
      expect((loaded.event as RideOptionSelectionChanged).rideType, 'standard');
      // And a tagged transition actually reached listeners (not just the
      // final cached state): the sync handler emitted one too.
      expect(
        transitions.where((s) => s.event is RideOptionSelectionChanged),
        isNotEmpty,
      );
    });

    test('unavailable-but-present type also re-anchors', () async {
      repo.nextOptions = [
        option('standard'),
        option('shared', available: false),
      ];
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
        selectedType: 'shared',
      ));
      await pump();
      final loaded = bloc.state as RideOptionsLoaded;
      expect(loaded.selectedType, 'standard');
      expect(loaded.event, isA<RideOptionSelectionChanged>());
    });

    test('valid selection is NOT re-anchored: snapshot tags the fetch event',
        () async {
      repo.nextOptions = [option('standard'), option('shared')];
      const load = LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
        selectedType: 'shared',
      );
      bloc.add(load);
      await pump();
      final loaded = bloc.state as RideOptionsLoaded;
      expect(loaded.selectedType, 'shared');
      expect(loaded.event, same(load));
      expect(loaded.event, isNot(isA<RideOptionSelectionChanged>()));
    });
  });

  group('SelectRideOption', () {
    test('updates highlight without disturbing options or estimate', () async {
      repo.nextEstimate = estimate();
      bloc.add(const GetFareEstimate(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();
      repo.nextOptions = [option('standard'), option('premium')];
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();

      bloc.add(const SelectRideOption('premium'));
      await pump();

      final loaded = bloc.state as RideOptionsLoaded;
      expect(loaded.selectedType, 'premium');
      expect(loaded.options.length, 2);
      expect(loaded.estimate, isNotNull);
      // Tagged with the user's pick so the page can distinguish a manual
      // selection from a bloc re-anchor if it ever needs to.
      expect(loaded.event, isA<SelectRideOption>());
    });
  });

  group('GetFareEstimate coherence with carousel', () {
    test('refreshed estimate folds into RideOptionsLoaded instead of '
        'clobbering the carousel', () async {
      repo.nextOptions = [option('standard')];
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();
      expect(bloc.state, isA<RideOptionsLoaded>());

      repo.nextEstimate = estimate(total: 210);
      bloc.add(const GetFareEstimate(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
        rideType: 'standard',
      ));
      await pump();

      final s = bloc.state;
      expect(s, isA<RideOptionsLoaded>(),
          reason: 'carousel data must survive an estimate refresh');
      expect((s as RideOptionsLoaded).estimate?.totalFare, 210);
      expect(s.options.length, 1);
    });

    test('does not emit RideLoading once real data is on screen', () async {
      repo.nextOptions = [option('standard')];
      bloc.add(const LoadRideOptions(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();

      final transitions = <RideState>[];
      final sub = bloc.stream.listen(transitions.add);
      repo.nextEstimate = estimate();
      bloc.add(const GetFareEstimate(
        pickupLat: 8.98,
        pickupLng: 38.75,
        dropoffLat: 9.03,
        dropoffLng: 38.79,
      ));
      await pump();
      await sub.cancel();

      expect(transitions.whereType<RideLoading>(), isEmpty);
    });
  });
}
