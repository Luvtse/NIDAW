import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/driver.dart';

/// OTP request result from POST /api/v1/auth/otp/request.
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

/// OTP verify result from POST /api/v1/auth/otp/verify. For an existing
/// driver account [driver] is set (session opened); for a verified but
/// unregistered number [verificationTicket] is set and must be spent on
/// [registerPhone].
class OtpVerifyResult {
  final Driver? driver;
  final String? verificationTicket;
  final int ticketExpiresInSeconds;
  final String? error;
  final String? errorCode;

  const OtpVerifyResult._({
    this.driver,
    this.verificationTicket,
    this.ticketExpiresInSeconds = 0,
    this.error,
    this.errorCode,
  });

  const OtpVerifyResult.signedIn(Driver driver) : this._(driver: driver);

  const OtpVerifyResult.unregistered({
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

abstract class AuthRepository {
  /// Request a phone OTP challenge bound to an operation
  /// (login | register | recovery), always for the driver account type.
  /// Also serves as the resend path; the server enforces cooldowns.
  Future<OtpRequestResult> requestOtp({
    required String phone,
    required String operation,
  });

  /// Verify a phone OTP code. Returns either a signed-in driver session or
  /// a registration ticket depending on server state.
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String code,
    required String operation,
  });

  /// Create a driver account using a fresh otp/verify(register) ticket.
  /// Full name, email and password are all optional; the drivers profile
  /// row is created server-side with onboarding_status='pending'.
  Future<Driver> registerPhone({
    required String verificationTicket,
    String? fullName,
    String? email,
    String? password,
  });

  Future<Driver> login(String email, String password);
  Future<Driver> register(Map<String, dynamic> data);
  Future<void> logout();
  Future<Driver?> getCurrentDriver();
  Future<bool> isAuthenticated();
  Future<String?> getAccessToken();
  Future<void> updateDriverStatus(String status);
}

class AuthRepositoryImpl implements AuthRepository {
  final ApiClient _apiClient;
  static const String _authBoxName = 'driver_auth';

  AuthRepositoryImpl({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<Box> _getAuthBox() async {
    return await Hive.openBox(_authBoxName);
  }

  // ==========================================================================
  // PHONE + OTP (driver entry path, mirrors the consumer app implementation)
  // ==========================================================================

  @override
  Future<OtpRequestResult> requestOtp({
    required String phone,
    required String operation,
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/otp/request',
        data: {
          'phone': phone,
          'account_type': 'driver',
          'operation': operation,
        },
      );

      final data = response.data as Map<String, dynamic>;
      return OtpRequestResult.success(
        expiresInSeconds: (data['expires_in'] as num?)?.toInt() ?? 0,
        resendAfterSeconds: (data['resend_after_seconds'] as num?)?.toInt() ?? 30,
      );
    } on DioException catch (e) {
      return OtpRequestResult.failure(
        error: _extractError(e),
        errorCode: _extractErrorCode(e),
      );
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
  }) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/otp/verify',
        data: {
          'phone': phone,
          'code': code,
          'account_type': 'driver',
          'operation': operation,
        },
      );

      final data = response.data as Map<String, dynamic>;

      // Registration path: single-use ticket spent on register-phone.
      final ticket = data['verification_ticket'] as String?;
      if (ticket != null && ticket.isNotEmpty) {
        return OtpVerifyResult.unregistered(
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
    } on DioException catch (e) {
      return OtpVerifyResult.failure(
        error: _extractError(e),
        errorCode: _extractErrorCode(e),
      );
    } catch (e) {
      return OtpVerifyResult.failure(
        error: 'Verification failed: ${e.toString()}',
        errorCode: 'UNKNOWN_ERROR',
      );
    }
  }

  @override
  Future<Driver> registerPhone({
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
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          if (password != null && password.isNotEmpty) 'password': password,
        },
      );

