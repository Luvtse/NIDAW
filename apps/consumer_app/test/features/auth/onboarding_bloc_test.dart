import 'package:flutter_test/flutter_test.dart';

import 'package:nidaw_app/core/network/api_client.dart';
import 'package:nidaw_app/features/auth/data/repositories/auth_repository.dart';
import 'package:nidaw_app/features/auth/domain/entities/onboarding_status.dart';
import 'package:nidaw_app/features/auth/presentation/bloc/onboarding_bloc.dart';

/// Minimal scripted fake of the auth repository covering only the calls the
/// onboarding chain performs. The field names below double as an API-contract
/// check against the Go JSON tags in
/// services/api/internal/modules/auth/interfaces/http/onboarding_handlers.go.
class _FakeAuthRepository implements AuthRepository {
  OnboardingStatus? statusToReturn;
  ApiException? statusError;
  String? ticketToReturn;
  ApiException? ticketError;
  OnboardingStatus? completeResult;
  ApiException? completeError;

  List<String>? completeAgreements;
  String? lastOtpPhone;
  String? lastOtpOperation;
  String? lastTicketCode;

  OtpRequestResult otpRequestResult = const OtpRequestResult.success(
    expiresInSeconds: 300,
    resendAfterSeconds: 30,
  );

  @override
  Future<OnboardingStatus> fetchOnboardingStatus() async {
    if (statusError != null) throw statusError!;
    return statusToReturn!;
  }

  @override
  Future<OtpRequestResult> requestOtp({
    required String phone,
    required String operation,
    String accountType = 'rider',
  }) async {
    lastOtpPhone = phone;
    lastOtpOperation = operation;
    return otpRequestResult;
  }

  @override
  Future<ConsentTicket> requestConsentTicket({required String code}) async {
    if (ticketError != null) throw ticketError!;
    lastTicketCode = code;
    return ConsentTicket(
      value: ticketToReturn ?? 'ticket-abc',
      expiresInSeconds: 120,
    );
  }

