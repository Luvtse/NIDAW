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

/// Result of [BiometricSecurityService.authenticate].
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

/// Failure thrown when the user tries to ENABLE biometric protection while
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

/// Device-native biometric security gate for the NIDAW Consumer App.
///
/// This is a LOCAL application-security layer only:
///  - It wraps `local_auth`, which talks to the platform Keystore
///    (Android) / Secure Enclave (iOS). Biometric templates are NEVER read,
///    exported, uploaded, or stored by NIDAW — the platform does not expose
///    them, and this service never asks for them.
///  - The persisted enable/disable preference contains only booleans and
///    non-sensitive metadata. Nothing here grants server-side access: every
///    protected backend operation still requires a valid session token, and
///    passing this gate is never a substitute for server authentication,
///    authorization, or professional verification.
///
/// Storage split follows the existing app conventions:
///  - The *gate requirement* flag lives in the Hive `'settings'` box (same
///    place as other device preferences such as the saved locale).
///  - A single marker in platform secure storage records WHICH account last
///    enabled the gate, so a different user signing in on a shared device
///    faces an honest re-enrollment prompt instead of inheriting someone
///    else's local protection state.
class BiometricSecurityService {
  static const String settingsBoxKey = 'biometric_gate';
  static const String _ownerMarkerKey = 'biometric_owner_v1';

  const BiometricSecurityService({
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
  /// [forSetup] adds the explicit consent copy shown when the user is
  /// enabling the feature. A cancelled prompt or abandoned fallback is
  /// reported honestly and never auto-approved.
  Future<BiometricAuthResult> authenticate({
    String reason = 'Confirm it’s you to open NIDAW',
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
    return Hive.box('settings');
  }

  /// Whether the LOCAL gate is enabled on this device. Fail-closed reads:
  /// any error means "off" — never a forced lockout and never a fake
  /// "enabled" state.
  bool isEnabled() {
    try {
      return _box.get(settingsBoxKey)?['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// True when the gate is enabled AND the device currently supports a
  /// biometric/pin verification path. Consumers use this to decide whether
  /// to prompt; a device that lost its enrollment mid-life degrades to the
  /// normal session flow instead of bricking the app.
  Future<bool> isGateActive() async {
    if (!isEnabled()) return false;
    final capability = await detectCapability();
    return capability.canAuthenticate;
  }

  /// Persists the user's enable/disable choice together with a non-sensitive
  /// owner marker (SHA-256 digest of the account id, kept in platform secure
  /// storage). Throws [BiometricSettingPersistenceException] when the Hive
  /// write fails so callers can show a real error instead of desyncing UI
  /// from disk.
  Future<void> setEnabled({
    required bool enabled,
    required String accountId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'enabled': enabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await _box.put(settingsBoxKey, payload);
    } catch (e) {
      debugPrint('[biometric] settings write failed: $e');
      throw const BiometricSettingPersistenceException();
    }
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

  /// Whether the gate was enabled by [accountId] on this device. When the
  /// marker is absent (fresh install, cleared storage, or a pre-marker build)
  /// the answer is treated as "yes": the Hive flag itself remains the gate,
  /// and the next successful unlock rewrites the marker.
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
      'nidaw-biometric-owner:${sha256.convert(utf8.encode(accountId)).toString()}';
}
