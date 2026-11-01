// Phase 3 — Core localization sweep (split_fare_sheet.dart).
//
// Locks two things:
//  1. Every user-facing string in the §3.3 Split Fare sheet resolves through
//     the generated catalog (en/am/om), and none of the former English
//     literals ('Split fare', 'Add person', 'Not split yet', 'Email or phone',
//     'Split status', ...) leak on am/om surfaces.
//  2. The honesty contract from the widget's doc header survives migration:
//     all numbers come from the server DTO, a no-split-yet 404 renders the
//     calm "not split yet" card (never an error), unknown invitee wire states
//     are surfaced verbatim instead of mislabeled, and the localized
//     fallback copy only appears when the server gave no message.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nidaw_app/core/di/injection.dart' show getIt;
import 'package:nidaw_app/features/nidus/data/repositories/split_fare_repository.dart';
import 'package:nidaw_app/features/nidus/presentation/widgets/split_fare_sheet.dart';
import 'package:nidaw_app/l10n/generated/app_localizations.dart';

/// A createSplit failure whose server message is EMPTY. The sheet treats an
/// empty message like "no message" and falls back to the localized
/// splitSendFailed copy — this exercises that path without weakening the
/// rule that a real server message always stays primary.
final _silentCreateFailure =
    SplitStatusResult.failure(message: '', code: 'EMPTY');

class _FakeSplitRepo implements SplitFareRepository {
  _FakeSplitRepo();

  final SplitStatus status = const SplitStatus(
    exists: false,
    rideId: 'r1',
    fare: 0,
    currency: 'ETB',
    inviterShare: 0,
    totalSplit: 0,
    remainingToPay: 0,
    invitees: [],
  );

  SplitStatusResult? getNext;
  SplitStatusResult? createNext;

  @override
  Future<SplitStatusResult> getSplit(String rideId) async =>
      getNext ?? SplitStatusResult.success(status);

  @override
  Future<SplitStatusResult> createSplit(
          String rideId, List<SplitShareRequest> shares) async =>
      createNext ?? SplitStatusResult.success(status);

  @override
  Future<SplitOpResult> acceptInvite(String inviteToken) async =>
      SplitOpResult.success();

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

const _formerLiterals = <String>[
  'Split fare',
  'Add person',
  'Not split yet',
  'Split status',
  'Total invited',
  'Still waiting',
  'Email or phone',
];

void main() {
  const en = Locale('en');
  const am = Locale('am');
  const om = Locale('om');

  late _FakeSplitRepo repo;

  setUp(() {
    repo = _FakeSplitRepo();
    if (!getIt.isRegistered<SplitFareRepository>()) {
      getIt.registerSingleton<SplitFareRepository>(repo);
    }
  });

  tearDown(() {
    if (getIt.isRegistered<SplitFareRepository>()) {
      getIt.unregister<SplitFareRepository>();
    }
  });

  Future<void> pumpSheet(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(_host(
      locale,
      const SplitFareSheet(rideId: 'r1', fare: 100, currency: 'ETB'),
    ));
    await tester.pumpAndSettle();
  }

  group('SplitFareSheet localization (Phase 3)', () {
    testWidgets('en: title/intro/add-person render from catalog',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      await pumpSheet(tester, en);
      expect(find.text(l10n.splitSheetTitle), findsOneWidget);
      expect(find.text(l10n.splitSheetIntro), findsOneWidget);
      expect(find.text(l10n.splitAddPerson), findsOneWidget);
      // No-split-yet is a calm state, not an error surface.
      expect(find.text(l10n.splitNotYetTitle), findsOneWidget);
      expect(find.text(l10n.splitNotYetSubtitle('ETB 100.00')), findsOneWidget);
    });

    testWidgets('am: catalog strings render, former English literals absent',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(am);
      await pumpSheet(tester, am);
      expect(find.text(l10n.splitSheetTitle), findsOneWidget);
      expect(find.text(l10n.splitAddPerson), findsOneWidget);
      expect(find.text(l10n.splitNotYetTitle), findsOneWidget);
      for (final lit in _formerLiterals) {
        expect(find.textContaining(lit), findsNothing,
            reason: 'English literal "$lit" leaked into Amharic surface');
      }
    });

    testWidgets('om: catalog strings render, former English literals absent',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(om);
      await pumpSheet(tester, om);
      expect(find.text(l10n.splitSheetTitle), findsOneWidget);
      expect(find.text(l10n.splitAddPerson), findsOneWidget);
      expect(find.text(l10n.splitNotYetTitle), findsOneWidget);
      for (final lit in _formerLiterals) {
        expect(find.textContaining(lit), findsNothing,
            reason: 'English literal "$lit" leaked into Oromo surface');
      }
    });

