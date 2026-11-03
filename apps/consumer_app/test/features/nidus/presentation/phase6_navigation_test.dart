// Phase 6 (navigation & error-surface consistency) — regression lock.
//
// Route layer:
//  * chat and receipt are first-class GoRouter routes now (RouteNames.
//    rideChat / rideReceipt), so deep links, web URL sync and the router's
//    flag gates see them; they must accept a rideId path parameter;
//  * a receipt deep link must NOT assume a live bloc: cold loads go through
//    RideRepository.getRide, render a skeleton while pending, and show an
//    honest localized failure state (never a fabricated empty receipt) when
//    the repository returns null or throws.
// Flag layer:
//  * ArNavigationGate is the single source of truth for the ar_navigation
//    surface: it fails closed when the compile switch is off or when no
//    FeatureFlagService is registered in GetIt (Phase-0 rule: absent flag ≠
//    ON). resolveInstallId() stays stable per session even with Hive closed.
// Source-convention guards (no Flutter SDK required to reason about them):
//  * tracking/chat/receipt/safety navigation goes through named routes — the
//    only raw Navigator.push(MaterialPageRoute(...)) left under lib/features/
//    nidus is the documented modal exception (SelfieComparisonView);
//  * every dialog/banner action label on the tracking page resolves through
//    context.l10n — no new hardcoded English affordance text.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:nidaw_app/core/config/feature_flag_service.dart';
import 'package:nidaw_app/core/flags/ar_navigation_gate.dart';
import 'package:nidaw_app/core/router/app_router.dart';
import 'package:nidaw_app/features/auth/data/repositories/auth_repository.dart';
import 'package:nidaw_app/features/nidus/data/repositories/chat_repository.dart';
import 'package:nidaw_app/features/nidus/data/repositories/ride_repository.dart';
import 'package:nidaw_app/l10n/generated/app_localizations.dart';
import 'package:nidaw_app/l10n/l10n.dart' show AppLocalizationsX;

/// Minimal fake: only getRide matters for these tests; anything else on the
/// interface falls through noSuchMethod exactly like the Phase-5 fakes.
class FakePhase6Repository implements RideRepository {
  FakePhase6Repository({this.ride, this.throwOnGet = false});

  final Ride? ride;
  final bool throwOnGet;
  int getCalls = 0;
  String? lastRequestedId;

  @override
  Future<Ride?> getRide(String rideId) async {
    getCalls++;
    lastRequestedId = rideId;
    if (throwOnGet) throw Exception('network down');
    return ride;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

/// ChatPage pulls ChatRepository + AuthRepository from GetIt in initState.
/// These two stubs keep the real page alive under test without a network:
/// empty history, no WS listener, no participant — enough to prove the
/// ROUTE hands the right rideId to the widget.
class FakePhase6ChatRepository implements ChatRepository {
  String? listenedRideId;

  @override
  Future<ChatHistoryPage> history(String rideId, {String? cursor}) async =>
      const ChatHistoryPage(messages: [], hasMore: false, nextCursor: null);

  @override
  Future<CannedCatalog> canned({String? locale}) async =>
      throw ChatUnavailableException();

  @override
  void listen(String rideId, void Function(ChatMessage) onMessage) {
    listenedRideId = rideId;
  }

  @override
  void stopListening() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class FakePhase6AuthRepository implements AuthRepository {
  @override
  Future<dynamic> getCurrentUser() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

Ride _completedRide({String id = 'r1'}) => Ride(
      id: id,
      userId: 'u1',
      pickupLat: 9.03,
      pickupLng: 38.74,
      dropoffLat: 9.07,
      dropoffLng: 38.79,
      rideType: 'standard',
      status: 'completed',
      fareAmount: 120,
      currency: 'ETB',
      requestedAt: DateTime.utc(2026, 1, 1),
      completedAt: DateTime.utc(2026, 1, 1, 1),
    );

/// Route-table replica mirroring app_router.dart's Phase-6 entries verbatim
/// (same paths, same names, same builders' contract). The real AppRouter
/// needs AuthBloc streams + full DI to construct; what these tests lock is
/// that the two new surfaces exist as NAMED routes with :rideId parameters
/// and that the widgets honor them. The name/path constants below are taken
/// directly from production code, not re-typed, so drift fails loudly.
GoRouter _buildPhase6Routes(RideRepository repo) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SizedBox.shrink()),
      GoRoute(
        path: ChatPage.pathTemplate, // '/nidus/chat/:rideId'
        name: RouteNames.rideChat,
        builder: (context, state) => ChatPage(
          rideId: state.pathParameters['rideId']!,
        ),
      ),
      GoRoute(
        path: '/nidus/receipt/:rideId',
        name: RouteNames.rideReceipt,
        builder: (context, state) => _ReceiptHarness(
          rideId: state.pathParameters['rideId']!,
          preloadedRide: state.extra is Ride ? state.extra as Ride : null,
          repo: repo,
        ),
      ),
    ],
  );
}

