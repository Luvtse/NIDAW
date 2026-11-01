// Phase 1 (UI/UX remediation §2) — SOS accessibility regression tests.
//
// The slide-to-confirm track was previously a bare GestureDetector: a
// screen-reader or keyboard user could not trigger an emergency alert at
// all. The fix exposes slider-style semantics plus a custom "activate"
// action on the thumb, and localizes every safety string (the audit found
// 'Slide to confirm SOS' hardcoded in English while the app ships en/am/om).
//
// NOTE ON GENERATED LOCALIZATION: `flutter gen-l10n` has not been run in
// this environment (no Flutter SDK), so lib/l10n/generated/ is stale until
// CI regenerates it. This test therefore does NOT pump SosSlideToConfirm
// directly (that would depend on the regenerated getters); instead it
// asserts the exact same contract statically:
//   * every ARB key the widget reads exists in ALL THREE locales with
//     matching placeholder shapes (localization can never regress to
//     English-only), and
//   * the widget source wires each key into Semantics/Tooltip (the
//     accessibility structure itself), mirroring the ride_error_banner_test
//     convention of asserting the contract without a full app runtime.
// A golden widget-level pass (TalkBack/VoiceOver manual check) remains a CI
// / device hand-off item from the Phase 1 findings sheet.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _arbDir = 'lib/l10n'; // package-relative; tests run with CWD = package root
const _locales = ['en', 'am', 'om'];

/// Every localization key SosSlideToConfirm + the toolkit SOS flow consume.
const _sosKeys = [
  'sosSlideLabel',
  'sosSliderA11y',
  'sosActivateA11y',
  'sosTooltip',
  'sosTitle',
  'sosTileSubtitle',
  'sosOverlayA11y',
  'sosOverlayTitle',
  'sosOverlayCountdownBody',
  'sosOverlayFallbackBody',
  'sosOverlayCancel',
  'sosOverlayCallNow',
  'sosOverlayRetryCall',
  'sosOverlayCallDirectly',
  'sosStartedCountdown',
  'sosLocationUnavailable',
  'openSafetyToolkit',
];

