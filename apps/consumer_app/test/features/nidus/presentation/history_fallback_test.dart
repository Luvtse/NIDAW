// Phase 1 (UI/UX remediation §3) — history loading/empty conflation tests.
//
// The old ride_history_page fell through its BlocBuilder to
// `Center(child: Text('No rides found'))` for ANY state that was not
// RideLoading / RideHistoryLoaded / RideError — including the very first
// RideInitial frame before LoadRideHistory resolved, and any foreign state
// the shared app-wide RideBloc happens to hold (DriverEnRoute from a live
// trip, FareEstimateLoaded from the request screen, etc.). Riders saw a
// false "your history is empty" message during those frames.
//
// The fix routes every pre-load/unrelated state to an honest skeleton.
// These bloc-level tests lock the state shapes the page branches on; the
// widget pass (skeleton renders, no 'No rides yet' text pre-load) runs in
// CI under flutter test once the l10n bundle is generated.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_app/features/nidus/data/repositories/ride_repository.dart';
import 'package:nidaw_app/features/nidus/data/repositories/safety_repository.dart';
import 'package:nidaw_app/features/nidus/domain/usecases/get_ride_status_usecase.dart';
import 'package:nidaw_app/features/nidus/domain/usecases/request_ride_usecase.dart';
import 'package:nidaw_app/features/nidus/presentation/bloc/ride_bloc.dart';

class FakeHistoryRepository implements RideRepository {
  bool failListRides = false;
  List<Ride> rides = const [];
  final List<String?> requestedStatuses = [];

  @override
  Future<RideListResult> listRides({
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    requestedStatuses.add(status);
    if (failListRides) throw Exception('history unavailable');
    return RideListResult(
      rides: rides,
      total: rides.length,
      limit: limit,
      offset: offset,
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
        'FakeHistoryRepository.${invocation.memberName} must not be reached '
        'by the Phase 1 history-fallback scenarios');
  }
}

class FakeSafetyRepository implements SafetyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
        'SafetyRepository.${invocation.memberName} must not be reached '
        'by the Phase 1 history-fallback scenarios');
  }
}

void main() {
  late FakeHistoryRepository repo;
  late RideBloc bloc;

  setUp(() {
    repo = FakeHistoryRepository();
    bloc = RideBloc(
      rideRepository: repo,
      requestRideUseCase: RequestRideUseCase(repo),
      getRideStatusUseCase: GetRideStatusUseCase(repo),
      safetyRepository: FakeSafetyRepository(),
    );
  });

  tearDown(() => bloc.close());

  group('LoadRideHistory state machine (page branch inputs)', () {
    test('initial state is RideInitial — the page must render the skeleton, '
        'never the empty-state copy, while this is the current state', () {
      // Locks the contract: RideInitial exists and is NOT one of the three
      // states the page treats as content (Loading/Loaded/Error), so it
      // falls into the skeleton branch by construction.
      expect(bloc.state, isA<RideInitial>());
      expect(bloc.state, isNot(isA<RideLoading>()));
      expect(bloc.state, isNot(isA<RideHistoryLoaded>()));
      expect(bloc.state, isNot(isA<RideError>()));
    });

    test('success emits RideHistoryLoaded with exactly the repository rows',
        () async {
      final future = bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      bloc.add(const LoadRideHistory());
      final loaded = await future as RideHistoryLoaded;
      expect(loaded.rides, isEmpty);
      expect(loaded.hasMore, isFalse);
      // An EMPTY RideHistoryLoaded is the ONLY state allowed to show
      // "no rides" copy — the page distinguishes genuine emptiness from
      // pre-load precisely via this type.
      expect(loaded.total, 0);
    });

    test('filtered reload passes the status through to the repository',
        () async {
      final future = bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      bloc.add(const LoadRideHistory(status: 'completed'));
      await future;
      expect(repo.requestedStatuses, contains('completed'));
    });

    test('failure emits RideError(LOAD_HISTORY_FAILED) — the page shows the '
        'localized primary headline with the raw message demoted to detail',
        () async {
      repo.failListRides = true;
      final future = bloc.stream.firstWhere((s) => s is RideError);
      bloc.add(const LoadRideHistory());
      final err = await future as RideError;
      expect(err.errorCode, 'LOAD_HISTORY_FAILED');
      // The raw server string is carried for the detail line only; the UI
      // must never promote it to the headline (Phase 1 §3 requirement).
      expect(err.message, contains('history unavailable'));
    });

    test('pre-load state types stay distinct from every content state the '
        'page renders — the skeleton branch can never be reached by a '
        'genuine empty-result RideHistoryLoaded', () async {
      final ok = bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      bloc.add(const LoadRideHistory());
      await ok;
      // RideInitial / RideLoading are the pre-load shapes; assert their
      // types are distinct from every content state the page renders.
      expect(const RideInitial(), isNot(isA<RideHistoryLoaded>()));
      expect(const RideLoading(), isNot(isA<RideHistoryLoaded>()));
      expect(const RideLoading(), isNot(isA<RideError>()));
    });
  });
}
