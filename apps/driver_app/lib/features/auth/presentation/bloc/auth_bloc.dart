import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../data/repositories/auth_repository.dart';
import '../../domain/entities/driver.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/register_usecase.dart';
import '../../../../core/network/websocket_client.dart';
import '../../../../core/startup/driver_startup_coordinator.dart';

// Events
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class CheckAuthStatus extends AuthEvent {
  const CheckAuthStatus();
}

class LoginRequested extends AuthEvent {
  final String email;
  final String password;

  const LoginRequested({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];
}

class RegisterRequested extends AuthEvent {
  final Map<String, dynamic> data;

  const RegisterRequested({required this.data});

  @override
  List<Object?> get props => [data];
}

class LogoutRequested extends AuthEvent {
  const LogoutRequested();
}

// States
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final Driver driver;
  final bool onboardingComplete;

  const AuthAuthenticated({
    required this.driver,
    required this.onboardingComplete,
  });

  @override
  List<Object?> get props => [driver, onboardingComplete];
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object?> get props => [message];
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase _loginUseCase;
  final RegisterUseCase _registerUseCase;
  final AuthRepository _authRepository;
  final WebSocketClient _webSocketClient;

  AuthBloc({
    required LoginUseCase loginUseCase,
    required RegisterUseCase registerUseCase,
    required AuthRepository authRepository,
    required WebSocketClient webSocketClient,
  })  : _loginUseCase = loginUseCase,
        _registerUseCase = registerUseCase,
        _authRepository = authRepository,
        _webSocketClient = webSocketClient,
        super(const AuthInitial()) {
    on<CheckAuthStatus>(_onCheckAuthStatus);
    on<LoginRequested>(_onLoginRequested);
    on<RegisterRequested>(_onRegisterRequested);
    on<LogoutRequested>(_onLogoutRequested);
  }

    /// Phase 5 (§4.3): every successful authentication notifies the startup
  /// coordinator so the WebSocket connect + `driver:offers` subscription are
  /// wired exactly when a token exists — replacing the legacy post-runApp
  /// delay hack. No-op in widget tests that never install a coordinator.
  void _notifyStartupAuthenticated() {
    if (hasDriverStartupCoordinator) {
      unawaited(currentDriverStartupCoordinator.onAuthenticated());
    }
  }

Future<void> _onCheckAuthStatus(
    CheckAuthStatus event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final isAuthenticated = await _authRepository.isAuthenticated();
      
      if (!isAuthenticated) {
        emit(const AuthUnauthenticated());
        return;
      }

      final driver = await _authRepository.getCurrentDriver();
      
      if (driver == null) {
        emit(const AuthUnauthenticated());
        return;
      }

      final onboardingComplete = driver.isVerified;
      await _webSocketClient.connect();
      _notifyStartupAuthenticated();

      emit(AuthAuthenticated(
        driver: driver,
        onboardingComplete: onboardingComplete,
      ));
    } catch (e) {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final driver = await _loginUseCase.execute(
        event.email,
        event.password,
      );

      final onboardingComplete = driver.isVerified;
      await _webSocketClient.connect();
      _notifyStartupAuthenticated();

      emit(AuthAuthenticated(
        driver: driver,
        onboardingComplete: onboardingComplete,
      ));
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }

  Future<void> _onRegisterRequested(
    RegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final driver = await _registerUseCase.execute(event.data);

      await _webSocketClient.connect();
      _notifyStartupAuthenticated();
      emit(AuthAuthenticated(
        driver: driver,
        onboardingComplete: false,
      ));
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      await _authRepository.logout();
      _webSocketClient.disconnect();
      emit(const AuthUnauthenticated());
    } catch (e) {
      emit(AuthError(message: e.toString()));
    }
  }
}