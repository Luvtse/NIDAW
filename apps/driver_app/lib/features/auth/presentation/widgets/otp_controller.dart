import 'package:flutter/foundation.dart';

import '../../domain/entities/driver.dart';
import '../../data/repositories/auth_repository.dart';

/// Outcome of an OTP verification attempt on the driver entry path.
class DriverOtpSignInResult {
  const DriverOtpSignInResult._({
    this.driver,
    this.verificationTicket,
    this.error,
    this.errorCode,
  });

  const DriverOtpSignInResult.success(Driver driver)
      : this._(driver: driver);

  const DriverOtpSignInResult.unregistered(
      {required String verificationTicket})
      : this._(verificationTicket: verificationTicket);

  const DriverOtpSignInResult.failure(
      {required String error, String? errorCode})
      : this._(error: error, errorCode: errorCode);

  final Driver? driver;
  final String? verificationTicket;
  final String? error;
  final String? errorCode;

  bool get signedIn => driver != null;
  bool get phoneUnregistered => verificationTicket != null;
}

/// ChangeNotifier driving the phone+OTP state machine for the driver app:
/// send code -> verify code -> session (login) or ticket (register).
/// Mirrors the consumer app's PhoneOtpController.
class DriverOtpController extends ChangeNotifier {
  DriverOtpController(this._authRepository);

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

  /// Request a code for [phone] bound to [operation] (login|register|recovery),
  /// always with account_type=driver.
  Future<bool> sendCode({
    required String phone,
    String operation = 'login',
  }) async {
    _busy = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
    final result = await _authRepository.requestOtp(
      phone: phone,
      operation: operation,
    );
    _busy = false;
    if (result.isFailure) {
      _error = result.error;
      _errorCode = result.errorCode;
      // A cooldown rejection still means a code is in flight: start the
      // countdown from the wait the server advertised instead of letting
      // the user hammer the rate limit.
      if (result.errorCode == 'OTP_COOLDOWN') {
        final match = _secondsInMessage.firstMatch(result.error ?? '');
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

  /// Verify [code]. Returns either a signed-in driver, a registration
  /// ticket for an unregistered number, or a failure with its error code.
  Future<DriverOtpSignInResult> signInWithCode({
    required String phone,
    required String code,
  }) async {
    _busy = true;
    _error = null;
    _errorCode = null;
    notifyListeners();
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
      return DriverOtpSignInResult.failure(
        error: result.error!,
        errorCode: result.errorCode,
      );
    }
    if (result.driver != null) {
      // Session opened and tokens persisted by the repository; the screen
      // dispatches OtpLoginCompleted to drive the AuthBloc state.
      _codeSent = false;
      notifyListeners();
      return DriverOtpSignInResult.success(result.driver!);
    }
    // Register branch: the number has no account yet but the code was
    // valid - hand the ticket to the signup flow.
    _codeSent = false;
    notifyListeners();
    return DriverOtpSignInResult.unregistered(
      verificationTicket: result.verificationTicket!,
    );
  }
}
