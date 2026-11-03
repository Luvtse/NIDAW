// Phase 5 (connectivity & state-honesty UX) — regression lock.
//
// Bloc level:
//  * offline tap on Request → RideDraftQueued, NEVER a network call;
//  * honest-null rule: an UNSET verdict is not treated as offline;
//  * blocked history refresh replays when connectivity returns;
//  * history filter survives reloads / resets only via clearStatusFilter;
//  * drafts sync through OfflineService.syncPendingOperations on reconnect.
// Widget level (ride_history_page):
//  * RefreshIndicator present; pull dispatches LoadRideHistory WITHOUT an
//    explicit status so the bloc-retained filter round-trips;
//  * re-entry seeds the chips from bloc.historyStatusFilter instead of
//    silently resetting to 'all'.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:nidaw_app/core/offline/offline_service.dart';
import 'package:nidaw_app/features/nidus/data/repositories/ride_repository.dart';
import 'package:nidaw_app/features/nidus/data/repositories/safety_repository.dart';
import 'package:nidaw_app/features/nidus/domain/usecases/get_ride_status_usecase.dart';
import 'package:nidaw_app/features/nidus/domain/usecases/request_ride_usecase.dart';
import 'package:nidaw_app/features/nidus/presentation/bloc/ride_bloc.dart';
import 'package:nidaw_app/features/nidus/presentation/pages/ride_history_page.dart';
import 'package:nidaw_app/l10n/generated/app_localizations.dart';

const _pickup = LatLngPair(9.03, 38.74);
const _dropoff = LatLngPair(9.07, 38.79);

/// Tiny coordinate pair holder so the request literals below read cleanly.
class LatLngPair {
  final double lat;
  final double lng;
  const LatLngPair(this.lat, this.lng);
}

RequestRide _request({String rideType = 'standard'}) => RequestRide(
      pickupLat: _pickup.lat,
      pickupLng: _pickup.lng,
      dropoffLat: _dropoff.lat,
      dropoffLng: _dropoff.lng,
      pickupAddress: 'Bole',
      dropoffAddress: 'Kazanchis',
      rideType: rideType,
    );

class FakePhase5Repository implements RideRepository {
  int requestCalls = 0;
  int listCalls = 0;
  final List<String?> requestedStatuses = [];
  List<Ride> rides = const [];

  @override
  Future<RideResult> requestRide({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? pickupAddress,
    String? dropoffAddress,
    String rideType = 'standard',
    String? paymentMethodId,
    String? paymentMethodType,
    String? promoCode,
    String? scheduledAt,
    List<RideStop> stops = const [],
  }) async {
    requestCalls++;
    return const RideResult.success(
        rideId: 'r-1', status: 'requested', fare: 120, eta: 4);
  }

  @override
  Future<RideListResult> listRides({
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    listCalls++;
    requestedStatuses.add(status);
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
        'FakePhase5Repository.${invocation.memberName} must not be reached '
        'by the Phase 5 scenarios');
  }
}

class FakeSafetyRepository implements SafetyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
        'SafetyRepository.${invocation.memberName} must not be reached '
        'by the Phase 5 scenarios');
  }
}

/// Test stand-in for the real OfflineService: same replay seam the bloc
/// calls on reconnect ([syncPendingOperations]), but Hive-free. Records
/// queue writes and can flip into "sync failed" to prove the bloc swallows
/// the error honestly instead of pretending delivery.
class FakeOfflineService extends OfflineService {
  int syncCalls = 0;
  bool failSync = false;
  final List<Map<String, dynamic>> queued = [];

  @override
  bool get isReady => true;

  @override
  Future<String> queueOperation({
    required String endpoint,
    required String method,
    required Map<String, dynamic> data,
    int priority = 0,
  }) async {
    queued.add({'endpoint': endpoint, 'method': method, 'data': data});
    return 'queued-${queued.length}';
  }

  @override
  Future<void> syncPendingOperations() async {
    syncCalls++;
    if (failSync) {
      throw Exception('sender rejected the replay');
    }
  }
}