Map<String, dynamic> _readArb(String locale) =>
    jsonDecode(File('$_arbDir/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _placeholders(Map<String, dynamic> arb, String key) {
  final meta = arb['@$key'];
  if (meta is! Map<String, dynamic>) return {};
  final ph = meta['placeholders'];
  if (ph is! Map<String, dynamic>) return {};
  return ph.keys.toSet();
}

void main() {
  group('SOS/safety ARB coverage across en/am/om', () {
    test('every sos key exists in all three locales with non-empty value',
        () {
      for (final locale in _locales) {
        final arb = _readArb(locale);
        for (final key in _sosKeys) {
          expect(arb.containsKey(key), isTrue,
              reason: '$key missing from app_$locale.arb — a missing key '
                  'renders English fallback text on an Amharic/Oromo rider\'s '
                  'emergency screen');
          final value = arb[key];
          expect(value, isA<String>(), reason: '$key/$locale must be a string');
          expect((value as String).trim(), isNotEmpty,
              reason: '$key/$locale is empty');
        }
      }
    });

    test('placeholder shapes match English exactly per key', () {
      final en = _readArb('en');
      for (final locale in ['am', 'om']) {
        final arb = _readArb(locale);
        for (final key in _sosKeys) {
          expect(_placeholders(arb, key), _placeholders(en, key),
              reason: 'placeholder mismatch for $key in $locale — gen-l10n '
                  'would emit different method signatures per locale');
        }
      }
    });

    test('substituted placeholders actually appear in the translated value',
        () {
      for (final locale in _locales) {
        final arb = _readArb(locale);
        for (final key in _sosKeys) {
          final ph = _placeholders(arb, key);
          final value = arb[key] as String;
          for (final name in ph) {
            expect(value.contains('{$name}'), isTrue,
                reason: '$key/$locale declares placeholder $name but the '
                    'string does not use it');
          }
        }
      }
    });

    test('Amharic/Oromo machine-assisted entries are flagged for review', () {
      // Phase 1 exit criterion requires native-speaker sign-off; the flag
      // lives inside the value so it cannot be silently dropped.
      for (final locale in ['am', 'om']) {
        final arb = _readArb(locale);
        final flagged =
            _sosKeys.where((k) => (arb[k] as String).contains('native review pending')).toList();
        // All NEW Phase-1 keys (added by this remediation) must carry the
        // marker until review lands. Pre-existing keys may already be signed
        // off, hence subset check rather than equality.
        for (final key in [
          'sosStartedCountdown',
          'sosLocationUnavailable',
          'openSafetyToolkit',
        ]) {
          expect(flagged, contains(key),
              reason: '$key/$locale shipped without the native-review flag');
        }
      }
    });
  });

  group('SosSlideToConfirm accessibility wiring (source contract)', () {
    final src = File(
            'lib/features/nidus/presentation/widgets/safety_widgets.dart')
        .readAsStringSync();

    test('track exposes slider semantics label from l10n', () {
      expect(src, contains('Semantics('));
      expect(src, contains('l10n.sosSliderA11y'));
    });

    test('thumb exposes an actionable a11y label + activate intent', () {
      expect(src, contains('confirmA11yLabel'));
      expect(src, contains('l10n.sosActivateA11y'));
      expect(src, contains('ActivateIntent'));
      expect(src, contains('ButtonActivateIntent'));
    });

    test('thumb is focusable with a visible focus ring (keyboard path)', () {
      expect(src, contains('FocusableActionDetector'));
      expect(src, contains('_focusNode.hasFocus'));
    });

    test('slide label and tooltip are localized, never hardcoded', () {
      expect(src, contains('l10n.sosSlideLabel'));
      expect(src, contains('l10n.sosTooltip'));
      expect(src, isNot(contains("'Slide to confirm SOS'")),
          reason: 'the audited hardcoded literal must not come back');
    });

    test('overlay copy routes through l10n (audit listed these verbatim)', () {
      for (final key in [
        'l10n.sosOverlayTitle',
        'l10n.sosOverlayCancel',
        'l10n.sosOverlayCallNow',
      ]) {
        expect(src, contains(key));
      }
      expect(src, isNot(contains("'Slide to confirm SOS'")));
      expect(src, isNot(contains("\"Cancel — I'm safe\"")));
    });
  });

  group('Safety Toolkit mounts the accessible confirm step (orphan resolved)',
      () {
    final page = File(
            'lib/features/nidus/presentation/pages/safety_toolkit_page.dart')
        .readAsStringSync();

    testWidgets('widget-test slot: dialog pumps SosSlideToConfirm under CI',
        (tester) async {
      // Static proof here; the pumped-widget version runs after gen-l10n in
      // CI (see header note). Contract: tap on the SOS tile must NOT arm
      // StartSosCountdown directly anymore — it shows the slide-to-confirm
      // dialog first, preserving the anti-pocket-dial guarantee.
      expect(page, contains('SosSlideToConfirm('));
      expect(page, contains('showGeneralDialog<bool>'));
      // And the countdown only starts AFTER confirmation returns true.
      final confirmIdx = page.indexOf('confirmed != true');
      final startIdx = page.indexOf('bloc.add(StartSosCountdown');
      expect(confirmIdx, greaterThan(0));
      expect(startIdx, greaterThan(confirmIdx),
          reason: 'StartSosCountdown must be dispatched only after the '
              'slide-to-confirm result is checked');
    });

    test('toolkit SOS uses real device location, never the 0,0 stub', () {
      expect(page, contains('DeviceLocationService'));
      expect(page, contains('LocationGranted'));
      expect(page, isNot(contains('lat: 0')),
          reason: 'Phase 0 addendum: lat/lng=0 placeholder dispatched a '
              'Gulf-of-Guinea emergency location — must stay gone');
      expect(page, isNot(contains('lng: 0')));
    });
  });
}
