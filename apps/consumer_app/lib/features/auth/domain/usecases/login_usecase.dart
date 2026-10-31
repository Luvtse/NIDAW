import 'package:equatable/equatable.dart';

import '../../data/repositories/auth_repository.dart';

// ============================================================================
// INPUT PARAMETERS
// ============================================================================

/// Parameters for the login use case
class LoginParams extends Equatable {
  final String email;
  final String password;

  const LoginParams({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];

  /// Validate the input parameters
  List<String> validate() {
    final errors = <String>[];

    if (email.isEmpty) {
      errors.add('Email is required');
    } else if (!_isValidEmail(email)) {
      errors.add('Invalid email format');
    }

    if (password.isEmpty) {
      errors.add('Password is required');
    } else if (password.length < 8) {
      errors.add('Password must be at least 8 characters');
    }

    return errors;
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }
}

// ============================================================================
// USE CASE
// ============================================================================

/// Use case for user login
/// 
/// This use case encapsulates the business logic for authenticating a user.
/// It validates input, calls the repository, and returns a typed result.
class LoginUseCase {
  final AuthRepository _authRepository;

  const LoginUseCase(this._authRepository);

  /// Execute the login use case
  /// 
  /// Returns an [AuthResult] containing either:
  /// - A [User] on success
  /// - An error message and code on failure
  Future<AuthResult> execute({
    required String email,
    required String password,
  }) async {
    // 1. Validate input
    final params = LoginParams(email: email, password: password);
    final validationErrors = params.validate();
    
    if (validationErrors.isNotEmpty) {
      return AuthResult.failure(
        error: validationErrors.join(', '),
        errorCode: 'VALIDATION_ERROR',
      );
    }

    // 2. Normalize input
    final normalizedEmail = email.trim().toLowerCase();

    // 3. Call repository
    final result = await _authRepository.login(
      email: normalizedEmail,
      password: password,
    );

    // 4. Return result (already typed by repository)
    return result;
  }

  /// Convenience method to check if login is possible without credentials
  Future<bool> hasActiveSession() async {
    final hasTokens = await _authRepository.hasStoredTokens();
    if (!hasTokens) return false;

    final isValid = await _authRepository.validateAccessToken();
    return isValid;
  }
}