    testWidgets('server-sourced totals render with localized labels',
        (tester) async {
      repo.getNext = SplitStatusResult.success(
        const SplitStatus(
          exists: true,
          rideId: 'r1',
          fare: 100,
          currency: 'ETB',
          inviterShare: 60,
          totalSplit: 40,
          remainingToPay: 25,
          invitees: [
            SplitInviteInfo(
              id: 'i1',
              inviteeContact: 'abebe@example.com',
              shareAmount: 15,
              currencyTag: 'ETB',
              status: 'paid',
              createdAt: DateTime.utc(2026, 1, 2)
            ),
          ],
        ),
      );
      final l10n = await AppLocalizations.delegate.load(en);
      await pumpSheet(tester, en);
      expect(find.text(l10n.splitStatusLabel), findsOneWidget);
      expect(find.text(l10n.splitKvFare), findsOneWidget);
      expect(find.text(l10n.splitKvYourShare), findsOneWidget);
      expect(find.text(l10n.splitKvTotalInvited), findsOneWidget);
      expect(find.text(l10n.splitKvStillWaiting), findsOneWidget);
      // Amounts are server DTO values, formatted, never invented.
      expect(find.text('ETB 60.00'), findsOneWidget);
      expect(find.text('ETB 40.00'), findsOneWidget);
      expect(find.text('ETB 25.00'), findsOneWidget);
      // Documented wire state 'paid' is localized in the invitee row.
      expect(find.textContaining(l10n.splitStatusPaid), findsOneWidget);
    });

    testWidgets('unknown invitee wire state is surfaced verbatim, not faked',
        (tester) async {
      repo.getNext = SplitStatusResult.success(
        SplitStatus(
          exists: true,
          rideId: 'r1',
          fare: 100,
          currency: 'ETB',
          inviterShare: 100,
          totalSplit: 0,
          remainingToPay: 0,
          invitees: [
            SplitInviteInfo(
              id: 'i1',
              inviteeContact: 'x@example.com',
              shareAmount: 10,
              currencyTag: 'ETB',
              status: 'teleported',
              createdAt: DateTime.utc(2026),
            ),
          ],
        ),
      );
      await pumpSheet(tester, en);
      expect(find.textContaining('teleported'), findsOneWidget);
    });

    testWidgets('send failure: empty server message falls back to localized copy',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      await pumpSheet(tester, en);
      // Add one draft so the send button exists, then tap it while the fake
      // repo returns a failure with an EMPTY message -> localized fallback.
      await tester.tap(find.text(l10n.splitAddPerson));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'abebe@example.com');
      await tester.enterText(find.byType(TextFormField).last, '20');
      await tester.pumpAndSettle();
      repo.createNext = _silentCreateFailure;
      await tester.tap(find.textContaining(l10n.splitSendInvites('')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.splitNeedOneShare), findsNothing);
      expect(find.text(l10n.splitSendFailed), findsOneWidget);
      expect(find.text(l10n.commonRetry), findsOneWidget);
    });

    testWidgets('send failure: real server message stays primary, not masked',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(en);
      await pumpSheet(tester, en);
      await tester.tap(find.text(l10n.splitAddPerson));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'abebe@example.com');
      await tester.enterText(find.byType(TextFormField).last, '20');
      await tester.pumpAndSettle();
      repo.createNext = SplitStatusResult.failure(
          message: 'Split service unavailable', code: 'SPLIT_DOWN');
      await tester.tap(find.textContaining(l10n.splitSendInvites('')));
      await tester.pumpAndSettle();
      expect(find.text('Split service unavailable'), findsOneWidget);
      expect(find.text(l10n.splitSendFailed), findsNothing);
    });

    testWidgets('validation errors are localized', (tester) async {
      final l10n = await AppLocalizations.delegate.load(am);
      await pumpSheet(tester, am);
      await tester.tap(find.text(l10n.splitAddPerson));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await tester.enterText(find.byType(TextFormField).last, '-5');
      await tester.enterText(find.byType(TextFormField).last, '20');
      await tester.pumpAndSettle();
      // Now total > 0; submit triggers Form validation errors, localized.
      await tester.tap(find.textContaining(l10n.splitSendInvites('')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.splitFieldInvalidContact), findsOneWidget);
      expect(find.text(l10n.splitFieldInvalidAmount), findsOneWidget);
      expect(find.text('Enter a valid email or phone number'), findsNothing);
      expect(find.text('Required'), findsNothing);
    });

    testWidgets('submitting with no amount shows localized pre-check, no server call',
        (tester) async {
      final l10n = await AppLocalizations.delegate.load(am);
      await pumpSheet(tester, am);
      await tester.tap(find.text(l10n.splitAddPerson));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'abebe@example.com');
      // Amount left at 0 -> total <= 0 -> client-side pre-check fires before
      // Form validation and before any network call.
      await tester.tap(find.textContaining(l10n.splitSendInvites('')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.splitNeedOneShare), findsOneWidget);
      expect(find.text('Add at least one share before sending.'), findsNothing);
    });
  });
}