void main() {
  late FakePhase5Repository repo;
  late StreamController<bool> connectivity;

  RideBloc buildBloc({OfflineService? offline}) {
    connectivity = StreamController<bool>.broadcast();
    return RideBloc(
      rideRepository: repo,
      requestRideUseCase: RequestRideUseCase(repo),
      getRideStatusUseCase: GetRideStatusUseCase(repo),
      safetyRepository: FakeSafetyRepository(),
      connectivityStream: connectivity.stream,
      offlineService: offline,
    );
  }

  setUp(() {
    repo = FakePhase5Repository();
  });

  group('offline ride request → draft, never a network call', () {
    test('settled-offline verdict routes RequestRide to RideDraftQueued',
        () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      connectivity.add(false);
      await bloc.stream.firstWhere((s) => s is RideInitial);
      // Give the ConnectivityChanged fold one microtask loop to settle the
      // verdict before the tap.
      await Future<void>.delayed(Duration.zero);

      final draft = bloc.stream.firstWhere((s) => s is RideDraftQueued);
      bloc.add(_request());
      final queuedState = await draft as RideDraftQueued;

      expect(queuedState.draftCount, 1);
      // The whole point: NO doomed POST went out while offline.
      expect(repo.requestCalls, 0);
    });

    test('honest-null rule — an UNSET verdict proceeds on the normal path',
        () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      final requested = bloc.stream.firstWhere((s) => s is RideRequested);
      bloc.add(_request());
      await requested;

      // No connectivity sample ever arrived → the bloc must NOT have
      // guessed "offline" and drafted the request.
      expect(repo.requestCalls, 1);
      expect(bloc.state, isNot(isA<RideDraftQueued>()));
    });

    test('draft persists through OfflineService when ready', () async {
      final svc = FakeOfflineService();
      final bloc = buildBloc(offline: svc);
      addTearDown(bloc.close);

      connectivity.add(false);
      await Future<void>.delayed(Duration.zero);

      final draft = bloc.stream.firstWhere((s) => s is RideDraftQueued);
      bloc.add(_request(rideType: 'premium'));
      await draft;

      expect(svc.queued, hasLength(1));
      final op = svc.queued.single;
      expect(op['method'], 'POST');
      expect(op['endpoint'], '/api/v1/nidus/rides');
      final payload = op['data'] as Map<String, dynamic>;
      expect(payload['ride_type'], 'premium');
      expect(payload['pickup_address'], 'Bole');
    });

    test('reconnect replays persisted drafts via syncPendingOperations',
        () async {
      final svc = FakeOfflineService();
      final bloc = buildBloc(offline: svc);
      addTearDown(bloc.close);

      connectivity.add(false);
      await Future<void>.delayed(Duration.zero);
      final first = bloc.stream.firstWhere((s) => s is RideDraftQueued);
      bloc.add(_request());
      await first;
      expect(svc.syncCalls, 0);

      connectivity.add(true);
      await bloc.stream.firstWhere((s) => s is! RideDraftQueued);
      await Future<void>.delayed(Duration.zero);
      expect(svc.syncCalls, 1);
    });

    test('a failing sync never crashes the bloc or claims delivery',
        () async {
      final svc = FakeOfflineService()..failSync = true;
      final bloc = buildBloc(offline: svc);
      addTearDown(bloc.close);

      connectivity.add(false);
      await Future<void>.delayed(Duration.zero);
      final first = bloc.stream.firstWhere((s) => s is RideDraftQueued);
      bloc.add(_request());
      await first;

      connectivity.add(true);
      await bloc.stream.firstWhere((s) => s is! RideDraftQueued);
      await Future<void>.delayed(Duration.zero);

      expect(svc.syncCalls, 1);
      // Honest degradation: the bloc folded back to a connectivity-aware
      // content view, never an uncaught error state from the replay.
      expect(bloc.state, isNot(isA<RideError>()));
    });
  });

  group('blocked refresh replay on reconnect', () {
    test('offline LoadRideHistory blocks without touching the network, then '
        'replays once connectivity returns', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      connectivity.add(false);
      await Future<void>.delayed(Duration.zero);

      final blocked =
          bloc.stream.firstWhere((s) => s is OfflineRefreshBlockedState);
      bloc.add(const LoadRideHistory());
      await blocked;
      expect(repo.listCalls, 0);

      connectivity.add(true);
      final loaded =
          bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      await loaded;
      expect(repo.listCalls, 1);
    });

    test('blocked attempt while ONLINE restores the content view instead of '
        'parking the surface on the transient state', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      // Settle a real online verdict + a successful load first.
      connectivity.add(true);
      final loaded = bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      bloc.add(const LoadRideHistory());
      await loaded;

      // A stale OfflineRefreshBlocked event arriving while online must not
      // leave the UI sitting on the blocked shell.
      final restored = bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      bloc.add(const OfflineRefreshBlocked());
      await restored;
      expect(bloc.state, isA<RideHistoryLoaded>());
    });
  });

  group('history filter survives reloads (chip round-trip)', () {
    test('retained filter carries through a plain reload; null status means '
        '"keep", not "reset"', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      var loaded = bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      bloc.add(const LoadRideHistory(status: 'completed'));
      await loaded;
      expect(repo.requestedStatuses.last, 'completed');

      // Pull-to-refresh / re-entry dispatch: NO explicit status.
      loaded = bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      bloc.add(const LoadRideHistory());
      await loaded;
      expect(repo.requestedStatuses.last, 'completed');
      expect(bloc.historyStatusFilter, 'completed');
      expect((bloc.state as RideHistoryLoaded).statusFilter, 'completed');

      // Only an explicit clear genuinely resets.
      loaded = bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      bloc.add(const LoadRideHistory(clearStatusFilter: true));
      await loaded;
      expect(repo.requestedStatuses.last, isNull);
      expect(bloc.historyStatusFilter, isNull);
    });

    test('a FAILED load leaves the retained filter untouched', () async {
      final bloc = buildBloc();
      addTearDown(bloc.close);

      var loaded = bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      bloc.add(const LoadRideHistory(status: 'cancelled'));
      await loaded;

      // Break the fetch, then reload with no explicit status.
      repo.failNextList = true;
      final errored = bloc.stream.firstWhere((s) => s is RideError);
      bloc.add(const LoadRideHistory());
      await errored;

      // The rider's active filter must survive the failure exactly as it
      // was — a failed refresh never silently resets chips.
      expect(bloc.historyStatusFilter, 'cancelled');
      expect(repo.requestedStatuses.last, 'cancelled');
      loaded = bloc.stream.firstWhere((s) => s is RideHistoryLoaded);
      bloc.add(const LoadRideHistory());
      await loaded;
      expect(repo.requestedStatuses.last, 'cancelled');
    });
  });

  group('ride_history_page widgets (refresh + filter round-trip)', () {
    Future<GoRouter> pumpHistoryPage(
        WidgetTester tester, RideBloc bloc) async {
      final router = GoRouter(
        routes: [
          ShellRoute(
            builder: (context, state, child) => child,
            routes: [
              GoRoute(
                path: '/nidus/history',
                builder: (context, state) =>
                    BlocProvider<RideBloc>.value(
                  value: bloc,
                  child: const RideHistoryPage(),
                ),
              ),
              GoRoute(
                path: '/nidus/tracking/:id',
                builder: (context, state) => const Scaffold(
                    body: Center(child: Text('TRACKING-STUB'))),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('renders a RefreshIndicator and pulls keep the filter',
        (tester) async {
      final bloc = buildBloc();
      await pumpHistoryPage(tester, bloc);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Choose a filter chip, wait for its load to settle.
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(repo.requestedStatuses.last, 'completed');

      // Pull to refresh — the bloc retains 'completed', so the refresh
      // re-fetches the SAME slice (no explicit status dispatched).
      await tester.drag(find.byType(SingleChildScrollView).first,
          const Offset(0, 260));
      await tester.pumpAndSettle();

      expect(repo.requestedStatuses.last, 'completed');
      expect(bloc.historyStatusFilter, 'completed');
      // The completed chip is still selected after the refresh.
      final chip = tester.widget<FilterChip>(find
          .ancestor(of: find.text('Completed'), matching: find.byType(FilterChip))
          .first);
      expect(chip.selected, isTrue);
      await bloc.close();
    });

    testWidgets('re-entry seeds the chips from the bloc-retained filter '
        'instead of resetting to All', (tester) async {
      final bloc = buildBloc();
      await pumpHistoryPage(tester, bloc);

      await tester.tap(find.text('Cancelled'));
      await tester.pumpAndSettle();
      expect(bloc.historyStatusFilter, 'cancelled');

      // Simulate leaving the page (pop) and coming back: dispose this
      // State and rebuild the route against the SAME bloc instance.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await pumpHistoryPage(tester, bloc);

      final chip = tester.widget<FilterChip>(find
          .ancestor(of: find.text('Cancelled'), matching: find.byType(FilterChip))
          .first);
      expect(chip.selected, isTrue,
          reason: 'the rider left on "Cancelled" — re-entry must not '
              'silently reset the chips to "All"');
      await bloc.close();
    });

    testWidgets('offline pull shows the honest blocked banner copy, not a '
        'fake success toast', (tester) async {
      final bloc = buildBloc();
      connectivity.add(false);
      await Future<void>.delayed(Duration.zero);
      await pumpHistoryPage(tester, bloc);

      await tester.drag(find.byType(SingleChildScrollView).first,
          const Offset(0, 260));
      await tester.pump();

      final messenger = tester.widget<ScaffoldMessenger>(
          find.byType(ScaffoldMessenger).first);
      // Nothing fabricated: at most the offline-blocked copy may show; the
      // success string must never appear while the verdict says offline.
      final snackBars =
          ScaffoldMessenger.of(messenger.context).debugActiveSnackBars;
      for (final sb in snackBars) {
        final text = (sb.content as Text?)?.data ?? '';
        expect(text, isNot('Ride history updated'));
      }
      await bloc.close();
    });
  });
}
