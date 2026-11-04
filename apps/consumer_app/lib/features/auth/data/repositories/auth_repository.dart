
import 'package:flutter/foundation.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/onboarding_status.dart';
import '../../domain/entities/user.dart';

// ============================================================================
// ABSTRACT INTERFACE
// ============================================================================

/// OTP request result.
class OtpRequestResult {
  final int expiresInSeconds;
  final int resendAfterSeconds;
  final String? error;
  final String? errorCode;

  const OtpRequestResult._({
    this.expiresInSeconds = 0,
    this.resendAfterSeconds = 0,
    this.error,
    this.errorCode,
  });

  const OtpRequestResult.success({
    required int expiresInSeconds,
    required int resendAfterSeconds,
  }) : this._(
          expiresInSeconds: expiresInSeconds,
          resendAfterSeconds: resendAfterSeconds,
        );

  const OtpRequestResult.failure({required String error, String? errorCode})
      : this._(error: error, errorCode: errorCode);

  bool get isFailure => error != null;
}

/// OTP verify result. For login/recovery of an existing account [auth] is
/// set; for first-time registration [verificationTicket] is set and must be
/// spent on [registerPhone].
class OtpVerifyResult {
  final AuthResult? auth;
  final String? verificationTicket;
  final int ticketExpiresInSeconds;
  final String? error;
  final String? errorCode;

  const OtpVerifyResult._({
    this.auth,
    this.verificationTicket,
    this.ticketExpiresInSeconds = 0,
    this.error,
    this.errorCode,
  });

  const OtpVerifyResult.signedIn(AuthResult auth) : this._(auth: auth);

  const OtpVerifyResult.registered({
    required String verificationTicket,
    required int ticketExpiresInSeconds,
  }) : this._(
          verificationTicket: verificationTicket,
          ticketExpiresInSeconds: ticketExpiresInSeconds,
        );

  const OtpVerifyResult.failure({required String error, String? errorCode})
      : this._(error: error, errorCode: errorCode);

  bool get isFailure => error != null;
}

/// Abstract repository interface for authentication operations
abstract class AuthRepository {
  /// Request a phone OTP challenge bound to an operation
  /// (login | register | recovery). Also serves as the resend path; the
  /// server enforces cooldowns and returns the wait time as an error.
  Future<OtpRequestResult> requestOtp({
    required String phone,
    required String operation,
    String accountType = 'rider',
  });

  /// Verify a phone OTP code. Returns either a signed-in session or a
  /// registration ticket depending on server state.
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String code,
    required String operation,
    String accountType = 'rider',
  });

  /// Create a rider/driver account using a fresh otp/verify(register) ticket.
  /// Email, password and full name are all optional.
  Future<AuthResult> registerPhone({
    required String verificationTicket,
    String? fullName,
    String? email,
    String? password,
  });

  /// Login with email and password
  Future<AuthResult> login({
    required String email,
    required String password,
  });

  /// Register a new user
  Future<AuthResult> register({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  });

  /// Logout the current user
  Future<void> logout();

  /// Check if user has stored tokens
  Future<bool> hasStoredTokens();

  /// Validate the current access token
  Future<bool> validateAccessToken();

  /// Refresh the access token using refresh token
  Future<bool> refreshAccessToken();

  /// Get the current user profile
  Future<User?> getCurrentUser();

  /// Get the current access token
  Future<String?> getAccessToken();

  /// Get token expiration time
  Future<DateTime?> getTokenExpiration();

  /// Check if onboarding is complete
  Future<bool> isOnboardingComplete();

  /// Full server-authoritative activation checklist.
  Future<OnboardingStatus> fetchOnboardingStatus();

  /// Verify the account's own phone OTP and obtain a single-use consent
  /// ticket authorizing POST /api/v1/auth/onboarding/complete.
  Future<ConsentTicket> requestConsentTicket({required String code});

  /// Accept the required agreements (OTP-proofed) and activate the account.
  /// Returns the resulting status; [complete] false means agreements are
  /// still missing (server answered 412), not an error.
  Future<OnboardingStatus> completeOnboarding({
    required String consentTicket,
    required List<String> agreements,
  });

  /// Mark onboarding as complete
  Future<void> markOnboardingComplete();

  /// Clear all stored tokens
  Future<void> clearStoredTokens();
}

