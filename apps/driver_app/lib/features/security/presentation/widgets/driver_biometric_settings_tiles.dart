import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/services/driver_biometric_security_service.dart';

/// Biometric-protection toggle rows used by the Driver App settings screen.
///
/// Purely local behaviour: enabling runs a native fingerprint/face check
/// first and only persists the preference after the platform confirms it.
/// Disabling requires no prompt (the driver is already inside the app).
/// Server sessions are untouched in both directions — these gates never
/// replace OTP login, token validation, or professional approval.
class DriverBiometricSettingsTiles extends StatefulWidget {
  const DriverBiometricSettingsTiles({
    super.key,
    required this.service,
    required this.accountId,
  });

  final DriverBiometricSecurityService service;

  /// Currently signed-in driver account id, used for the device-local owner
  /// marker. Substitutes pass their OWN id — they never inherit the primary
  /// driver's local protection state or biometrics.
  final String accountId;

  @override
  State<DriverBiometricSettingsTiles> createState() =>
      _DriverBiometricSettingsTilesState();
}

class _DriverBiometricSettingsTilesState
    extends State<DriverBiometricSettingsTiles> {
  bool _busy = false;

  bool get _appGateEnabled => widget.service.isAppGateEnabled();

  bool get _goOnlineGateEnabled => widget.service.isGoOnlineGateEnabled();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.fingerprint, color: AppColors.primary),
            ),
            title: const Text(
              'Biometric Unlock',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _appGateEnabled
                  ? 'Fingerprint or face unlock required to open the app on '
                      'this device'
                  : 'Use fingerprint or face unlock instead of logging in '
                      'again on this device',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            value: _appGateEnabled,
            activeColor: AppColors.primary,
            onChanged: _busy
                ? null
                : (v) => _handle(
                    requestEnabled: v,
                    persist: (enabled) => widget.service.setEnabled(
                        key: DriverBiometricSecurityService.appGateKey,
                        enabled: enabled,
                        accountId: widget.accountId),
                    onLabel: 'Confirm it’s you to enable biometric unlock',
                    successMessage:
                        'Biometric unlock turned on for this device.',
                  ),
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: SwitchListTile(
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.wifi_tethering,
                  color: AppColors.success),
            ),
            title: const Text(
              'Require Biometric Before Going Online',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _goOnlineGateEnabled
                  ? 'A fingerprint or face check runs every time before you '
                      'go online. Going offline never prompts.'
                  : 'Optional extra check before your availability switch '
                      'turns you online',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            value: _goOnlineGateEnabled,
            activeColor: AppColors.success,
            onChanged: _busy
                ? null
                : (v) => _handle(
                    requestEnabled: v,
                    persist: (enabled) =>
                        widget.service.setGoOnlineGateEnabled(
                            enabled: enabled, accountId: widget.accountId),
                    onLabel:
                        'Confirm it’s you to require biometric before going online',
                    successMessage:
                        'Biometric check will now run before you go online.',
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _handle({
    required bool requestEnabled,
    required Future<void> Function(bool enabled) persist,
    required String onLabel,
    required String successMessage,
  }) async {
    setState(() => _busy = true);
    try {
      if (requestEnabled) {
        await _enable(persist: persist, onLabel: onLabel,
            successMessage: successMessage);
      } else {
        await persist(false);
        if (mounted) setState(() {});
      }
    } on BiometricSettingPersistenceException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable({
    required Future<void> Function(bool enabled) persist,
    required String onLabel,
    required String successMessage,
  }) async {
    final capability = await widget.service.detectCapability();
    if (!capability.hasAnyBiometric) {
      _showSnack(capability.canAuthenticate
          ? 'No fingerprint or face data is enrolled on this device yet. Add '
              'one in system settings first.'
          : 'This device does not support biometric authentication.');
      return;
    }
    final result = await widget.service.authenticate(
      reason: onLabel,
      forSetup: true,
    );
    if (!result.isSuccess) {
      _showSnack(result.message ??
          'Biometric verification was not completed, so the setting was not '
              'changed.');
      return;
    }
    await persist(true);
    if (mounted) setState(() {});
    _showSnack(successMessage);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
