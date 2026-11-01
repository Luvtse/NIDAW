// Phase 3 — Core localization sweep (driver_card.dart).
//
// Locks the contract that every user-facing string on the tracking driver
// card routes through the ARB catalog: the call/chat tooltips and the ETA
// unit label must resolve from context.l10n, never ship as English literals
// from driver_card.dart itself. Amharic/Oromo cases assert the localized
// strings render and the former English literals ('Call driver using masked
// number', 'Chat with driver', 'min') do NOT leak.
//
// NOTE: this environment has no Flutter toolchain, so these tests are
// compile-unverified here; they follow the exact MaterialApp+delegates
// harness pattern used across this repo's widget tests (see
// ride_type_selector_l10n_test.dart) and must pass in CI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_app/features/nidus/presentation/widgets/driver_card.dart';
import 'package:nidaw_app/l10n/generated/app_localizations.dart';

Widget _host(Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DriverCard(
          driverName: 'Abebe Kebede',
          rating: 4.8,
          carModel: 'Toyota Corolla',
          plateNumber: '3ABC1234',
          eta: 5,
          onCall: () {},
          onChat: () {},
        ),
      ),
    );

void main() {
  const en = Locale('en');
  const am = Locale('am');
  const om = Locale('om');

  group('DriverCard localization (Phase 3)', () {
    testWidgets('English card resolves tooltip/unit strings from catalog',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      await tester.pumpWidget(_host(en));
      await tester.pumpAndSettle();

      // IconButton tooltips surface as Tooltip widgets in the tree.
      expect(
        find.byTooltip(l10n.driverCallTooltip),
        findsOneWidget,
        reason: 'call action must use the localized catalog tooltip',
      );
      expect(
        find.byTooltip(l10n.driverChatTooltip),
        findsOneWidget,
        reason: 'chat action must use the localized catalog tooltip',
      );
      expect(find.text(l10n.driverEtaMinutesUnit), findsOneWidget);
      // Data lines still render.
      expect(find.text('Abebe Kebede'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('Amharic card renders localized tooltips/unit, no English leak',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(am);
      await tester.pumpWidget(_host(am));
      await tester.pumpAndSettle();

      expect(find.byTooltip(l10n.driverCallTooltip), findsOneWidget);
      expect(find.byTooltip(l10n.driverChatTooltip), findsOneWidget);
      expect(find.text(l10n.driverEtaMinutesUnit), findsOneWidget);

      // The pre-sweep English literals must not appear anywhere.
      expect(l10n.driverCallTooltip, isNot('Call driver using masked number'));
      expect(find.text('Call driver using masked number'), findsNothing);
      expect(find.text('Chat with driver'), findsNothing);
      expect(find.text('min'), findsNothing);
    });

    testWidgets('Oromo card renders localized tooltips/unit, no English leak',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(om);
      await tester.pumpWidget(_host(om));
      await tester.pumpAndSettle();

      expect(find.byTooltip(l10n.driverCallTooltip), findsOneWidget);
      expect(find.byTooltip(l10n.driverChatTooltip), findsOneWidget);
      expect(find.text(l10n.driverEtaMinutesUnit), findsOneWidget);

      expect(l10n.driverCallTooltip, isNot('Call driver using masked number'));
      expect(find.text('Call driver using masked number'), findsNothing);
      expect(find.text('Chat with driver'), findsNothing);
      expect(find.text('min'), findsNothing);
    });
  });
}