// ============================================================================
// AUTH RESULT
// ============================================================================

/// Auth result from login/register
class AuthResult {
  final User? user;
  final String? error;
  final String? errorCode;

  const AuthResult._({this.user, this.error, this.errorCode});

  const AuthResult.success(User user) : this._(user: user);
  const AuthResult.failure({required String error, String? errorCode})
      : this._(error: error, errorCode: errorCode);

  bool get isSuccess => user != null;
  bool get isFailure => error != null;
}

// ============================================================================
// TOKEN STORAGE INTERFACE
// ============================================================================

/// Interface for secure token storage
// NOTE: TokenStorage abstract contract intentionally not redeclared here;
// the single canonical definition lives in core/network/api_client.dart.

// ============================================================================
// IMPLEMENTATION
// ============================================================================

/// Concrete implementation of AuthRepository
class AuthRepositoryImpl implements AuthRepository {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  // In-memory cache for current user
  User? _cachedUser;
  bool? _onboardingComplete;

  AuthRepositoryImpl({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
  })  : _apiClient = apiClient,
        _tokenStorage = tokenStorage {
    // Set up unauthorized callback for token refresh
    _apiClient.onUnauthorized = _handleUnauthorized;
  }

  // ==========================================================================
  // PHONE + OTP (Phase 2/3 flow)
  // ==========================================================================

