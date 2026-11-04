import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';

/// Outcome of a device-native biometric prompt (fingerprint / face unlock).
enum BiometricOutcome {
  success,

  /// The user dismissed the sheet without authenticating.
  userCancelled,

  /// No usable biometric is enrolled on this device.
  notEnrolled,

  /// The device cannot perform biometric authentication at all.
  unavailable,

  /// Too many failed attempts — the platform locked biometrics temporarily.
  lockedOut,

  /// Any other platform/permission failure. Surfaced honestly; never treated
  /// as success.
  failure,
}

/// Result of [DriverBiometricSecurityService.authenticate].
class BiometricAuthResult {
  final BiometricOutcome outcome;
  final String? message;

  const BiometricAuthResult(this.outcome, {this.message});

  bool get isSuccess => outcome == BiometricOutcome.success;
}

/// A locally detected biometric capability (device truth, not user intent).
class BiometricCapability {
  final bool canAuthenticate;
  final List<String> availableKinds;

  const BiometricCapability({
    required this.canAuthenticate,
    required this.availableKinds,
  });

  bool get hasAnyBiometric => canAuthenticate && availableKinds.isNotEmpty;
}

/// Failure thrown when a driver tries to CHANGE a biometric preference while
/// the local preference store is unusable. Callers must surface this instead
/// of silently pretending the setting was saved.
class BiometricSettingPersistenceException implements Exception {
  final String message;

  const BiometricSettingPersistenceException([
    this.message =
        'Could not save the biometric setting on this device. Try again.',
  ]);

  @override
  String toString() => message;
}

/// Device-native biometric security gate for the NIDAW Driver App.
///
/// This is a LOCAL application-security layer only:
///  - It wraps `local_auth`, which talks to the platform Keystore (Android)
///    / Secure Enclave (iOS). Biometric templates are NEVER read, exported,
///    uploaded, or stored by NIDAW — the platform does not expose them, and
///    this service never asks for them.
///  - Passing this gate authorizes NOTHING remotely. Going online still
///    requires a valid session token AND server-side professional approval;
///    the backend remains the sole authority over eligibility (Phase 8).
///    Local biometric success is never a substitute for server-side
///    authentication, authorization, or document verification.
///
/// Two independent preferences are managed here:
///  - App-open gate (`biometric_gate`): cold-start unlock, same semantics as
///    the Consumer App's rider gate.
///  - Go-Online gate (`biometric_go_online`): configurable requirement to
///    re-verify with a native fingerprint/face prompt immediately before the
///    availability switch turns the driver online. Turning OFFLINE never
///    prompts — de-escalation must always be frictionless.
///
/// Storage follows the existing Driver App conventions: preference flags live
/// in the Hive `'driver_settings'` box (opened by the startup coordinator's
/// deferred stage; reads fail closed to "off" if it is somehow unavailable).
/// A single marker in platform secure storage records WHICH driver account
/// last enabled the app-open gate, so a different driver signing in on a
/// shared device faces an honest re-enrollment prompt instead of inheriting
/// someone else's local protection state. Substitutes therefore always pass
/// the gate against their OWN identity — the gate never borrows or mirrors
/// the primary driver's credentials or biometrics.
class DriverBiometricSecurityService {
  static const String settingsBoxName = 'driver_settings';
  static const String appGateKey = 'biometric_gate';
  static const String goOnlineGateKey = 'biometric_go_online';
  static const String _ownerMarkerKey = 'nidaw_driver_biometric_owner_v1';

  const DriverBiometricSecurityService({
    LocalAuthentication? localAuthentication,
    FlutterSecureStorage? secureStorage,
    Box? settingsBox,
  })  : _auth = localAuthentication ?? LocalAuthentication(),
        _storage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        _settingsOverride = settingsBox;

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;
  final Box? _settingsOverride;

  // ------------------------------------------------------------------
  // Capability detection
  // ------------------------------------------------------------------

