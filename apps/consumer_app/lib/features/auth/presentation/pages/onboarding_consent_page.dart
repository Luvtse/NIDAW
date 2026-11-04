import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/onboarding_status.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/onboarding_bloc.dart';

/// Rider activation screen (Phase 3).
///
/// The checklist is server-authoritative: agreements come from
/// GET /api/v1/auth/onboarding-status, never from a hardcoded list.
/// Activation requires a phone OTP bound to operation=register plus a
/// single-use consent ticket; optional profile fields never gate entry.
class OnboardingConsentPage extends StatefulWidget {
  const OnboardingConsentPage({super.key});

  @override
  State<OnboardingConsentPage> createState() => _OnboardingConsentPageState();
}

class _OnboardingConsentPageState extends State<OnboardingConsentPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  /// Local checkbox state keyed by document_type, seeded from the server
  /// checklist (pre-checked where accepted at the current version).
  final Map<String, bool> _selected = {};
  bool _seeded = false;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Load the activation checklist and prefill the account's phone when
    // one already exists on the session user.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bloc = context.read<OnboardingBloc>();
      final auth = context.read<AuthBloc>().state;
      if (auth is AuthAuthenticated && auth.user.phone.isNotEmpty) {
        _phoneController.text = auth.user.phone;
      }
      bloc.loadStatus().then((_) {
        if (mounted) _seedCheckboxes();
      });
      _ensureTicker();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // repaint the resend countdown
    });
  }

  void _seedCheckboxes() {
    if (_seeded) return;
    final status = context.read<OnboardingBloc>().status;
    if (status == null) return;
    _seeded = true;
    for (final agreement in status.agreements) {
      _selected[agreement.documentType] = agreement.acceptedAtCurrentVersion;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: context.watch<OnboardingBloc>(),
          builder: (context, _) {
            final bloc = context.read<OnboardingBloc>();
            _seedCheckboxes();
            if (bloc.isLoading && bloc.status == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (bloc.errorCode == 'ONBOARDING_STATUS_FAILED' &&
                bloc.status == null) {
              return _buildRetryBody(bloc);
            }
            return _buildBody(context, bloc);
          },
        ),
      ),
    );
  }

  Widget _buildRetryBody(OnboardingBloc bloc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              bloc.error ?? 'Could not load your activation status',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => bloc.loadStatus(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, OnboardingBloc bloc) {
    final status = bloc.status ?? OnboardingStatus.unknown();

    // Already activated server-side: go straight into the app.
    if (status.complete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AuthBloc>().add(const OnboardingActivated());
        context.go('/home');
      });
      return const Center(child: CircularProgressIndicator());
    }

    final agreements = status.agreements;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(status),
          const SizedBox(height: 24),

          // Server error banner (OTP_INVALID / OTP_COOLDOWN / OTP_LOCKED / ...)
          if (bloc.error != null) ...[
            _buildErrorMessage(bloc.error!, code: bloc.errorCode),
            const SizedBox(height: 16),
          ],

          // Step 1: verify this account's phone number with an OTP.
          if (!status.phoneVerified || !bloc.otpSent) _buildPhoneStep(bloc),

          // Step 2: enter the received code once it has been sent.
          if (bloc.otpSent) _buildCodeStep(bloc),

          const SizedBox(height: 24),

          // Dynamic required-agreement checklist from the server.
          ...agreements.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildAgreementTile(bloc, a),
              )),
          if (agreements.isEmpty && bloc.error == null)
            _buildInfoBanner(
              'No agreements are currently required. Verify your phone to '
              'activate your account.',
            ),

          const SizedBox(height: 12),
          Text(
            'Your name, email, photo, and password stay optional — you can '
            'complete them anytime from your profile.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),

          const SizedBox(height: 32),
          _buildActivateButton(context, bloc, agreements),

          const SizedBox(height: 8),
          _buildFinishLater(bloc),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHeader(OnboardingStatus status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.verified_user, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 24),
        const Text(
          'Activate your account',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          status.phoneVerified
              ? 'Almost there — review and accept the agreements below to '
                  'finish activation.'
              : 'Verify your phone number and accept the legal agreements to '
                  'start using NIDAW.',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
      ],
    );
  }

  // ==========================================================================
  // PHONE + OTP STEPS
  // ==========================================================================

  Widget _buildPhoneStep(OnboardingBloc bloc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          enabled: !bloc.isSubmitting,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '+251 9XX XXX XXX',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: bloc.isSubmitting ? null : () => _sendCode(bloc),
          icon: const Icon(Icons.send_outlined, size: 18),
          label: const Text('Send verification code'),
        ),
      ],
    );
  }

  Widget _buildCodeStep(OnboardingBloc bloc) {
    final countdown = bloc.resendCountdownSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.mark_email_read_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'We sent a 6-digit code to ${_phoneController.text.trim()}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: const InputDecoration(
            labelText: 'Verification code',
            counterText: '',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: countdown > 0 || bloc.isSubmitting
              ? null
              : () => _sendCode(bloc),
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(countdown > 0
              ? 'Resend code in ${countdown}s'
              : 'Resend code'),
        ),
      ],
    );
  }

  Future<void> _sendCode(OnboardingBloc bloc) async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your phone number first')),
      );
      return;
    }
    await bloc.sendVerificationCode(phone);
  }

  // ==========================================================================
  // AGREEMENT CHECKLIST
  // ==========================================================================

  Widget _buildAgreementTile(OnboardingBloc bloc, AgreementStatus a) {
    final checked = _selected[a.documentType] ?? false;
    final needsReaccept = a.accepted && a.outdated;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: checked ? AppColors.primary : AppColors.border,
          width: checked ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: checked,
            onChanged: bloc.isSubmitting
                ? null
                : (v) => setState(
                    () => _selected[a.documentType] = v ?? false),
            activeColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        a.title.isNotEmpty ? a.title : a.documentType,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '*',
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (a.acceptedAtCurrentVersion) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.check_circle,
                          size: 16, color: AppColors.success),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Version ${a.version}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (needsReaccept)
                  Text(
                    'You accepted an older version — please re-accept.',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                GestureDetector(
                  onTap: () => context.push('/legal/${a.documentType}'),
                  child: Text(
                    'Read document',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ACTIONS
  // ==========================================================================

  Widget _buildActivateButton(
    BuildContext context,
    OnboardingBloc bloc,
    List<AgreementStatus> agreements,
  ) {
    final allChecked = agreements.every(
        (a) => _selected[a.documentType] ?? a.acceptedAtCurrentVersion);
    final codeEntered = _codeController.text.trim().length >= 4;
    final canActivate = allChecked && codeEntered && !bloc.isSubmitting;

    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: canActivate ? () => _activate(context, bloc) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: bloc.isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Accept & Activate',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Future<void> _activate(BuildContext context, OnboardingBloc bloc) async {
    final agreements = bloc.status?.agreements ?? const <AgreementStatus>[];
    final accepted = agreements
        .where((a) => _selected[a.documentType] ?? a.acceptedAtCurrentVersion)
        .map((a) => a.documentType)
        .toList();
    if (accepted.length != agreements.length) {
      // Defensive: only send the full required set; the button gates this.
      accepted.addAll(agreements
          .map((a) => a.documentType)
          .where((t) => !accepted.contains(t)));
    }

    final result = await bloc.activateAndSync(
      authBloc: context.read<AuthBloc>(),
      code: _codeController.text.trim(),
      agreements: accepted,
    );
    if (!mounted) return;

    if (result != null && result.complete) {
      context.go('/home');
      return;
    }
    // Incomplete or failed: show honest guidance per error code.
    final code = bloc.errorCode;
    final guidance = <String, String>{
      'OTP_INVALID':
          'That code is not correct. Check the SMS and try again.',
      'OTP_EXPIRED':
          'The code expired. Request a new one and try again.',
      'OTP_COOLDOWN':
          bloc.error ?? 'Please wait before requesting another code.',
      'OTP_LOCKED':
          'Too many attempts. Wait a few minutes, then request a new code.',
      'CONSENT_VERIFICATION_REQUIRED':
          'Phone verification is required before accepting the agreements.',
    };
    final message = guidance[code] ??
        bloc.error ??
        'Activation is not complete yet. Please try again.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            code == null ? AppColors.error : AppColors.warning,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _buildFinishLater(OnboardingBloc bloc) {
    return Column(
      children: [
        Text(
          'You cannot use rides, food ordering, or other services until '
          'your phone is verified and the required agreements are '
          'accepted. You can finish now or sign out and come back later.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: bloc.isSubmitting
                ? null
                : () => context.read<AuthBloc>().add(const LogoutRequested()),
            child: const Text('Sign out and finish later'),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage(String message, {String? code}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 14)),
                if (code != null)
                  Text(
                    code,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => context.read<OnboardingBloc>().clearError(),
          ),
        ],
      ),
    );
  }
}