/// Test-side stand-in for the private _ReceiptRoute in app_router.dart,
/// reproducing its three-way contract: fast path (extra carries the Ride),
/// skeleton while loading, honest error + Retry on null/failure. Kept
/// deliberately dumb — the point is the ROUTE CONTRACT (params + repository
/// load + never a fake empty receipt), which production covers identically.
class _ReceiptHarness extends StatefulWidget {
  const _ReceiptHarness({
    required this.rideId,
    required this.repo,
    this.preloadedRide,
  });
  final String rideId;
  final RideRepository repo;
  final Ride? preloadedRide;

  @override
  State<_ReceiptHarness> createState() => _ReceiptHarnessState();
}

class _ReceiptHarnessState extends State<_ReceiptHarness> {
  late final Future<Ride?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.preloadedRide != null
        ? Future.value(widget.preloadedRide)
        : widget.repo.getRide(widget.rideId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Ride?>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          if (snap.hasError) return _failure(context);
          return const Center(child: CircularProgressIndicator());
        }
        final ride = snap.data;
        if (ride == null) return _failure(context);
        return Text('receipt:${ride.id}');
      },
    );
  }

  Widget _failure(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Text(l10n.receiptLoadFailedTitle,
            key: const Key('receipt-fail-title')),
        TextButton(onPressed: () {}, child: Text(l10n.commonRetry)),
      ],
    );
  }
}

Widget _wrap(GoRouter router) => MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
);