  /// Queries the platform for real biometric hardware/enrollment state.
  Future<BiometricCapability> detectCapability() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        return const BiometricCapability(
          canAuthenticate: false,
          availableKinds: [],
        );
      }
      final canAuthenticate = await _auth.canCheckBiometrics;
      final kinds = canAuthenticate
          ? (await _auth.getAvailableBiometrics())
              .map(_kindLabel)
              .toList(growable: false)
          : const <String>[];
      return BiometricCapability(
        canAuthenticate: supported,
        availableKinds: kinds,
      );
    } catch (e) {
      debugPrint('[biometric] capability detection failed: $e');
      return const BiometricCapability(
        canAuthenticate: false,
        availableKinds: [],
      );
    }
  }

  String _kindLabel(BiometricType type) {
    switch (type) {
      case BiometricType.fingerprint:
        return 'Fingerprint';
      case BiometricType.face:
        return 'Face unlock';
      case BiometricType.iris:
        return 'Iris scan';
      default:
        return 'Biometric';
    }
  }

  // ------------------------------------------------------------------
  // Prompt
  // ------------------------------------------------------------------

  /// Runs the native biometric prompt. Success means the platform accepted
  /// a locally enrolled fingerprint/face (or the system credential fallback);
  /// it authorizes NOTHING remotely.
  ///
  /// [forSetup] adds the explicit consent copy shown when the driver is
  /// enabling one of the gates. A cancelled prompt or abandoned fallback is
  /// reported honestly and never auto-approved.
  Future<BiometricAuthResult> authenticate({
    String reason = 'Confirm it’s you to open NIDAW Driver',
    bool forSetup = false,
  }) async {
    try {
      final granted = await _auth.authenticate(
        localizedReason: forSetup
            ? '$reason\n\nNIDAW stores no biometric data — this check happens '
                'entirely on your device.'
            : reason,
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Verify your identity',
            cancelButton: 'Cancel',
            biometricNotRecognized: 'Biometric not recognized. Try again.',
            goToSettingsButton: 'Settings',
            goToSettingsDescription:
                'Enroll a fingerprint or face unlock in system settings first.',
          ),
          IOSAuthMessages(
            cancelButton: 'Cancel',
            lockOutButton: 'Use Passcode',
          ),
        ],
        options: const AuthenticationOptions(
          biometricOnly: false,
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );
      if (granted) {
        return const BiometricAuthResult(BiometricOutcome.success);
      }
      return const BiometricAuthResult(
        BiometricOutcome.userCancelled,
        message: 'Biometric verification was cancelled.',
      );
    } catch (e) {
      final text = e.toString();
      if (text.contains('notEnrolled') ||
          text.contains('NotEnrolled') ||
          text.contains('PasswordAuthenticationNotEnabled')) {
        return const BiometricAuthResult(
          BiometricOutcome.notEnrolled,
          message: 'No fingerprint or face unlock is enrolled on this device.',
        );
      }
      if (text.contains('Locked') || text.contains('lockout')) {
        return const BiometricAuthResult(
          BiometricOutcome.lockedOut,
          message: 'Too many failed attempts. Use your device passcode or '
              'try again later.',
        );
      }
      if (text.contains('NotSupported') || text.contains('Supported')) {
        return const BiometricAuthResult(
          BiometricOutcome.unavailable,
          message: 'This device does not support biometric authentication.',
        );
      }
      debugPrint('[biometric] authenticate failed: $e');
      return BiometricAuthResult(
        BiometricOutcome.failure,
        message: 'Biometric verification failed: $e',
      );
    }
  }

  // ------------------------------------------------------------------
  // Preference persistence (device-local, non-sensitive)
  // ------------------------------------------------------------------

  Box get _box {
    final override = _settingsOverride;
    if (override != null) return override;
    return Hive.box(settingsBoxName);
  }

  bool _readFlag(String key) {
    try {
      return _box.get(key)?['enabled'] == true;
    } catch (_) {
      // Fail-closed reads: an unreadable preference means "gate off" — never
      // a forced lockout and never a fake "enabled" state.
      return false;
    }
  }

  /// Whether the app-open biometric gate is enabled on this device.
  bool isAppGateEnabled() => _readFlag(appGateKey);

  /// Whether a native biometric prompt is required before going online.
  /// Disabled by default; drivers enable it explicitly from Settings.
  bool isGoOnlineGateEnabled() => _readFlag(goOnlineGateKey);

  /// True when the app-open gate is enabled AND the device currently supports
  /// a biometric/pin verification path. The router uses this to decide
  /// whether to prompt; a device that lost its enrollment mid-life degrades
  /// to the normal session flow instead of bricking the app.
  Future<bool> isAppGateActive() async {
    if (!isAppGateEnabled()) return false;
    final capability = await detectCapability();
    return capability.canAuthenticate;
  }

  /// Resolves whether the Go-Online prompt should run right now.
  ///
  /// Honest degradation: if the driver enabled the requirement but the device
  /// currently cannot verify any biometric (lost enrollment, unsupported
  /// hardware), we do NOT silently skip the check and we do NOT brick the
  /// driver's livelihood either — the caller receives
  /// [GoOnlineGateDecision.shouldPrompt] together with the capability so it
  /// can show the real reason and let the driver fix Settings or continue
  /// through the normal (server-authorized) flow. When the gate is simply
  /// disabled, [GoOnlineGateDecision.required] is false and nothing prompts.
  Future<GoOnlineGateDecision> resolveGoOnlineGate() async {
    if (!isGoOnlineGateEnabled()) {
      return const GoOnlineGateDecision(required: false, shouldPrompt: false);
    }
    final capability = await detectCapability();
    return GoOnlineGateDecision(
      required: true,
      shouldPrompt: capability.canAuthenticate,
      capabilityUnavailable: !capability.canAuthenticate ||
          !capability.hasAnyBiometric,
    );
  }

  /// Persists one of the two preference flags together with a non-sensitive
  /// owner marker (SHA-256 digest of the driver account id, kept in platform
  /// secure storage) for the app-open gate. Throws
  /// [BiometricSettingPersistenceException] when the Hive write fails so
  /// callers can show a real error instead of desyncing UI from disk.
  Future<void> setEnabled({
    required String key,
    required bool enabled,
    required String accountId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'enabled': enabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _box.put(key, payload);
    } catch (e) {
      debugPrint('[biometric] settings write failed: $e');
      throw const BiometricSettingPersistenceException();
    }
    if (key != appGateKey) return;
    try {
      if (enabled) {
        await _storage.write(
          key: _ownerMarkerKey,
          value: base64Url.convert(utf8.encode(_marker(accountId))),
        );
      } else {
        await _storage.delete(key: _ownerMarkerKey);
      }
    } catch (e) {
      // The marker is defense-in-depth against shared-device confusion; the
      // authoritative gate flag already persisted. Not fatal.
      debugPrint('[biometric] owner marker update failed: $e');
    }
  }

  /// Convenience wrapper for the app-open gate flag.
  Future<void> setAppGateEnabled({
    required bool enabled,
    required String accountId,
  }) =>
      setEnabled(key: appGateKey, enabled: enabled, accountId: accountId);

  /// Convenience wrapper for the configurable Go-Online gate flag.
  Future<void> setGoOnlineGateEnabled({
    required bool enabled,
    required String accountId,
  }) =>
      setEnabled(
          key: goOnlineGateKey, enabled: enabled, accountId: accountId);

  /// Whether the app-open gate was enabled by [accountId] on this device.
  /// When the marker is absent (fresh install, cleared storage, or a pre-
  /// marker build) the answer is treated as "yes": the Hive flag itself
  /// remains the gate, and the next successful unlock rewrites the marker.
  Future<bool> ownedBy(String accountId) async {
    try {
      final raw = await _storage.read(key: _ownerMarkerKey);
      if (raw == null) return true;
      final decoded = utf8.decode(base64Url.decode(raw));
      return decoded == _marker(accountId);
    } catch (e) {
      debugPrint('[biometric] owner marker read failed: $e');
      return true;
    }
  }

  String _marker(String accountId) =>
      'nidaw-driver-biometric-owner:'
      '${sha256.convert(utf8.encode(accountId)).toString()}';
}

/// Outcome of [DriverBiometricSecurityService.resolveGoOnlineGate].
class GoOnlineGateDecision {
  /// The driver has enabled the Go-Online biometric requirement.
  final bool required;

  /// A native prompt can actually run on this device right now.
  final bool shouldPrompt;

  /// The requirement is active but the device currently cannot verify a
  /// biometric — callers must surface this honestly rather than pretending
  /// the check passed.
  final bool capabilityUnavailable;

  const GoOnlineGateDecision({
    required this.required,
    required this.shouldPrompt,
    this.capabilityUnavailable = false,
  });
}
