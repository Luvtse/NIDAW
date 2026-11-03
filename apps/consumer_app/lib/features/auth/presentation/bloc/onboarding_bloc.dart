import 'package:flutter/foundation.dart';

import '../../../../core/network/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/onboarding_status.dart';

/// Drives the rider activation screen: loads the server-authoritative
/// checklist from GET /api/v1/auth/onboarding-status, runs the OTP ->
/// consent-ticket -> complete chain, and exposes skip-and-complete-later.
class OnboardingBloc extends ChangeNotifier {
  OnboardingBloc({required AuthRepository authRepository})
      : _authRepository = authRepository;

  final AuthRepository _authRepository;

  OnboardingStatus? _status;
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _error;
  String? _errorCode;

  /// Set after otp/request(register) succeeds for this account's phone.
  bool _otpSent = false;
  int _resendAfterSeconds = 0;
  DateTime? _resendAvailableAt;

  OnboardingStatus? get status => _status;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  String? get errorCode => _errorCode;
  bool get otpSent => _otpSent;

  /// Seconds left before a resend is allowed (0 when available).
  int get resendCountdownSeconds {
    if (_resendAvailableAt == null) return 0;
    final remaining = _resendAvailableAt!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Agreement types that must be accepted to activate, taken from the
  /// server's required set — never hardcoded in the client.
  List<String> get requiredAgreementTypes =>
      _status?.agreements.map((a) => a.documentType).toList() ?? const [];

  Future<void> loadStatus() async {
    _setLoading(true);
    _error = null;
    try {
      _status = await _authRepository.fetchOnboardingStatus();
      _notify();
    } on ApiException catch (e) {
      _fail(e.message, e.errorCode);
    } catch (e) {
      _fail('Could not load your activation status', 'ONBOARDING_STATUS_FAILED');
    } finally {
      _setLoading(false);
    }
  }

  /// Step 1 of the consent chain: send an OTP bound to
  /// operation=register for the signed-in account's own phone.
  Future<bool> sendVerificationCode(String phone) async {
    _error = null;
    final result = await _authRepository.requestOtp(
      phone: phone,
      operation: 'register',
    );
    if (result.isFailure) {
      _fail(result.error!, result.errorCode);
      return false;
    }
    _otpSent = true;
    _resendAfterSeconds = result.resendAfterSeconds;
    _resendAvailableAt =
        DateTime.now().add(Duration(seconds: result.resendAfterSeconds));
    _notify();
    return true;
  }

  /// Steps 2+3: verify the code against the account's own phone (server
  /// reads the phone from the session row), obtain the single-use consent
  /// ticket, then submit the accepted agreement set for activation.
  /// Returns the resulting status; `complete == false` means the server is
  /// still waiting on agreements/phone verification (not a crash).
  Future<OnboardingStatus?> activate({
    required String code,
    required List<String> agreements,
  }) async {
    _isSubmitting = true;
    _error = null;
    _notify();
    try {
      final ticket =
          await _authRepository.requestConsentTicket(code: code);
      _status = await _authRepository.completeOnboarding(
        consentTicket: ticket.value,
        agreements: agreements,
      );
      _otpSent = false;
      _resendAvailableAt = null;
      return _status;
    } on ApiException catch (e) {
      // A spent/invalid ticket keeps the user on-screen with actionable
      // guidance rather than pretending success.
      _fail(e.message, e.errorCode);
      if (e.errorCode == 'OTP_EXPIRED' ||
          e.errorCode == 'OTP_INVALID' ||
          e.errorCode == 'CONSENT_VERIFICATION_REQUIRED') {
        _otpSent = false;
      }
      return _status;
    } catch (e) {
      _fail('Activation failed. Please try again.', 'ONBOARDING_FAILED');
      return _status;
    } finally {
      _isSubmitting = false;
      _notify();
    }
  }

  void clearError() {
    _error = null;
    _errorCode = null;
    _notify();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    _notify();
  }

  void _fail(String message, String? code) {
    _error = message;
    _errorCode = code;
  }

  void _notify() {
    try {
      notifyListeners();
    } catch (_) {
      // Listener detached during teardown; state remains readable.
    }
  }
}
