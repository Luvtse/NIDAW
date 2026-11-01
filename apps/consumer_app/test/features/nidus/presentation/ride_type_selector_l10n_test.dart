// Phase 3 — Dead-code resolution / Core localization sweep (verification).
//
// Locks the contract that every user-facing string on a ride-option card
// routes through the ARB catalog: no English literals ('CHOSEN', 'ETA
// unavailable', 'Capacity not provided', 'Unavailable', 'N seats',
// 'N min away') ship from ride_type_selector.dart itself. The degraded-state
// headline labels are injected by the page; the per-card strings resolve from
// context.l10n inside the widget.
//
// Also pins the honest-degradation rule for RideOptionEstimate.etaMinutes:
// an omitted server ETA renders the localized "ETA unavailable" line, never
// a fabricated "0 min away"; a real 0 renders the =0 plural case.
//
// NOTE: this environment has no Flutter toolchain, so these tests are
// compile-unverified here; they follow the exact MaterialApp+delegates
// harness pattern used across this repo's widget tests and must pass in CI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_app/features/nidus/data/repositories/ride_repository.dart';
import 'package:nidaw_app/features/nidus/presentation/widgets/ride_type_selector.dart';
import 'package:nidaw_app/l10n/generated/app_localizations.dart';

RideOptionEstimate _option({
  String rideType = 'standard',
  int? etaMinutes,
  int? capacity,
  bool available = true,
}) =>
    RideOptionEstimate(
      rideType: rideType,
      displayName: rideType,
      totalFare: 100,
      surgeMultiplier: 1.0,
      currency: 'ETB',
      etaMinutes: etaMinutes,
      available: available,
      capacity: capacity,
    );

Widget _host(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  const en = Locale('en');
  const am = Locale('am');

  group('RideTypeSelector localization (Phase 3)', () {
    testWidgets('English card uses catalog strings, not widget literals',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      await tester.pumpWidget(_host(en, RideTypeSelector(
        selectedType: 'standard',
        onTypeSelected: (_) {},
        pricesUnavailableLabel: l10n.requestOptionsPricesUnavailable,
        setRouteFirstLabel: l10n.requestOptionsSetRouteFirst,
        retryLabel: l10n.commonRetry,
        options: [
          _option(etaMinutes: 5, capacity: 4),
          _option(rideType: 'premium', etaMinutes: 0, capacity: 1),
          // Omitted capacity + omitted ETA => honest localized degradation.
          _option(rideType: 'shared', available: false),
        ],
      )));
      await tester.pumpAndSettle();

      expect(find.text(l10n.requestOptionChosenBadge), findsOneWidget);
      expect(find.text(l10n.requestOptionEtaMinutes(5)), findsOneWidget);
      expect(find.text(l10n.requestOptionEtaMinutes(0)), findsOneWidget);
      // The 'shared' fixture omits capacity AND ETA — its line renders the
      // localized "Capacity not provided" label, and the unavailable card's
      // seat count never leaks as the English literal 'N seats'.
      expect(find.text(l10n.requestOptionCapacityUnknown), findsWidgets);
      expect(find.text(l10n.requestOptionEtaUnavailable), findsOneWidget);
      expect(find.text(l10n.requestOptionUnavailable), findsOneWidget);
      // Never fabricate a zero-ETA for an omitted value.
      expect(find.text('0 min away'), findsNothing);
    });

    testWidgets('Amharic card renders Ethiopic catalog strings', (tester) async {
      final l10n = await AppLocalizations.delegate.load(am);
      await tester.pumpWidget(_host(am, RideTypeSelector(
        selectedType: 'standard',
        onTypeSelected: (_) {},
        pricesUnavailableLabel: l10n.requestOptionsPricesUnavailable,
        setRouteFirstLabel: l10n.requestOptionsSetRouteFirst,
        retryLabel: l10n.commonRetry,
        options: [_option(etaMinutes: 5, capacity: 4)],
      )));
      await tester.pumpAndSettle();

      expect(find.text(l10n.requestOptionChosenBadge), findsOneWidget);
      expect(find.text(l10n.requestOptionEtaMinutes(5)), findsOneWidget);
      expect(find.text(l10n.requestOptionSeats(4)), findsOneWidget);
      // No English literals leak into the am surface.
      expect(find.text('CHOSEN'), findsNothing);
      expect(find.text('5 min away'), findsNothing);
      expect(find.text('4 seats'), findsNothing);
    });

    testWidgets('Oromo card renders catalog strings', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('om'));
      await tester.pumpWidget(_host(const Locale('om'), RideTypeSelector(
        selectedType: 'standard',
        onTypeSelected: (_) {},
        pricesUnavailableLabel: l10n.requestOptionsPricesUnavailable,
        setRouteFirstLabel: l10n.requestOptionsSetRouteFirst,
        retryLabel: l10n.commonRetry,
        options: [_option(etaMinutes: 7, capacity: 2, available: false)],
      )));
      await tester.pumpAndSettle();

      expect(find.text(l10n.requestOptionEtaMinutes(7)), findsOneWidget);
      expect(find.text(l10n.requestOptionSeats(2)), findsOneWidget);
      expect(find.text(l10n.requestOptionUnavailable), findsOneWidget);
      expect(find.text('7 min away'), findsNothing);
    });

    testWidgets('failure strip shows localized headline + retry action',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      var retries = 0;
      await tester.pumpWidget(_host(en, RideTypeSelector(
        selectedType: 'standard',
        onTypeSelected: (_) {},
        pricesUnavailableLabel: l10n.requestOptionsPricesUnavailable,
        setRouteFirstLabel: l10n.requestOptionsSetRouteFirst,
        retryLabel: l10n.commonRetry,
        error: 'estimates endpoint down',
        onRetry: () => retries++,
      )));
      await tester.pumpAndSettle();

      // Phase 3 exit criterion: failing estimate path keeps a user-reachable,
      // localized retry after dead-code reconnect.
      expect(find.text(l10n.requestOptionsPricesUnavailable), findsOneWidget);
      expect(find.text(l10n.commonRetry), findsOneWidget);
      await tester.tap(find.text(l10n.commonRetry));
      expect(retries, 1);
      // Raw server detail is demoted to secondary text, not the headline.
      expect(find.text('estimates endpoint down'), findsOneWidget);
    });
  });

  group('RideOptionEstimate honest degradation (Phase 3)', () {
    test('fromJson maps omitted ETA to null, not 0', () {
      final option = RideOptionEstimate.fromJson(const {
        'ride_type': 'standard',
        'total_fare': 100,
        'surge_multiplier': 1.0,
        'currency': 'ETB',
        'available': true,
      });
      expect(option.etaMinutes, isNull);
      expect(option.capacity, isNull);
    });

    test('fromJson preserves a real zero ETA', () {
      final option = RideOptionEstimate.fromJson(const {
        'ride_type': 'standard',
        'total_fare': 100,
        'surge_multiplier': 1.0,
        'currency': 'ETB',
        'estimated_pickup_minutes': 0,
        'available': true,
      });
      expect(option.etaMinutes, 0);
    });
  });
}
