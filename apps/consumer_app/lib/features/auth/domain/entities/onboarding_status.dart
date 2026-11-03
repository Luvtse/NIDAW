import 'package:equatable/equatable.dart';

/// One legal agreement from GET /api/v1/auth/onboarding-status.
class AgreementStatus extends Equatable {
  const AgreementStatus({
    required this.documentType,
    required this.title,
    required this.version,
    required this.accepted,
    required this.outdated,
    this.acceptedAt,
    this.acceptedVersion,
  });

  final String documentType;
  final String title;
  final String version;
  final bool accepted;
  final bool outdated;
  final DateTime? acceptedAt;
  final String? acceptedVersion;

  /// Acceptance is only valid for the current policy version.
  bool get acceptedAtCurrentVersion => accepted && !outdated;

  factory AgreementStatus.fromJson(Map<String, dynamic> json) {
    return AgreementStatus(
      documentType: json['document_type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      version: json['version'] as String? ?? '',
      accepted: json['accepted'] as bool? ?? false,
      outdated: json['outdated'] as bool? ?? false,
      acceptedAt: json['accepted_at'] == null
          ? null
          : DateTime.tryParse(json['accepted_at'] as String),
      acceptedVersion: json['accepted_version'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [documentType, title, version, accepted, outdated, acceptedAt, acceptedVersion];
}

/// Server-authoritative rider activation checklist.
class OnboardingStatus extends Equatable {
  const OnboardingStatus({
    required this.complete,
    required this.phoneVerified,
    required this.agreements,
    required this.missingAgreements,
    required this.profileFieldsMissing,
    this.activatedAt,
  });

  final bool complete;
  final bool phoneVerified;
  final List<AgreementStatus> agreements;
  final List<String> missingAgreements;
  final List<String> profileFieldsMissing;
  final DateTime? activatedAt;

  /// Optional profile fields never gate booking or ordering: this mirrors the
  /// server rule that activation = verified phone + accepted agreements only.
  bool get canUseApp => complete;

  factory OnboardingStatus.fromJson(Map<String, dynamic> json) {
    final rawAgreements = json['required_agreements'];
    final rawMissing = json['missing_agreements'];
    final rawProfile = json['profile_fields_missing'];
    return OnboardingStatus(
      complete: json['complete'] as bool? ?? false,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      agreements: rawAgreements is List
          ? rawAgreements
              .whereType<Map<String, dynamic>>()
              .map(AgreementStatus.fromJson)
              .toList()
          : const [],
      missingAgreements: rawMissing is List
          ? rawMissing.whereType<String>().toList()
          : const [],
      profileFieldsMissing: rawProfile is List
          ? rawProfile.whereType<String>().toList()
          : const [],
      activatedAt: json['activated_at'] == null
          ? null
          : DateTime.tryParse(json['activated_at'] as String),
    );
  }

  /// Conservative fallback when the status endpoint is unreachable: treat the
  /// account as not-yet-activated so the consent screen re-checks with the
  /// server instead of silently skipping legally-required acceptance.
  factory OnboardingStatus.unknown() {
    return const OnboardingStatus(
      complete: false,
      phoneVerified: false,
      agreements: [],
      missingAgreements: [],
      profileFieldsMissing: [],
    );
  }

  @override
  List<Object?> get props => [
        complete,
        phoneVerified,
        agreements,
        missingAgreements,
        profileFieldsMissing,
        activatedAt,
      ];
}

/// Response of POST /api/v1/auth/onboarding/consent-ticket.
class ConsentTicket extends Equatable {
  const ConsentTicket({
    required this.value,
    required this.expiresInSeconds,
  });

  final String value;
  final int expiresInSeconds;

  factory ConsentTicket.fromJson(Map<String, dynamic> json) {
    return ConsentTicket(
      value: json['consent_ticket'] as String? ?? '',
      expiresInSeconds: (json['ticket_expires_in'] as num?)?.toInt() ?? 300,
    );
  }

  @override
  List<Object?> get props => [value, expiresInSeconds];
}
