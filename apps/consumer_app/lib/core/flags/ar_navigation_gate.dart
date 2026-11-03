// Phase 6 (navigation & error-surface consistency): single source of truth
// for the AR-navigation runtime gate.
//
// Before this file existed, the `ar_navigation` gate was resolved twice with
// two hand-copied implementations:
//   * app_router.dart's GoRoute redirect (compile switch + install-bucketed
//     runtime flag) — the authoritative fallback;
//   * ride_tracking_page.dart's _ArNavigationButton, which re-read the Hive
//     'settings' box inline and skipped the compile switch entirely.
// Both comments promised "the same bucket" but nothing enforced it; a change
// to one side could silently desynchronize entry-button visibility from the
// router redirect.
//
// Now both call sites go through ArNavigationGate.resolve(). The opaque
// per-install id (feature-flag rollout bucketing — see FeatureFlagService
// .isEnabled) lives here too, so the storage key is named in exactly one
// place.
import 'dart:convert';
import 'dart:math' as math;

import 'package:hive/hive.dart';

import '../config/feature_flag_service.dart';
import '../constants/app_constants.dart';
import '../di/injection.dart';

/// Runtime + compile-time gate for the §4.1 AR walk-to-pickup surface.
class ArNavigationGate {
  const ArNavigationGate._();

  /// Feature-flag key shared by the router redirect and the tracking-page
  /// entry button.
  static const String flagKey = 'ar_navigation';

  /// Hive box/key holding the stable per-install rollout id. Never a real
  /// device fingerprint — a random opaque id, so it carries no PII; a
  /// reinstall re-rolls the bucket, which is acceptable for rollout gates.
  static const String settingsBoxName = 'settings';
  static const String installIdKey = 'install_id';

  static String? _cachedInstallId;

  /// Compile-time kill switch (--dart-define=FEATURE_AR_NAVIGATION). Checked
  /// first everywhere: when off, nothing else is evaluated at all.
  static bool get compileEnabled => AppConstants.enableARNavigation;

  /// Resolves the full double gate: compile switch AND the runtime
  /// `ar_navigation` flag evaluated against this install's rollout bucket.
  ///
  /// Fail-closed on every unavailable dependency (GetIt not ready, flag
  /// service missing, Hive unopenable): no button, no dead end. When Hive is
  /// unavailable we fall back to an in-memory id so partial rollouts still
  /// bucket deterministically for this session instead of resolving blindly
  /// without a deviceId.
  static Future<bool> resolve() async {
    if (!compileEnabled) return false;
    try {
      final flags = getIt<FeatureFlagService>();
      final deviceId = await resolveInstallId();
      return flags.isEnabled(flagKey, deviceId: deviceId);
    } catch (_) {
      // Flag service unavailable → conservative false (kill-switch
      // semantics).
      return false;
    }
  }

  /// Stable per-install identifier used for deterministic feature-flag
  /// rollout bucketing. Generated once on first access and persisted in the
  /// already-open 'settings' Hive box.
  static Future<String?> resolveInstallId() async {
    if (_cachedInstallId != null) return _cachedInstallId;
    try {
      final box = Hive.box(settingsBoxName);
      var id = box.get(installIdKey) as String?;
      if (id == null || id.isEmpty) {
        id = _generateOpaqueId();
        await box.put(installIdKey, id);
      }
      _cachedInstallId = id;
      return id;
    } catch (_) {
      // Hive unavailable (tests, corrupted store): fall back to an
      // in-memory id so flag evaluation stays stable for this session.
      final id = _generateOpaqueId();
      _cachedInstallId = id;
      return id;
    }
  }

  /// Test seam: drops the memoized id so each test starts from a clean
  /// slate (mirrors what a fresh install would do).
  static void clearCachedInstallIdForTest() => _cachedInstallId = null;

  /// Byte-identical to the id generator that previously lived in
  /// app_router.dart — installs bucketed before Phase 6 stay in the same
  /// rollout bucket after it (the persisted value is what feeds isEnabled).
  static String _generateOpaqueId() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
