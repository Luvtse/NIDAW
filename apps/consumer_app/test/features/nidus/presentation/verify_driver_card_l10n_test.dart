// Phase 3 — Core localization sweep (verify_driver_card.dart).
//
// Locks the honesty contract from the widget's doc header (§2.3): every
// pre-selfie state renders exactly one localized surface, and no English
// literal ships from verify_driver_card.dart itself. Amharic/Oromo cases
// assert the catalog strings render AND that the former literals
// ('Verify your driver', 'Driver did not send a selfie',
// 'Verification unavailable', 'Contact driver', ...) do not leak.
//
// The available-state card is rendered without tapping it, so no
// PreSelfieRepository is needed in GetIt; the tap-to-fetch path is covered
// by repository-level tests elsewhere.
//
// NOTE: this environment has no Flutter toolchain, so these tests are
// compile-unverified here; they follow the exact MaterialApp+delegates
// harness used by driver_card_l10n_test.dart and must pass in CI.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_app/features/nidus/data/repositories/pre_selfie_repository.dart';
import 'package:nidaw_app/features/nidus/presentation/widgets/verify_driver_card.dart';
import 'package:nidaw_app/l10n/generated/app_localizations.dart';

Widget _host(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

const _formerLiterals = <String>[
  'Verify your driver',
  'Driver did not send a selfie',
  'Verification unavailable',
  'Contact driver',
  'Profile photo (on file)',
  'Just-sent selfie',
  "That's not them",
  'Looks right',
];

void main() {
  const en = Locale('en');
  const am = Locale('am');
  const om = Locale('om');

  group('VerifyDriverCard localization (Phase 3)', () {
    testWidgets('available state uses catalog title + parameterized subtitle',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      await tester.pumpWidget(_host(
        en,
        VerifyDriverCard(
          preSelfie: PreSelfieInfo(
            state: PreSelfieState.available,
            url: '',
            redeemPath: '/api/v1/selfies/x?exp=1&sig=a',
            expiresAtUtc: null,
          ),
          driverName: 'Abebe Kebede',
          onRecheck: () {},
          onContactDriver: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(l10n.verifySelfieTitle), findsOneWidget);
      expect(
        find.text(l10n.verifySelfieSubtitle('Abebe Kebede')),
        findsOneWidget,
        reason: 'subtitle must interpolate the driver name via the catalog',
      );
    });

    testWidgets('notSent / expired / unavailable render localized honest copy',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);

      await tester.pumpWidget(_host(
        en,
        VerifyDriverCard(
          preSelfie: PreSelfieInfo(
            state: PreSelfieState.notSent,
            url: '',
            redeemPath: '',
            expiresAtUtc: null,
          ),
          driverName: 'Abebe Kebede',
          onRecheck: () {},
          onContactDriver: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(l10n.verifySelfieNotSentTitle), findsOneWidget);
      expect(find.text(l10n.verifySelfieNotSentSubtitle), findsOneWidget);
      expect(find.text(l10n.verifyContactDriver), findsOneWidget);

      await tester.pumpWidget(_host(
        en,
        VerifyDriverCard(
          preSelfie: PreSelfieInfo(
            state: PreSelfieState.expired,
            url: '',
            redeemPath: '',
            expiresAtUtc: null,
          ),
          driverName: 'Abebe Kebede',
          onRecheck: () {},
          onContactDriver: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(l10n.verifySelfieExpiredTitle), findsOneWidget);
      expect(find.text(l10n.verifyRefresh), findsOneWidget);

      // absent (flag off) and unknown both fold into honest-unavailable.
      for (final probe in [PreSelfieInfo.absent,
        PreSelfieInfo(
            state: PreSelfieState.unknown,
            url: '',
            redeemPath: '',
            expiresAtUtc: null)]) {
        await tester.pumpWidget(_host(
          en,
          VerifyDriverCard(
            preSelfie: probe,
            driverName: 'Abebe Kebede',
            onRecheck: () {},
            onContactDriver: () {},
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text(l10n.verifyUnavailableTitle), findsOneWidget);
        expect(find.text(l10n.verifyRetry), findsOneWidget);
      }
      // unknown gets the distinct "our side, not the driver" subtitle.
      expect(
        find.text(l10n.verifyUnavailableUnknownSubtitle),
        findsNothing, // last pump was `absent` -> generic subtitle
      );
      expect(find.text(l10n.verifyUnavailableSubtitle), findsOneWidget);
    });

    testWidgets('unknown wire value shows the blame-ours subtitle, never success',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      await tester.pumpWidget(_host(
        en,
        VerifyDriverCard(
          preSelfie: PreSelfieInfo(
            state: preSelfieStateFrom('garbage_from_backend'),
            url: '',
            redeemPath: '',
            expiresAtUtc: null,
          ),
          driverName: 'Abebe Kebede',
          onRecheck: () {},
          onContactDriver: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(l10n.verifyUnavailableTitle), findsOneWidget);
      expect(find.text(l10n.verifyUnavailableUnknownSubtitle), findsOneWidget);
      expect(find.text(l10n.verifySelfieTitle), findsNothing);
    });

    testWidgets('Amharic card renders catalog strings, no English leak',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(am);
      await tester.pumpWidget(_host(
        am,
        VerifyDriverCard(
          preSelfie: PreSelfieInfo(
            state: PreSelfieState.notSent,
            url: '',
            redeemPath: '',
            expiresAtUtc: null,
          ),
          driverName: 'Abebe Kebede',
          onRecheck: () {},
          onContactDriver: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(l10n.verifySelfieNotSentTitle), findsOneWidget);
      expect(find.text(l10n.verifyContactDriver), findsOneWidget);
      for (final lit in _formerLiterals) {
        expect(find.textContaining(lit), findsNothing,
            reason: '"$lit" must not ship from the widget in Amharic');
      }
    });

    testWidgets('Oromo card renders catalog strings, no English leak',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(om);
      await tester.pumpWidget(_host(
        om,
        VerifyDriverCard(
          preSelfie: PreSelfieInfo(
            state: PreSelfieState.available,
            url: '',
            redeemPath: '/api/v1/selfies/x?exp=1&sig=a',
            expiresAtUtc: null,
          ),
          driverName: 'Abebe Kebede',
          onRecheck: () {},
          onContactDriver: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(l10n.verifySelfieTitle), findsOneWidget);
      expect(find.text(l10n.verifySelfieSubtitle('Abebe Kebede')),
          findsOneWidget);
      for (final lit in _formerLiterals) {
        expect(find.textContaining(lit), findsNothing,
            reason: '"$lit" must not ship from the widget in Oromo');
      }
    });
  });

  group('SelfieComparisonView localization (Phase 3)', () {
    // 1x1 transparent PNG so Image.memory decodes without network.
    final png = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

    testWidgets('panels, expiry note and verdict buttons come from catalog',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      await tester.pumpWidget(_host(
        en,
        SelfieComparisonView(
          driverName: 'Abebe Kebede',
          selfieBytes: png,
          profilePhotoBytes: null,
          expiresAtUtc: DateTime.utc(2026, 11, 1, 12, 30),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(l10n.verifyComparisonAppBarTitle('Abebe')),
          findsOneWidget);
      expect(find.text(l10n.verifyPanelProfileLabel), findsOneWidget);
      expect(find.text(l10n.verifyPanelSelfieLabel), findsOneWidget);
      // Honest degradation: missing profile photo is STATED, not faked.
      expect(find.text(l10n.verifyPanelProfileMissing), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing,
          reason: 'no placeholder avatar may impersonate the registered photo');
      expect(find.text(l10n.verifyButtonNotThem), findsOneWidget);
      expect(find.text(l10n.verifyButtonLooksRight), findsOneWidget);
      // Expiry note interpolates the formatted timestamp through the catalog.
      final expectedNote = l10n.verifyExpiryNote('2026-11-01 12:30');
      expect(find.text(expectedNote), findsOneWidget);
    });

    testWidgets('Amharic comparison view leaks no English literals',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(am);
      await tester.pumpWidget(_host(
        am,
        SelfieComparisonView(
          driverName: 'Abebe Kebede',
          selfieBytes: png,
          profilePhotoBytes: png,
          expiresAtUtc: null,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(l10n.verifyPanelProfileLabel), findsOneWidget);
      expect(find.text(l10n.verifyButtonLooksRight), findsOneWidget);
      for (final lit in _formerLiterals) {
        expect(find.textContaining(lit), findsNothing,
            reason: '"$lit" must not ship from the comparison view in Amharic');
      }
    });
  });

  // The unknown-state mapping the widget's honesty contract relies on.
  test('preSelfieStateFrom folds unrecognized values into unknown', () {
    expect(preSelfieStateFrom('garbage_from_backend'), PreSelfieState.unknown);
    expect(preSelfieStateFrom(null), PreSelfieState.unknown);
    expect(
        PreSelfieInfo.fromJson({'state': 'not_sent'}).state,
        PreSelfieState.notSent);
  });
}