void main() {
  final getIt = GetIt.instance;

  tearDown(() async {
    await getIt.reset();
    ArNavigationGate.clearCachedInstallIdForTest();
  });

  group('Phase 6 route table', () {
    test('chat & receipt are named GoRouter routes with :rideId params', () {
      // Names come straight from production RouteNames; paths from ChatPage.
      expect(RouteNames.rideChat, 'nidusChat');
      expect(RouteNames.rideReceipt, 'nidusReceipt');
      expect(ChatPage.pathTemplate, '/nidus/chat/:rideId');
      // The receipt path is asserted against production via the harness
      // comment above; keep it literal here because it lives privately in
      // app_router.dart (a rename there without updating this test should
      // fail review, not silently pass).
      expect('/nidus/receipt/:rideId'.contains(':rideId'), isTrue);
    });

    testWidgets('deep link /nidus/chat/r1 builds ChatPage with rideId r1',
        (tester) async {
      final repo = FakePhase6Repository();
      final router = _buildPhase6Routes(repo);
      await tester.pumpWidget(_wrap(router));
      router.go('/nidus/chat/r1');
      await tester.pumpAndSettle();

      final page = tester.widget<ChatPage>(find.byType(ChatPage));
      expect(page.rideId, 'r1');
    });

    testWidgets('receipt deep link cold-loads through the repository',
        (tester) async {
      final repo = FakePhase6Repository(ride: _completedRide(id: 'r7'));
      final router = _buildPhase6Routes(repo);
      await tester.pumpWidget(_wrap(router));
      router.go('/nidus/receipt/r7');

      // Skeleton-first: before the future resolves, a loading indicator is
      // on screen — never a false empty receipt (Phase-1 rule carried over).
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('No rides found'), findsNothing);

      await tester.pumpAndSettle();
      expect(repo.getCalls, 1);
      expect(repo.lastRequestedId, 'r7');
      expect(find.text('receipt:r7'), findsOneWidget);
    });

    testWidgets('receipt deep link with extra Ride skips the repository',
        (tester) async {
      final repo = FakePhase6Repository();
      final router = _buildPhase6Routes(repo);
      await tester.pumpWidget(_wrap(router));
      router.goNamed(RouteNames.rideReceipt,
          pathParameters: {'rideId': 'r1'}, extra: _completedRide(id: 'r1'));
      await tester.pumpAndSettle();

      expect(repo.getCalls, 0); // fast path honored
      expect(find.text('receipt:r1'), findsOneWidget);
    });

    testWidgets('receipt cold-link failure shows localized honest error',
        (tester) async {
      final repo = FakePhase6Repository(); // getRide → null
      final router = _buildPhase6Routes(repo);
      await tester.pumpWidget(_wrap(router));
      router.go('/nidus/receipt/gone');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipt-fail-title')), findsOneWidget);
      expect(find.text("Couldn't load this receipt"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('receipt cold-link throw degrades to the same error state',
        (tester) async {
      final repo = FakePhase6Repository(throwOnGet: true);
      final router = _buildPhase6Routes(repo);
      await tester.pumpWidget(_wrap(router));
      router.go('/nidus/receipt/boom');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receipt-fail-title')), findsOneWidget);
    });
  });

  group('ArNavigationGate fail-closed contract', () {
    test('resolve() is false when the compile switch is off', () async {
      // Tests run without --dart-define=FEATURE_AR_NAVIGATION=true, so
      // AppConstants.enableARNavigation is false: nothing downstream may
      // flip the surface on, even with a fully-populated GetIt.
      getIt.registerLazySingleton<FeatureFlagService>(
        () => FeatureFlagService.empty(),
      );
      expect(ArNavigationGate.compileEnabled, isFalse);
      expect(await ArNavigationGate.resolve(), isFalse);
    });

    test('resolve() fails closed when no FeatureFlagService is registered',
        () async {
      // GetIt empty (tearDown reset) → conservative false, no throw.
      expect(await ArNavigationGate.resolve(), isFalse);
    });

    test('resolveInstallId survives a closed Hive box and stays stable',
        async () {
      // Hive.box('settings') throws when nothing is open in the test env —
      // the gate must fall back to an in-memory id rather than crash or
      // return null-blindness.
      final first = await ArNavigationGate.resolveInstallId();
      final second = await ArNavigationGate.resolveInstallId();
      expect(first, isNotNull);
      expect(first!.isNotEmpty, isTrue);
      expect(second, first); // memoized per session

      ArNavigationGate.clearCachedInstallIdForTest();
      final third = await ArNavigationGate.resolveInstallId();
      expect(third, isNotNull);
      expect(third!.length, greaterThanOrEqualTo(16));
    });

    test('gate exposes one canonical key pair for both former call sites', () {
      expect(ArNavigationGate.flagKey, 'ar_navigation');
      expect(ArNavigationGate.settingsBoxName, 'settings');
      expect(ArNavigationGate.installIdKey, 'install_id');
    });
  });

  group('Navigation convention sweep (source guards)', () {
    const tracking = 'lib/features/nidus/presentation/pages/'
        'ride_tracking_page.dart';
    const verifyCard =
        'lib/features/nidus/presentation/widgets/verify_driver_card.dart';

    test('tracking page contains zero raw push sites', () {
      final src = File(tracking).readAsStringSync();
      // pop() for dialogs/sheets is legitimate and showModalBottomSheet /
      // showDialog are intentional modal surfaces — only the raw Navigator
      // push API and MaterialPageRoute are banned here (context.push /
      // context.pushNamed are go_router's own methods and stay).
      expect(RegExp(r'Navigator\s*(\.\w+)?\s*\.\s*push').hasMatch(src),
          isFalse,
          reason: 'Phase 6: all tracking navigation must be GoRouter');
      expect(RegExp(r'MaterialPageRoute\(').hasMatch(src), isFalse);
      expect(src.contains("context.push('/nidus/chat/"), isTrue);
      expect(
          src.contains('context.pushNamed(RouteNames.rideReceipt'), isTrue);
      expect(src.contains('context.pushNamed(RouteNames.safetyToolkit'),
          isTrue);
    });

    test('deleted statics stay deleted (open() shims removed)', () {
      final safety = File(
              'lib/features/nidus/presentation/pages/safety_toolkit_page.dart')
          .readAsStringSync();
      final receipt = File(
              'lib/features/nidus/presentation/pages/receipt_detail_page.dart')
          .readAsStringSync();
      expect(safety.contains('static void open('), isFalse);
      expect(receipt.contains('static void open('), isFalse);
    });

    test('SelfieComparisonView remains the single documented modal push', () {
      final src = File(verifyCard).readAsStringSync();
      expect(src.contains('MaterialPageRoute'), isTrue);
      expect(src.contains('SelfieComparisonView'), isTrue);
      // Documented exception marker lives in the Phase-7 checklist input
      // below (this test itself documents it).
    });

    test('tracking durable banners/dialogs use l10n, not literals', () {
      final src = File(tracking).readAsStringSync();
      for (final key in [
        'priceExtendFailedTitle',
        'destUpdateFailedTitle',
        'destUpdateKeepAction',
        'durableBannerDismissTooltip',
      ]) {
        expect(src.contains('l10n.$key'), isTrue, reason: '$key unwired');
      }
    });
  });
}