  @override
  Future<OtpRequestResult> requestOtp({
    required String phone,
    required String operation,
    String accountType = 'rider',
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/otp/request',
        data: {
          'phone': phone,
          'account_type': accountType,
          'operation': operation,
        },
      );

      final data = response.data as Map<String, dynamic>;
      return OtpRequestResult.success(
        expiresInSeconds: (data['expires_in'] as num?)?.toInt() ?? 0,
        resendAfterSeconds: (data['resend_after_seconds'] as num?)?.toInt() ?? 30,
      );
    } on ApiException catch (e) {
      return OtpRequestResult.failure(error: e.message, errorCode: e.errorCode);
    } catch (e) {
      return OtpRequestResult.failure(
        error: 'Could not send the verification code. Check your connection.',
        errorCode: 'UNKNOWN_ERROR',
      );
    }
  }

  @override
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String code,
    required String operation,
    String accountType = 'rider',
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/otp/verify',
        data: {
          'phone': phone,
          'code': code,
          'account_type': accountType,
          'operation': operation,
        },
      );

      final data = response.data as Map<String, dynamic>;

      // Registration path: single-use ticket spent on register-phone.
      final ticket = data['verification_ticket'] as String?;
      if (ticket != null && ticket.isNotEmpty) {
        return OtpVerifyResult.registered(
          verificationTicket: ticket,
          ticketExpiresInSeconds:
              (data['ticket_expires_in'] as num?)?.toInt() ?? 600,
        );
      }

      // Login path: full token pair returned.
      if (data['access_token'] is String) {
        return OtpVerifyResult.signedIn(await _persistSession(data));
      }

      return const OtpVerifyResult.failure(
        error: 'Unexpected verification response',
        errorCode: 'MALFORMED_RESPONSE',
      );
    } on ApiException catch (e) {
      return OtpVerifyResult.failure(error: e.message, errorCode: e.errorCode);
    } catch (e) {
      return OtpVerifyResult.failure(
        error: 'Verification failed: ${e.toString()}',
        errorCode: 'UNKNOWN_ERROR',
      );
    }
  }

  @override
  Future<AuthResult> registerPhone({
    required String verificationTicket,
    String? fullName,
    String? email,
    String? password,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/register-phone',
        data: {
          'verification_ticket': verificationTicket,
            if (fullName != null && fullName.trim().isNotEmpty)
              'full_name': fullName.trim(),
            if (email != null && email.trim().isNotEmpty)
              'email': email.trim(),
            if (password != null && password.isNotEmpty)
              'password': password,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final result = await _persistSession(data);
      // New accounts have not completed legal-consent activation yet.
      _onboardingComplete = false;
      return result;
    } on ConflictException {
      return const AuthResult.failure(
        error: 'This phone or email could not be used for a new account',
        errorCode: 'IDENTITY_CONFLICT',
      );
    } on ApiException catch (e) {
      return AuthResult.failure(error: e.message, errorCode: e.errorCode);
    } catch (e) {
      return AuthResult.failure(
        error: 'Registration failed: ${e.toString()}',
        errorCode: 'UNKNOWN_ERROR',
      );
    }
  }

  /// Stores the token pair from an auth response body and builds the
  /// [AuthResult]. Shared by login/register/otp-verify/register-phone.
  Future<AuthResult> _persistSession(Map<String, dynamic> data) async {
    final accessToken = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String;
    final expiresIn = (data['expires_in'] as num).toInt();

    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    await _tokenStorage.saveTokenExpiration(expiresAt);

    final userData = data['user'] as Map<String, dynamic>?;
    if (userData == null) {
      return const AuthResult.failure(
        error: 'Malformed authentication response',
        errorCode: 'MALFORMED_RESPONSE',
      );
    }
    final user = User.fromJson(userData);
    _cachedUser = user;
    return AuthResult.success(user);
  }

  // ==========================================================================
  // LOGIN / REGISTER
  // ==========================================================================

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      final data = response.data as Map<String, dynamic>;
      return await _persistSession(data);
    } on UnauthorizedException catch (e) {
      return AuthResult.failure(
        error: e.message,
        errorCode: e.errorCode,
      );
    } on ApiException catch (e) {
      return AuthResult.failure(
        error: e.message,
        errorCode: e.errorCode,
      );
    } catch (e) {
      return AuthResult.failure(
        error: 'Login failed: ${e.toString()}',
        errorCode: 'UNKNOWN_ERROR',
      );
    }
  }

  @override
  Future<AuthResult> register({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/register',
        data: {
          'email': email,
          'password': password,
          'full_name': fullName,
          'phone': phone,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final result = await _persistSession(data);

      // New users haven't completed onboarding
      _onboardingComplete = false;

      return result;
    } on ConflictException {
      return AuthResult.failure(
        error: 'An account with this email already exists',
        errorCode: 'EMAIL_EXISTS',
      );
    } on ValidationException catch (e) {
      return AuthResult.failure(
        error: e.message,
        errorCode: e.errorCode,
      );
    } on ApiException catch (e) {
      return AuthResult.failure(
        error: e.message,
        errorCode: e.errorCode,
      );
    } catch (e) {
      return AuthResult.failure(
        error: 'Registration failed: ${e.toString()}',
        errorCode: 'UNKNOWN_ERROR',
      );
    }
  }

  // ==========================================================================
  // LOGOUT
  // ==========================================================================

  @override
  Future<void> logout() async {
    try {
      // Try to call logout endpoint (best effort). Send the stored refresh
      // token so the server revokes this device's exact session family
      // instead of falling back to revoke-all-for-user.
      try {
        final refreshToken = await _tokenStorage.getRefreshToken();
        await _apiClient.post(
          '/api/v1/auth/logout',
          data: (refreshToken != null && refreshToken.isNotEmpty)
              ? {'refresh_token': refreshToken}
              : null,
        );
      } catch (_) {
        // Best effort: local state is cleared in the finally block anyway.
      }
    } finally {
      // Always clear local state
      await _tokenStorage.clearTokens();
      _cachedUser = null;
      _onboardingComplete = null;
    }
  }

  // ==========================================================================
  // TOKEN MANAGEMENT
  // ==========================================================================

  @override
  Future<bool> hasStoredTokens() async {
    final accessToken = await _tokenStorage.getAccessToken();
    return accessToken != null && accessToken.isNotEmpty;
  }

  @override
  Future<bool> validateAccessToken() async {
    try {
      final token = await _tokenStorage.getAccessToken();
      if (token == null) return false;

      // Call a protected endpoint to validate
      await _apiClient.get('/api/v1/auth/me');
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> refreshAccessToken() async {
    try {
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken == null) return false;

      final response = await _apiClient.post(
        '/api/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      final data = response.data as Map<String, dynamic>;
      
      final newAccessToken = data['access_token'] as String;
      final newRefreshToken = data['refresh_token'] as String;
      final expiresIn = data['expires_in'] as int;

      await _tokenStorage.saveTokens(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
      );

      final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      await _tokenStorage.saveTokenExpiration(expiresAt);

      return true;
    } catch (e) {
      debugPrint('Token refresh failed: $e');
      return false;
    }
  }

  @override
  Future<String?> getAccessToken() async {
    return await _tokenStorage.getAccessToken();
  }

  @override
  Future<DateTime?> getTokenExpiration() async {
    return await _tokenStorage.getTokenExpiration();
  }

  @override
  Future<void> clearStoredTokens() async {
    await _tokenStorage.clearTokens();
    _cachedUser = null;
  }

  // ==========================================================================
  // USER PROFILE
  // ==========================================================================

  @override
  Future<User?> getCurrentUser() async {
    // Return cached user if available
    if (_cachedUser != null) {
      return _cachedUser;
    }

    try {
      final response = await _apiClient.get('/api/v1/auth/me');
      final data = response.data as Map<String, dynamic>;
      final user = User.fromJson(data['user'] as Map<String, dynamic>);
      _cachedUser = user;
      return user;
    } catch (e) {
      debugPrint('Failed to get current user: $e');
      return null;
    }
  }

  // ==========================================================================
  // ONBOARDING
  // ==========================================================================

  @override
  Future<bool> isOnboardingComplete() async {
    if (_onboardingComplete != null) {
      return _onboardingComplete!;
    }

    try {
      final status = await fetchOnboardingStatus();
      _onboardingComplete = status.complete;
      return status.complete;
    } catch (e) {
      debugPrint('Failed to check onboarding status: $e');
      return false;
    }
  }

  @override
  Future<OnboardingStatus> fetchOnboardingStatus() async {
    final response = await _apiClient.get('/api/v1/auth/onboarding-status');
    final data = response.data as Map<String, dynamic>;
    final status = OnboardingStatus.fromJson(data);
    _onboardingComplete = status.complete;
    return status;
  }

  @override
  Future<ConsentTicket> requestConsentTicket({required String code}) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/onboarding/consent-ticket',
        data: {'code': code},
      );
      final data = response.data as Map<String, dynamic>;
      final ticket = ConsentTicket.fromJson(data);
      if (ticket.value.isEmpty) {
        throw const ApiException(
          message: 'Verification did not produce a consent ticket',
          errorCode: 'MALFORMED_RESPONSE',
        );
      }
      return ticket;
    } on UnauthorizedException {
      // A 401 here means the OTP was wrong/expired (server code
      // OTP_EXPIRED / OTP_INVALID), not that the session died — do not let
      // it be mistaken for an auth-token problem.
      rethrow;
    } on ApiException catch (e) {
      throw e;
    } catch (e) {
      throw ApiException(
        message: 'Could not verify the code: ${e.toString()}',
        errorCode: 'UNKNOWN_ERROR',
      );
    }
  }

  @override
  Future<OnboardingStatus> completeOnboarding({
    required String consentTicket,
    required List<String> agreements,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/onboarding/complete',
        data: {
          'consent_ticket': consentTicket,
          'agreements': agreements,
        },
      );
      final data = response.data as Map<String, dynamic>;
      final status = OnboardingStatus.fromJson(data);
      _onboardingComplete = status.complete;
      return status;
    } on ApiException catch (e) {
      // 412 Precondition Failed carries the updated checklist body: the
      // account is simply not fully activated yet, not a transport error.
      if (e.statusCode == 412 && e.responseData is Map<String, dynamic>) {
        final status = OnboardingStatus.fromJson(e.responseData as Map<String, dynamic>);
        _onboardingComplete = status.complete;
        return status;
      }
      rethrow;
    }
  }

  @override
  Future<void> markOnboardingComplete() async {
    try {
      final status = await fetchOnboardingStatus();
      if (status.complete) {
        return;
      }
      // The server refuses completion without an OTP-bound consent ticket;
      // callers must go through completeOnboarding(). Surfacing this as an
      // error keeps stale local state from faking activation.
      throw const ApiException(
        message: 'Phone verification and agreement acceptance are required before activation',
        errorCode: 'CONSENT_VERIFICATION_REQUIRED',
      );
    } catch (e) {
      debugPrint('Failed to mark onboarding complete: $e');
      rethrow;
    }
  }

  // ==========================================================================
  // TOKEN REFRESH HANDLER
  // ==========================================================================

  /// Called by ApiClient when a 401 is received
  Future<void> _handleUnauthorized() async {
    debugPrint('Unauthorized - attempting token refresh');
    final refreshed = await refreshAccessToken();
    if (!refreshed) {
      // Refresh failed, force logout
      await logout();
    }
  }
}