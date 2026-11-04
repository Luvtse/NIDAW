import 'package:flutter/foundation.dart';

import '../../../../core/network/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/onboarding_status.dart';
import 'auth_bloc.dart';

/// Result of the phone+OTP sign-in path on the login screen.
class OtpSignInResult {
  final bool signedIn;
  final bool phoneUnregistered;
  final AuthResult? auth;
  final String? verificationTicket;
  final String? error;
  final String? errorCode;

  const OtpSignInResult._({
    this.signedIn = false,
    this.phoneUnregistered = false,
    this.auth,
    this.verificationTicket,
    this.error,
    this.errorCode,
  });

  const OtpSignInResult.success(AuthResult auth)
      : this._(signedIn: true, auth: auth);

  const OtpSignInResult.unregistered({required String verificationTicket})
      : this._(phoneUnregistered: true, verificationTicket: verificationTicket);

  const OtpSignInResult.failure({required String error, String? errorCode})
      : this._(error: error, errorCode: errorCode);
}

/// Shared driver for the phone + OTP screens (login sign-in and the rider
/// activation consent screen). The AuthBloc owns session transitions once a
/// code verifies; this class only runs the request/verify round-trips and
/// exposes resend cooldown state.
class PhoneOtpController extends ChangeNotifier {
  PhoneOtpController({required AuthRepository authRepository})
      : _authRepository = authRepository;

  final AuthRepository _authRepository;

  static final RegExp _secondsInMessage =
      RegExp(r'(\d+)\s*second', caseSensitive: false);

  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _errorCode;
  DateTime? _resendAvailableAt;

  bool get codeSent => _codeSent;
  bool get busy => _busy;
  String? get error => _error;
  String? get errorCode => _errorCode;

  int get resendCountdownSeconds {
    if (_resendAvailableAt == null) return 0;
    final remaining = _resendAvailableAt!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  void reset() {
    _codeSent = false;
    _busy = false;
    _error = null;
    _errorCode = null;
    _resendAvailableAt = null;
    notifyListeners();
  }

  /// Request a code for [phone] bound to [operation] (login|register|recovery).
  Future<bool> sendCode({
    required String phone,
    String operation = 'login',
    String accountType = 'rider',
  }) async {
    _busy = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    final result = await _authRepository.requestOtp(
      phone: phone,
      operation: operation,
      accountType: accountType,
    );
    _busy = false;
    if (result.isFailure) {
      _error = result.error;
      _errorCode = result.errorCode;
      // A cooldown rejection still means a code is in flight: start the
      // countdown from the wait the server advertised instead of letting
      // the user hammer the rate limit.
      if (result.errorCode == 'OTP_COOLDOWN') {
        final match = _secondsInMessage.firstMatch(result.error!);
        final seconds = int.tryParse(match?.group(1) ?? '') ?? 30;
        _resendAvailableAt = DateTime.now().add(Duration(seconds: seconds));
      }
      notifyListeners();
      return false;
    }
    _codeSent = true;
    _resendAvailableAt =
        DateTime.now().add(Duration(seconds: result.resendAfterSeconds));
    notifyListeners();
    return true;
  }

  /// Verify [code]. On success the AuthBloc event has already been dispatched
  /// (session or registration-ticket path), so callers just navigate via the
  /// bloc listener. Failures surface as [OtpSignInResult] for inline UI.
  Future<OtpSignInResult> signInWithCode({
    required String phone,
    required String code,
  }) async {
    _busy = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    try {
      final result = await _authRepository.verifyOtp(
        phone: phone,
        code: code,
        operation: 'login',
      );
      _busy = false;
      if (result.isFailure) {
        _error = result.error;
        _errorCode = result.errorCode;
        notifyListeners();
        return OtpSignInResult.failure(
          error: result.error!,
          errorCode: result.errorCode,
        );
      }
      if (result.auth != null) {
        // Session opened and tokens persisted by the repository; the login
        // screen dispatches OtpLoginCompleted to drive the AuthBloc state.
        _codeSent = false;
        notifyListeners();
        return OtpSignInResult.success(result.auth!);
      }
      // Register branch: the number has no account yet but the code was
      // valid — hand the ticket to the signup flow.
      _codeSent = false;
      notifyListeners();
      return OtpSignInResult.unregistered(
        verificationTicket: result.verificationTicket!,
      );
    } on ApiException catch (e) {
      _busy = false;
      _error = e.message;
      _errorCode = e.errorCode;
      notifyListeners();
      return OtpSignInResult.failure(error: e.message, errorCode: e.errorCode);
    } catch (e) {
      _busy = false;
      _error = 'Verification failed. Please try again.';
      _errorCode = 'UNKNOWN_ERROR';
      notifyListeners();
      return const OtpSignInResult.failure(
        error: 'Verification failed. Please try again.',
        errorCode: 'UNKNOWN_ERROR',
      );
    }
  }
}

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
  DateTime? _resendAvailableAt;

  OnboardingStatus? get status => _status;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  String? get errorCode => _errorCode;
  bool get otpSent => _otpSent;

  /// Seconds the server asked us to wait before a resend is allowed
  /// (0 when no request has been made yet).
  int get resendAfterSeconds {
    if (_resendAvailableAt == null) return 0;
    final remaining = _resendAvailableAt!.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

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

  static final RegExp _secondsInMessage =
      RegExp(r'(\d+)\s*second', caseSensitive: false);

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
      // A cooldown rejection still means a code is in flight: start the
      // resend countdown from the wait the server advertised so the user
      // learns when they can request again instead of hammering the limit.
      if (result.errorCode == 'OTP_COOLDOWN') {
        final match = _secondsInMessage.firstMatch(result.error!);
        final seconds = int.tryParse(match?.group(1) ?? '') ?? 30;

        _resendAvailableAt = DateTime.now().add(Duration(seconds: seconds));
        _notify();
      }
      return false;
    }
    _otpSent = true;

    _resendAvailableAt =
        DateTime.now().add(Duration(seconds: result.resendAfterSeconds));
    _notify();
    return true;
  }

  /// Convenience wrapper over [activate] that also syncs the global AuthBloc
  /// once the server reports the account activated. Returns the resulting
  /// status (`complete == true` only after server-side activation).
  Future<OnboardingStatus?> activateAndSync({
    required AuthBloc authBloc,
    required String code,
    required List<String> agreements,
  }) async {
    final result = await activate(code: code, agreements: agreements);
    if (result != null && result.complete) {
      authBloc.add(const OnboardingActivated());
    }
    return result;
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