      final data = response.data as Map<String, dynamic>;
      return await _persistSession(data);
    } on DioException catch (e) {
      throw Exception(_extractError(e));
    }
  }

  /// Stores the token pair from an auth response body and loads the driver
  /// profile. Shared by login/register/otp-verify/register-phone.
  Future<Driver> _persistSession(Map<String, dynamic> data) async {
    final authBox = await _getAuthBox();
    await authBox.put('access_token', data['access_token']);
    await authBox.put('refresh_token', data['refresh_token']);
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 900;
    await authBox.put(
      'token_expires_at',
      DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch,
    );
    await authBox.put('base_url', _apiClient.baseUrl);

    final userData = data['user'] as Map<String, dynamic>?;
    if (userData == null) {
      throw Exception('Malformed authentication response');
    }
    final profileResponse = await _apiClient.get('/api/v1/nidus/drivers/profile');
    final profileData = profileResponse.data as Map<String, dynamic>;
    return Driver.fromJson({...userData, ...profileData});
  }

  static String _extractError(DioException e) {
    final resp = e.response;
    if (resp?.data is Map) {
      final map = resp!.data as Map;
      final err = map['error'];
      if (err is Map && err['message'] is String) return err['message'] as String;
      if (map['message'] is String) return map['message'] as String;
      if (map['error'] is String) return map['error'] as String;
    }
    return 'Request failed. Please try again.';
  }

  static String? _extractErrorCode(DioException e) {
    final resp = e.response;
    if (resp?.data is Map) {
      final map = resp!.data as Map;
      final err = map['error'];
      if (err is Map && err['code'] is String) return err['code'] as String;
      if (map['code'] is String) return map['code'] as String;
    }
    return null;
  }

  @override
  Future<Driver> login(String email, String password) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/login',
        data: {
          'email': email,
          'password': password,
          'role': 'driver',
        },
      );

      final data = response.data as Map<String, dynamic>;
      
      // Save tokens
      final authBox = await _getAuthBox();
      await authBox.put('access_token', data['access_token']);
      await authBox.put('refresh_token', data['refresh_token']);
      await authBox.put('token_expires_at', data['expires_in']);
      await authBox.put('base_url', _apiClient.baseUrl);

      // Get driver profile
      final driverData = data['user'] as Map<String, dynamic>;
      final driverResponse = await _apiClient.get('/api/v1/nidus/drivers/profile');
      final driverProfile = driverResponse.data as Map<String, dynamic>;

      return Driver.fromJson({
        ...driverData,
        ...driverProfile,
      });
    } catch (e) {
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  @override
  Future<Driver> register(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/auth/register',
        data: {
          ...data,
          'role': 'driver',
        },
      );

      final responseData = response.data as Map<String, dynamic>;
      
      // Save tokens
      final authBox = await _getAuthBox();
      await authBox.put('access_token', responseData['access_token']);
      await authBox.put('refresh_token', responseData['refresh_token']);
      await authBox.put('token_expires_at', responseData['expires_in']);
      await authBox.put('base_url', _apiClient.baseUrl);

      final driverData = responseData['user'] as Map<String, dynamic>;
      final profileResponse = await _apiClient.get('/api/v1/nidus/drivers/profile');
      final profileData = profileResponse.data as Map<String, dynamic>;
      return Driver.fromJson({...driverData, ...profileData});
    } catch (e) {
      throw Exception('Registration failed: ${e.toString()}');
    }
  }

  @override
  Future<void> logout() async {
    try {
      // Send the stored refresh token so the server revokes this device's
      // exact session family instead of falling back to revoke-all-for-user.
      final authBox = await _getAuthBox();
      final refreshToken = authBox.get('refresh_token');
      await _apiClient.post(
        '/api/v1/auth/logout',
        data: refreshToken != null ? {'refresh_token': refreshToken} : null,
      );
    } catch (e) {
      // Ignore logout errors
    } finally {
      final authBox = await _getAuthBox();
      await authBox.clear();
    }
  }

  @override
  Future<Driver?> getCurrentDriver() async {
    try {
      final authBox = await _getAuthBox();
      final token = authBox.get('access_token');
      
      if (token == null) return null;

      final response = await _apiClient.get('/api/v1/nidus/drivers/profile');
      final data = response.data as Map<String, dynamic>;
      
      return Driver.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    final authBox = await _getAuthBox();
    final token = authBox.get('access_token');
    final expiresAt = authBox.get('token_expires_at');
    
    if (token == null || expiresAt == null) return false;
    
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt);
    return expiry.isAfter(DateTime.now());
  }

  @override
  Future<String?> getAccessToken() async {
    final authBox = await _getAuthBox();
    return authBox.get('access_token') as String?;
  }

  @override
  Future<void> updateDriverStatus(String status) async {
    try {
      await _apiClient.post(
        status == 'available'
            ? '/api/v1/nidus/drivers/online'
            : '/api/v1/nidus/drivers/offline',
      );
    } catch (e) {
      throw Exception('Failed to update status: ${e.toString()}');
    }
  }
}