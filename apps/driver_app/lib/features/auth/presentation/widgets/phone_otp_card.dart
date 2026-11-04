import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart' show getIt;
import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/auth_repository.dart';
import '../bloc/auth_bloc.dart';
import 'otp_controller.dart';

/// Phone-number + OTP sign-in / sign-up card shared by the driver login and
/// registration screens. It is the primary driver entry path: email/password
/// remains available for legacy accounts, but a phone number is mandatory
/// and every new account proves phone possession with an OTP before any
/// session or registration ticket is issued. OTP never grants professional
/// approval - new drivers continue into the onboarding flow afterwards.
class PhoneOtpCard extends StatefulWidget {
  const PhoneOtpCard({super.key, this.initialMode = 'login'});

  /// 'login' offers sign-in for existing drivers (an unregistered verified
  /// number automatically continues into account creation). 'register'
  /// starts in the create-account mode directly.
  final String initialMode;

  @override
  State<PhoneOtpCard> createState() => _PhoneOtpCardState();
}

class _PhoneOtpCardState extends State<PhoneOtpCard> {
  late final DriverOtpController _otp;
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  bool _signupMode = false;
  String? _pendingTicket;
  String? _inlineError;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _otp = DriverOtpController(getIt<AuthRepository>());
    _signupMode = widget.initialMode == 'register';
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _otp.resendCountdownSeconds > 0) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _otp.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _otp,
      builder: (context, _) {
        return Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                _signupMode ? 'Create with your phone' : 'Continue with phone',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _signupMode
                    ? 'Your phone number is required. Name, email, and '
                        'password are optional.'
                    : 'We text you a 6-digit code - no password needed.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),

              // Optional name on the signup path only.
              if (_signupMode && _pendingTicket != null) ...[
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Your name (optional)',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Step 1: phone.
              if (!_otp.codeSent)
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  enabled: !_otp.busy,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '+251 9XX XXX XXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: _validatePhone,
                ),

              // Step 2: code entry with resend countdown.
              if (_otp.codeSent) ...[
                Row(
                  children: [
                    const Icon(Icons.mark_email_read_outlined,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Code sent to ${_phoneController.text.trim()}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    counterText: '',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().length < 4)
                      ? 'Enter the 6-digit code'
                      : null,
                ),
                TextButton.icon(
                  onPressed: _otp.resendCountdownSeconds > 0 || _otp.busy
                      ? null
                      : _sendCode,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(_otp.resendCountdownSeconds > 0
                      ? 'Resend code in ${_otp.resendCountdownSeconds}s'
                      : 'Resend code'),
                ),
              ],

              if (_inlineError != null || _otp.error != null) ...[
                const SizedBox(height: 4),
                _buildInlineError(_inlineError ?? _otp.error!),
              ],

              const SizedBox(height: 12),

              // Action button per step.
              if (!_otp.codeSent)
                OutlinedButton.icon(
                  onPressed: _otp.busy ? null : _sendCode,
                  icon: _otp.busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: Text(_signupMode
                      ? 'Send verification code'
                      : 'Send code to my phone'),
                )
              else if (_pendingTicket == null)
                ElevatedButton(
                  onPressed: _otp.busy ? null : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _otp.busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Verify & continue'),
                )
              else
                ElevatedButton(
                  onPressed: _otp.busy ? null : _finishSignup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _otp.busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Create my NIDAW driver account'),
                ),

              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _otp.busy ? null : _toggleMode,
                  child: Text(_signupMode
                      ? 'I already have an account'
                      : 'New to NIDAW? Become a driver'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String? _validatePhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Phone number is required';
    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9 || digits.length > 15) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  void _toggleMode() {
    setState(() {
      _signupMode = !_signupMode;
      _inlineError = null;
      _pendingTicket = null;
    });
    _otp.reset();
  }

  Future<void> _sendCode() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    _inlineError = null;
    await _otp.sendCode(
      phone: _phoneController.text.trim(),
      operation: _signupMode ? 'register' : 'login',
    );
  }

  Future<void> _verifyCode() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    _inlineError = null;
    final result = await _otp.signInWithCode(
      phone: _phoneController.text.trim(),
      code: _codeController.text.trim(),
    );
    if (!mounted) return;

    if (result.signedIn) {
      // The session is open and tokens persisted; mirror it into the
      // global AuthBloc so the router gate reacts immediately without a
      // second (single-use-rejected) verify round-trip.
      context.read<AuthBloc>().add(OtpLoginCompleted(result.driver!));
      return;
    }
    if (result.phoneUnregistered) {
      setState(() {
        _signupMode = true;
        _pendingTicket = result.verificationTicket;
        _codeController.clear();
      });
      return;
    }
    setState(
        () => _inlineError = _guidanceFor(result.errorCode, result.error!));
  }

  Future<void> _finishSignup() async {
    final ticket = _pendingTicket;
    if (ticket == null) return;
    _inlineError = null;
    // The AuthBloc owns the register-phone call and emits
    // AuthAuthenticated(onboardingComplete: false); its listeners navigate
    // to /onboarding where document upload and professional approval happen.
    context.read<AuthBloc>().add(PhoneRegistrationRequested(
          verificationTicket: ticket,
          fullName: _nameController.text.trim(),
        ));
  }

  static String _guidanceFor(String? code, String fallback) {
    final guidance = <String, String>{
      'OTP_INVALID': 'That code is not correct. Check the SMS and try again.',
      'OTP_EXPIRED': 'The code expired. Request a new one and try again.',
      'OTP_LOCKED':
          'Too many attempts. Wait a few minutes, then request a new code.',
      'OTP_COOLDOWN': fallback,
      'SMS_DELIVERY_FAILED':
          'We could not send the code. Please check the number and retry.',
      'IDENTITY_CONFLICT':
          'This phone or email belongs to another account. Try signing in.',
    };
    return guidance[code] ?? fallback;
  }

  Widget _buildInlineError(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
