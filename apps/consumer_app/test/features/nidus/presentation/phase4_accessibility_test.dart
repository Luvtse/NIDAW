// Phase 4 — Accessibility & Honest Degradation regression tests.
//
// Locks three contracts introduced in Phase 4:
//   1. DriverCard avatar honesty: when no driver photo is available the card
//      renders initials + an explicit semantic label ("photo unavailable"),
//      never a fake Icons.person silhouette sitting next to the real selfie
//      shown by VerifyDriverCard (the verify_driver_card.dart:28 rule).
//   2. DriverCard call/chat actions expose screen-reader semantics (button
//      role + localized action label), not just hover tooltips.
//   3. RideHistoryPage filter chips announce the ACTION they perform
//      ("Show completed rides only") with selected/mutually-exclusive group
//      state, and status glyphs announce their localized status instead of
//      being decorative icons.
//
// Harness: MaterialApp + AppLocalizations delegates (same pattern as
// driver_card_l10n_test.dart / ride_type_selector_l10n_test.dart) plus
// tester.ensureSemantics() so SemanticsNodes are emitted. This environment
// has no Flutter toolchain; the tests must run in CI (`flutter test`).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_app/features/nidus/data/repositories/ride_repository.dart';
import 'package:nidaw_app/features/nidus/data/repositories/safety_repository.dart';
import 'package:nidaw_app/features/nidus/domain/usecases/get_ride_status_usecase.dart';
import 'package:nidaw_app/features/nidus/domain/usecases/request_ride_usecase.dart';
import 'package:nidaw_app/features/nidus/presentation/bloc/ride_bloc.dart';
import 'package:nidaw_app/features/nidus/presentation/pages/ride_history_page.dart';
import 'package:nidaw_app/features/nidus/presentation/widgets/driver_card.dart';
import 'package:nidaw_app/l10n/generated/app_localizations.dart';

Widget _host(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

/// Repository stub serving exactly the rows the history page fetches.
class _A11yHistoryRepo implements RideRepository {
  List<Ride> rides = [];

  @override
  Future<RideListResult> listRides({
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    final filtered = status == null
        ? rides
        : rides.where((r) => r.status == status).toList();
    return RideListResult(
      rides: filtered,
      total: filtered.length,
      limit: limit,
      offset: offset,
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(
          '_A11yHistoryRepo.${invocation.memberName} must not be reached by '
          'the Phase 4 accessibility scenarios');
}

class _NoopSafetyRepo implements SafetyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('SafetyRepository must not be reached here');
}

Ride _ride({required String id, required String status}) => Ride(
      id: id,
      userId: 'user-1',
      pickupLat: 9.03,
      pickupLng: 38.74,
      dropoffLat: 9.05,
      dropoffLng: 38.76,
      pickupAddress: 'Bole Market',
      dropoffAddress: 'Kazanchis',
      rideType: 'standard',
      status: status,
      fareAmount: 150.0,
      currency: 'ETB',
      requestedAt: DateTime.utc(2026, 10, 1, 9, 30),
      completedAt: DateTime.utc(2026, 10, 1, 10, 15),
    );

void main() {
  const en = Locale('en');

  group('DriverCard honest degradation + semantics (Phase 4)', () {
    testWidgets('renders initials, NOT a fake Icons.person silhouette',
        (tester) async {
      await tester.ensureSemantics();
      await tester.pumpWidget(_host(
        en,
        DriverCard(
          driverName: 'Abebe Kebede',
          rating: 4.8,
          carModel: 'Toyota Corolla',
          plateNumber: '3ABC1234',
          eta: 5,
          onCall: () {},
          onChat: () {},
        ),
      ));
      await tester.pumpAndSettle();

      // The visible placeholder is the derived initials, not a generic icon.
      expect(find.text('AK'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);

      // And it announces honestly that no photo exists.
      final l10n = await AppLocalizations.delegate.load(en);
      expect(
        find.bySemanticsLabel(l10n.driverAvatarInitialsLabel('Abebe Kebede')),
        findsOneWidget,
      );
      tester.disposeSemantics();
    });

    testWidgets('call/chat buttons expose button-role semantics labels',
        (tester) async {
      await tester.ensureSemantics();
      await tester.pumpWidget(_host(
        en,
        DriverCard(
          driverName: 'Abebe Kebede',
          rating: 4.8,
          carModel: 'Toyota Corolla',
          plateNumber: '3ABC1234',
          eta: 5,
          onCall: () {},
          onChat: () {},
        ),
      ));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(en);

      final callNode = tester.getSemantics(
          find.descendant(
              of: find.byIcon(Icons.call), within: find.byType(Semantics)));
      expect(callNode.label, contains(l10n.driverCallTooltip));
      expect(callNode.hasFlag(SemanticsFlag.isButton), isTrue);

      final chatNode = tester.getSemantics(
          find.descendant(
              of: find.byIcon(Icons.message_outlined),
              within: find.byType(Semantics)));
      expect(chatNode.label, contains(l10n.driverChatTooltip));
      expect(chatNode.hasFlag(SemanticsFlag.isButton), isTrue);
      tester.disposeSemantics();
    });
  });

  group('RideHistoryPage semantics (Phase 4)', () {
    late _A11yHistoryRepo repo;
    late RideBloc bloc;

    setUp(() {
      repo = _A11yHistoryRepo()
        ..rides = [
          _ride(id: 'r1', status: 'completed'),
          _ride(id: 'r2', status: 'matched'),
        ];
      bloc = RideBloc(
        rideRepository: repo,
        requestRideUseCase: RequestRideUseCase(repo),
        getRideStatusUseCase: GetRideStatusUseCase(repo),
        safetyRepository: _NoopSafetyRepo(),
      );
    });

    tearDown(() => bloc.close());

    Future<void> pumpHistory(WidgetTester tester) async {
      await tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        locale: en,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<RideBloc>.value(
          value: bloc,
          child: const RideHistoryPage(),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('filter chips announce their action with selected state',
        (tester) async {
      await pumpHistory(tester);
      final l10n = await AppLocalizations.delegate.load(en);

      // Default selection: "All" chip is on, others off — announced via the
      // action-style label, not the bare one-word visual label.
      final allNode = tester.getSemantics(find
          .descendant(of: find.text(l10n.historyFilterAll),
              within: find.byType(Semantics))
          .first);
      expect(allNode.label, contains(l10n.historyFilterAllLabel));
      expect(allNode.hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(allNode.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);

      final completedNode = tester.getSemantics(find
          .descendant(of: find.text(l10n.historyFilterCompleted),
              within: find.byType(Semantics))
          .first);
      expect(completedNode.label, contains(l10n.historyFilterCompletedLabel));
      expect(completedNode.hasFlag(SemanticsFlag.isSelected), isFalse);
      tester.disposeSemantics();
    });

    testWidgets('status glyph carries a localized status announcement',
        (tester) async {
      await pumpHistory(tester);
      final l10n = await AppLocalizations.delegate.load(en);

      // 'matched' degrades honestly: the backend row has no driver attached
      // in this fixture, so the card must announce the localized status via
      // the glyph's Semantics wrapper — never a silent decorative icon and
      // never an English raw wire token.
      expect(
        find.bySemanticsLabel(
            l10n.historyStatusIconLabel(l10n.historyStatusMatched)),
        findsWidgets,
      );
      // The completed row announces its localized status too.
      expect(
        find.bySemanticsLabel(
            l10n.historyStatusIconLabel(l10n.historyFilterCompleted)),
        findsWidgets,
      );
      tester.disposeSemantics();
    });
  });
}
