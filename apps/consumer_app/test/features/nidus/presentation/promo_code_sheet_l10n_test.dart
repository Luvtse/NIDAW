// Phase 3 — Core localization sweep (promo_code_sheet.dart).
//
// Locks two things:
//  1. Every user-facing string in the §3.2 promo-code sheet resolves through
//     the generated catalog (en/am/om), and none of the former English
//     literals ('Promo code', 'Validate & apply', 'Your codes', 'Use', ...)
//     leak on am/om surfaces. The Oromo rows additionally guard against the
//     earlier seeding bug that shipped Amharic text under `om`.
//  2. The honesty contract from the widget's doc header survives migration:
//     discount/cap/min-fare numbers come verbatim from the server DTO, only
//     the surrounding words are localized, a real server failure reason
//     stays PRIMARY, and the localized fallback copy appears only when the
//     message is absent or empty.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nidaw_app/core/di/injection.dart' show getIt;
import 'package:nidaw_app/features/nidus/data/repositories/phase2_money_repository.dart';
import 'package:nidaw_app/features/nidus/presentation/widgets/promo_code_sheet.dart';
import 'package:nidaw_app/l10n/generated/app_localizations.dart';

/// No-network fake for GET /promotions/mine + POST /promotions/redeem.
/// Implements (rather than extends) the concrete repository so no ApiClient
/// is ever constructed; unimplemented members hit noSuchMethod on purpose.
class _FakeMoneyRepo implements Phase2MoneyRepository {
  _FakeMoneyRepo();

  PromoListResult? nextList;
  PromoRedeemResult? nextRedeem;

  int redeemCalls = 0;
  String? lastRedeemCode;

  @override
  Future<PromoListResult> listMyPromos() async =>
      nextList ?? const PromoListResult.success([]);

