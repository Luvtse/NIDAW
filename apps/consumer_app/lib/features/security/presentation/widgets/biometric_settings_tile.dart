import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/services/biometric_security_service.dart';

/// Biometric-protection toggle row used by the Consumer App settings screen.
///
/// Purely local behaviour: enabling runs a native fingerprint/face check
/// first and only persists the preference after the platform confirms it.
/// Disabling requires no prompt (the user is already inside the app). Server
/// sessions are untouched in both directions — this gate never replaces OTP
/// login or token validation.
class BiometricSettingsTile extends StatefulWidget {
  const BiometricSettingsTile({
    super.key,
    required this.service,
    required this.accountId,
  });

  final BiometricSecurityService service;

  /// Currently signed-in account id, used for the device-local owner marker.
  final String accountId;

  @override
  State<BiometricSettingsTile> createState() => _BiometricSettingsTileState();
}

class _BiometricSettingsTileState extends State<BiometricSettingsTile> {
  bool _busy = false;
  String? _statusLine;

  bool get _enabled => widget.service.isEnabled();

  @override
  Widget build(BuildContext context) {
    return Card(
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
          _statusLine ??
              (_enabled
                  ? 'Fingerprint or face unlock required to open the app on '
                      'this device'
                  : 'Use fingerprint or face unlock instead of logging in '
                      'again on this device'),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        value: _enabled,
        activeColor: AppColors.primary,
        onChanged: _busy ? null : _onChanged,
      ),
    );
  }

  Future<void> _onChanged(bool requestEnabled) async {
    setState(() {
      _busy = true;
      _statusLine = null;
    });
    try {
      if (requestEnabled) {
        await _enable();
      } else {
        await widget.service.setEnabled(enabled: false, accountId: widget.accountId);
        if (mounted) setState(() {});
      }
    } on BiometricSettingPersistenceException catch (e) {
      _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    final capability = await widget.service.detectCapability();
    if (!capability.hasAnyBiometric) {
      _showSnack(capability.canAuthenticate
          ? 'No fingerprint or face data is enrolled on this device yet. Add '
              'one in system settings first.'
          : 'This device does not support biometric authentication.');
      return;
    }
    final result = await widget.service.authenticate(
      reason: 'Confirm it’s you to enable biometric unlock',
      forSetup: true,
    );
    if (!result.isSuccess) {
      _showSnack(result.message ??
          'Biometric verification was not completed, so the setting was not '
              'changed.');
      return;
    }
    await widget.service.setEnabled(enabled: true, accountId: widget.accountId);
    if (mounted) setState(() {});
    _showSnack('Biometric unlock turned on for this device.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
