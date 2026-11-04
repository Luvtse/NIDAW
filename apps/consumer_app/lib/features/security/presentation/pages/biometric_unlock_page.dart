import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart' show getIt;
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/services/biometric_security_service.dart';

/// Local biometric lock screen shown at cold start when the rider enabled
/// biometric unlock on this device and a persisted session exists.
///
/// This gate only controls ENTRY to the already-authenticated local session:
///  - No network call, no token exchange, no server trust is granted here.
///    The AuthBloc session (access + refresh tokens) remains the sole source
///    of authorization for every backend operation.
///  - Cancel/switch-user clears nothing server-side but leaves the app in the
///    signed-out UI flow; the session itself is untouched until it expires or
///    the user explicitly logs out from Settings.
class BiometricUnlockPage extends StatefulWidget {
  const BiometricUnlockPage({super.key});

  @override
  State<BiometricUnlockPage> createState() => _BiometricUnlockPageState();
}

class _BiometricUnlockPageState extends State<BiometricUnlockPage> {
  final _service = getIt<BiometricSecurityService>();
  bool _prompting = false;
  String? _message;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prompt());
  }

  Future<void> _prompt() async {
    if (_prompting) return;
    setState(() {
      _prompting = true;
      _message = null;
    });
    final result = await _service.authenticate();
    if (!mounted) return;
    setState(() => _prompting = false);
    if (result.isSuccess) {
      _continueToApp();
      return;
    }
    _attempts += 1;
    setState(() {
      _message = result.message ?? 'Biometric verification did not complete.';
    });
  }

  void _continueToApp() {
    if (!mounted) return;
    // Session hydration proceeds exactly as before Phase 6 — the router
    // redirect lands on /home once AuthBloc reports AuthAuthenticated.
    context.read<AuthBloc>().add(const CheckAuthStatus());
    context.go('/splash');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.fingerprint,
                  size: 96, color: AppColors.primary),
              const SizedBox(height: 24),
              const Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Use your fingerprint or face to unlock NIDAW on this '
                'device.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(
                  _message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 13),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _prompting ? null : _prompt,
                icon: _prompting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(_prompting
                    ? 'Waiting for biometric…'
                    : (_attempts == 0 ? 'Unlock' : 'Try again')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _prompting
                    ? null
                    : () {
                        // Honest escape hatch: drop to the normal auth flow.
                        // Tokens are NOT deleted — the session stays valid
                        // server-side and can be resumed later.
                        context.go('/login');
                      },
                child: const Text('Use phone number instead'),
              ),
              const SizedBox(height: 8),
              Text(
                'This check happens entirely on your device. NIDAW never '
                'sees or stores your biometric data.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