  @override
  Future<PromoRedeemResult> redeemPromo({
    required String code,
    required double fare,
    required String currency,
    String? rideType,
  }) async {
    redeemCalls++;
    lastRedeemCode = code;
    return nextRedeem ??
        const PromoRedeemResult.failure(
            message: '', code: 'EMPTY_SERVER_MESSAGE');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Widget _host(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

const _percentCode = PromoCodeInfo(
  code: 'NIDUS20',
  type: 'percent',
  value: 20,
  maxDiscount: 50,
  minFare: 100,
  validTo: null,
);

const _fixedCode = PromoCodeInfo(
  code: 'ETB10',
  type: 'fixed',
  value: 10,
  minFare: 0,
  validTo: null,
);

/// Former English literals from the pre-migration sheet. Must never appear
/// on am/om surfaces.
const _formerLiterals = <String>[
  'Promo code',
  'Remove',
  'Validate & apply',
  'Checking…',
  'Your codes',
  'Could not load your saved codes.',
  'No active codes yet',
  'This code could not be validated.',
  'Enter a promo code first.',
  'Needs an estimated fare first',
  'Set pickup and destination',
  'min away', // cross-surface guard: promo rows must not reuse ETA copy
];

void main() {
  const en = Locale('en');
  const am = Locale('am');
  const om = Locale('om');

  late _FakeMoneyRepo repo;

  setUp(() {
    repo = _FakeMoneyRepo();
    if (!getIt.isRegistered<Phase2MoneyRepository>()) {
      getIt.registerSingleton<Phase2MoneyRepository>(repo);
    }
  });

  tearDown(() {
    if (getIt.isRegistered<Phase2MoneyRepository>()) {
      getIt.unregister<Phase2MoneyRepository>();
    }
  });

  Future<void> pumpSheet(WidgetTester tester, Locale locale,
      {double? estimatedFare = 150}) async {
    await tester.pumpWidget(_host(
      locale,
      PromoCodeSheet(
        estimatedFare: estimatedFare,
        currency: 'ETB',
        rideType: 'standard',
        onApplied: (_, __) {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('PromoCodeSheet localization (Phase 3)', () {
    testWidgets('en: title/hint/buttons render from catalog', (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      await pumpSheet(tester, en);
      expect(find.text(l10n.promoCodeTitle), findsOneWidget);
      expect(find.text(l10n.promoCodeHint), findsOneWidget);
      expect(find.text(l10n.promoCodeValidateApply), findsOneWidget);
      expect(find.text(l10n.promoCodeYourCodes), findsOneWidget);
      // Empty list is a calm state with its own honest copy.
      expect(find.text(l10n.promoCodeEmpty), findsOneWidget);
    });

    testWidgets('am: catalog strings render, former English literals absent',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(am);
      await pumpSheet(tester, am);
      expect(find.text(l10n.promoCodeTitle), findsOneWidget);
      expect(find.text(l10n.promoCodeValidateApply), findsOneWidget);
      expect(find.text(l10n.promoCodeYourCodes), findsOneWidget);
      for (final lit in _formerLiterals) {
        expect(find.textContaining(lit), findsNothing,
            reason: 'English literal "$lit" leaked into Amharic surface');
      }
    });

    testWidgets('om: Latin-script Afaan Oromoo renders, no Amharic leak',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(om);
      await pumpSheet(tester, om);
      expect(find.text(l10n.promoCodeTitle), findsOneWidget);
      expect(find.text(l10n.promoCodeValidateApply), findsOneWidget);
      // Regression guard for the seeding bug that duplicated Amharic under
      // `om`: every rendered promo string must be Latin script.
      for (final s in [
        l10n.promoCodeTitle,
        l10n.promoCodeValidateApply,
        l10n.promoCodeYourCodes,
        l10n.promoCodeEmpty,
      ]) {
        expect(s, isNot(contains(RegExp(r'[\u1200-\u137F]'))),
            reason: 'Amharic text leaked into the Oromo catalog: $s');
      }
      for (final lit in _formerLiterals) {
        expect(find.textContaining(lit), findsNothing,
            reason: 'English literal "$lit" leaked into Oromo surface');
      }
    });

    testWidgets('needs-fare hint appears only without an estimate',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      await pumpSheet(tester, en, estimatedFare: null);
      expect(find.text(l10n.promoCodeNeedsFare), findsOneWidget);
      await pumpSheet(tester, en, estimatedFare: 150);
      expect(find.text(l10n.promoCodeNeedsFare), findsNothing);
    });

    testWidgets('saved-code rows: server numbers verbatim inside localized copy',
        (tester) async {
      repo.nextList = const PromoListResult.success([_percentCode, _fixedCode]);
      final l10n = await AppLocalizations.delegate.load(en);
      await pumpSheet(tester, en);
      expect(find.text(_percentCode.code), findsOneWidget);
      expect(find.text(_fixedCode.code), findsOneWidget);
      expect(find.text(l10n.promoCodeUse), findsNWidgets(2));
      // Percent row: all four fragments, numbers exactly as the DTO sent.
      expect(find.textContaining(l10n.promoOffPercent('20')), findsOneWidget);
      expect(find.textContaining(l10n.promoMaxCap('ETB', '50.00')), findsOneWidget);
      expect(find.textContaining(l10n.promoMinFare('ETB', '100.00')),
          findsOneWidget);
      // Fixed row: no cap/min-fare fragments (both absent in the DTO).
      expect(find.textContaining(l10n.promoOffFixed('ETB', '10.00')),
          findsOneWidget);
      // Localized labels around the numbers — never the raw English glue.
      expect(find.textContaining('% off'), findsNothing);
      expect(find.textContaining('min fare '), findsNothing);
    });

    testWidgets('load failure shows honest retry affordance', (tester) async {
      repo.nextList = const PromoListResult.failure(
          message: 'boom', code: 'SERVER');
      final l10n = await AppLocalizations.delegate.load(en);
      await pumpSheet(tester, en);
      expect(find.text(l10n.promoCodeLoadFailed), findsOneWidget);
      expect(find.text(l10n.promoCodeRetry), findsOneWidget);
      // Retry re-queries and recovers to the success view.
      repo.nextList = const PromoListResult.success([_fixedCode]);
      await tester.tap(find.text(l10n.promoCodeRetry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.promoCodeLoadFailed), findsNothing);
      expect(find.text(_fixedCode.code), findsOneWidget);
    });

    testWidgets('server failure reason stays primary; localized copy is fallback',
        (tester) async {
      // Real reason from the server → shown verbatim, fallback NOT shown.
      repo.nextRedeem = const PromoRedeemResult.failure(
          message: 'Code expired on 2026-01-01', code: 'EXPIRED');
      final l10n = await AppLocalizations.delegate.load(en);
      await pumpSheet(tester, en);
      await tester.tap(find.text(l10n.promoCodeValidateApply));
      await tester.pumpAndSettle();
      expect(find.textContaining('Code expired on 2026-01-01'), findsOneWidget);
      expect(find.text(l10n.promoCodeInvalid), findsNothing);

      // Empty-message failure → treated like "no message", localized fallback.
      await pumpSheet(tester, en);
      await tester.tap(find.text(l10n.promoCodeValidateApply));
      await tester.pumpAndSettle();
      expect(find.text(l10n.promoCodeInvalid), findsOneWidget);
    });

    testWidgets('client-side validators fire before any network call',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      // Empty field.
      await pumpSheet(tester, en);
      await tester.tap(find.text(l10n.promoCodeValidateApply));
      await tester.pumpAndSettle();
      expect(find.text(l10n.promoCodeEnterFirst), findsOneWidget);
      expect(repo.redeemCalls, 0);

      // No fare: validation happens client-side, never a blind redeem.
      await pumpSheet(tester, en, estimatedFare: null);
      await tester.enterText(find.byType(TextField), 'NIDUS20');
      await tester.tap(find.text(l10n.promoCodeValidateApply));
      await tester.pumpAndSettle();
      expect(find.text(l10n.promoCodeNeedRoute), findsOneWidget);
      expect(repo.redeemCalls, 0);
    });

    testWidgets('success applies server projection and pops the sheet',
        (tester) async {
      String? appliedCode;
      double? appliedDiscount;
      repo.nextRedeem = const PromoRedeemResult.success(PromoProjection(
        code: 'NIDUS20',
        type: 'percent',
        value: 20,
        projectedDiscount: 30.0,
        currency: 'ETB',
      ));
      final l10n = await AppLocalizations.delegate.load(en);
      await tester.pumpWidget(_host(
        en,
        PromoCodeSheet(
          estimatedFare: 150,
          currency: 'ETB',
          rideType: 'standard',
          onApplied: (code, discount) {
            appliedCode = code;
            appliedDiscount = discount;
          },
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'nidus20');
      await tester.tap(find.text(l10n.promoCodeValidateApply));
      await tester.pumpAndSettle();
      expect(appliedCode, 'NIDUS20');
      expect(appliedDiscount, 30.0); // server number, untouched by the client
      expect(find.byType(PromoCodeSheet), findsNothing);
    });

    testWidgets('attached code shows Remove and clears via onApplied(null)',
        (tester) async {
      String? appliedCode = 'preset';
      repo.nextRedeem = const PromoRedeemResult.success(PromoProjection(
        code: 'NIDUS20',
        type: 'percent',
        value: 20,
        projectedDiscount: 30.0,
        currency: 'ETB',
      ));
      final l10n = await AppLocalizations.delegate.load(en);
      await tester.pumpWidget(_host(
        en,
        PromoCodeSheet(
          estimatedFare: 150,
          currency: 'ETB',
          rideType: 'standard',
          currentCode: 'NIDUS20',
          onApplied: (code, _) => appliedCode = code,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(l10n.promoCodeRemove), findsOneWidget);
      await tester.tap(find.text(l10n.promoCodeRemove));
      await tester.pumpAndSettle();
      expect(appliedCode, isNull);
      expect(find.byType(PromoCodeSheet), findsNothing);
    });
  });

  group('Oromo catalog sanity (pure)', () {
    test('om promo entries are Afaan Oromoo, not duplicated Amharic',
        async () {
      final l10n = await AppLocalizations.delegate.load(om);
      expect(l10n.promoCodeTitle, contains('Koodhaa'));
      expect(l10n.promoCodeRetry, contains('deebi'));
      expect(l10n.promoUntil('2026-12-31'), contains('hanga'));
      expect(l10n.promoOffPercent('20'), contains('hir'));
    });
  });
}