  @override
  Future<OnboardingStatus> completeOnboarding({
    required String consentTicket,
    required List<String> agreements,
  }) async {
    if (completeError != null) throw completeError!;
    completeAgreements = agreements;
    return completeResult!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not needed for this test');
}

OnboardingStatus _status({
  required bool complete,
  bool phoneVerified = true,
}) {
  final status = OnboardingStatus.fromJson(const <String, dynamic>{
    'phone_verified': true,
    'complete': false,
    'required_agreements': [
      {
        'document_type': 'terms_of_service',
        'title': 'Terms of Service',
        'version': 'v2',
        'accepted': false,
        'outdated': false,
      },
      {
        'document_type': 'privacy_policy',
        'title': 'Privacy Policy',
        'version': 'v1',
        'accepted': false,
        'outdated': false,
      },
    ],
    'missing_agreements': ['terms_of_service', 'privacy_policy'],
    'profile_fields_missing': ['full_name', 'email'],
  });
  return OnboardingStatus(
    complete: complete,
    phoneVerified: phoneVerified,
    agreements: status.agreements,
    missingAgreements: status.missingAgreements,
    profileFieldsMissing: status.profileFieldsMissing,
  );
}

void main() {
  late _FakeAuthRepository repo;
  late OnboardingBloc bloc;

  setUp(() {
    repo = _FakeAuthRepository();
    bloc = OnboardingBloc(authRepository: repo);
  });

  group('OnboardingBloc.loadStatus', () {
    test('stores the server checklist and exposes required agreement types',
        () async {
      repo.statusToReturn = _status(complete: false);
      await bloc.loadStatus();

      expect(bloc.error, isNull);
      expect(bloc.isLoading, isFalse);
      expect(bloc.status?.complete, isFalse);
      // Required set comes from the server, never hardcoded client-side.
      expect(
        bloc.requiredAgreementTypes,
        ['terms_of_service', 'privacy_policy'],
      );
      // Optional profile gaps are surfaced but informational only.
      expect(bloc.status?.profileFieldsMissing, contains('full_name'));
    });

    test('surfaces API errors with the business error code', () async {
      repo.statusError = const ApiException(
        message: 'Session expired',
        statusCode: 401,
        errorCode: 'TOKEN_EXPIRED',
      );
      await bloc.loadStatus();

      expect(bloc.error, 'Session expired');
      expect(bloc.errorCode, 'TOKEN_EXPIRED');
      expect(bloc.isLoading, isFalse);
    });
  });

  group('OnboardingBloc.sendVerificationCode', () {
    test('requests an OTP bound to operation=register for the account phone',
        () async {
      await bloc.sendVerificationCode('+251911223344');

      expect(repo.lastOtpPhone, '+251911223344');
      expect(repo.lastOtpOperation, 'register');
      expect(bloc.otpSent, isTrue);
      expect(bloc.resendCountdownSeconds, greaterThan(0));
      expect(bloc.error, isNull);
    });

    test('OTP_COOLDOWN starts the countdown from the server-advertised wait',
        () async {
      repo.otpRequestResult = const OtpRequestResult.failure(
        error: 'Please wait 45 seconds before requesting a new code',
        errorCode: 'OTP_COOLDOWN',
      );
      await bloc.sendVerificationCode('+251911223344');

      expect(bloc.otpSent, isFalse);
      expect(bloc.errorCode, 'OTP_COOLDOWN');
      expect(bloc.resendCountdownSeconds, greaterThan(0));
    });

    test('OTP_LOCKED surfaces the lockout without a countdown', () async {
      repo.otpRequestResult = const OtpRequestResult.failure(
        error: 'Too many attempts. Try again later.',
        errorCode: 'OTP_LOCKED',
      );
      await bloc.sendVerificationCode('+251911223344');

      expect(bloc.errorCode, 'OTP_LOCKED');
      expect(bloc.resendCountdownSeconds, 0);
    });
  });

  group('OnboardingBloc.activate', () {
    test('runs the consent-ticket -> complete chain and returns completion',
        () async {
      repo.ticketToReturn = 'single-use-ticket';
      repo.completeResult = _status(complete: true);

      final result = await bloc.activate(
        code: '123456',
        agreements: const ['terms_of_service', 'privacy_policy'],
      );

      expect(repo.lastTicketCode, '123456');
      expect(
        repo.completeAgreements,
        ['terms_of_service', 'privacy_policy'],
      );
      expect(result?.complete, isTrue);
      expect(bloc.isSubmitting, isFalse);
      expect(bloc.error, isNull);
      expect(bloc.otpSent, isFalse);
    });

    test('server-incomplete result keeps the user on-screen with the checklist',
        () async {
      // A 412 answer maps to a non-complete status carrying the remaining
      // checklist — not a crash and not a fake success.
      repo.ticketToReturn = 'ticket';
      repo.completeResult = _status(complete: false);

      final result = await bloc.activate(
        code: '123456',
        agreements: const ['terms_of_service'],
      );

      expect(result?.complete, isFalse);
      expect(bloc.error, isNull);
      expect(bloc.status?.missingAgreements, contains('privacy_policy'));
    });

    test('OTP_INVALID resets the sent flag so a fresh code can be requested',
        () async {
      repo.ticketError = const ApiException(
        message: 'Invalid or expired code',
        statusCode: 400,
        errorCode: 'OTP_INVALID',
      );
      await bloc.sendVerificationCode('+251911223344');
      expect(bloc.otpSent, isTrue);

      final result =
          await bloc.activate(code: '000000', agreements: const []);

      expect(result, isNull);
      expect(bloc.errorCode, 'OTP_INVALID');
      expect(bloc.otpSent, isFalse);
      expect(bloc.isSubmitting, isFalse);
    });

    test('CONSENT_VERIFICATION_REQUIRED forces re-proof before completing',
        () async {
      repo.completeError = const ApiException(
        message: 'Fresh phone verification is required',
        statusCode: 403,
        errorCode: 'CONSENT_VERIFICATION_REQUIRED',
      );

      await bloc.activate(
          code: '123456', agreements: const ['terms_of_service']);

      expect(bloc.errorCode, 'CONSENT_VERIFICATION_REQUIRED');
      expect(bloc.otpSent, isFalse);
    });
  });

  group('skip-and-complete-later gating', () {
    test('missing optional profile fields never block activation', () async {
      // Regression guard for the roadmap rule: riders may book rides and
      // order food while profile_fields_missing is non-empty. The gate is
      // ONLY the server-computed `complete` flag, which ignores optional
      // fields — the client must not derive gating from anything else.
      repo.statusToReturn = _status(complete: true);
      await bloc.loadStatus();

      expect(bloc.status?.complete, isTrue);
      expect(bloc.status?.canUseApp, isTrue);
      expect(bloc.status?.profileFieldsMissing, isNotEmpty);
      expect(bloc.requiredAgreementTypes, isNotEmpty);
    });

    test('unverified phone blocks activation even with all consents', () async {
      repo.statusToReturn = _status(complete: false, phoneVerified: false);
      await bloc.loadStatus();

      expect(bloc.status?.complete, isFalse);
      expect(bloc.status?.canUseApp, isFalse);
      expect(bloc.status?.phoneVerified, isFalse);
    });
  });
}
