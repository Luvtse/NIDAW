import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_client.dart';

// ============================================================================
// ABSTRACT INTERFACE
// ============================================================================

/// Repository for rider safety features: SOS, trip sharing, and trusted
/// contacts. Backed by the `/api/v1/nidus/safety` endpoint group.
abstract class SafetyRepository {
  /// Trigger an emergency SOS for a ride. Returns the incident id.
  Future<SosResult> triggerSos({
    required String rideId,
    required double lat,
    required double lng,
    String? message,
  });

  /// Create a tokenized live-tracking link for an active ride.
  Future<ShareLinkResult> createShareLink({
    required String rideId,
    required String label,
  });

  /// List share links that are still active for [rideId].
  Future<List<SharedTripLink>> listActiveShareLinks(String rideId);

  /// Revoke a previously created share link.
  Future<bool> revokeShareLink(String linkId);

  /// Trusted contacts (auto-notified on SOS / long-trip check-ins).
  Future<List<TrustedContact>> listTrustedContacts();

  Future<TrustedContact> addTrustedContact({
    required String name,
    required String phone,
    bool autoNotify = true,
  });

  Future<bool> removeTrustedContact(String contactId);

  Future<bool> updateTrustedContact(
    String contactId, {
    String? name,
    String? phone,
    bool? autoNotify,
  });

  /// Subscribe to live location updates for a shared trip topic.
  Stream<SharedTripLocation> subscribeToSharedTrip(String linkToken);

  /// Unsubscribe from a shared trip topic.
  void unsubscribeFromSharedTrip(String linkToken);
}

// ============================================================================
// DOMAIN ENTITIES
// ============================================================================

/// Result of an SOS request.
class SosResult {
  final bool success;
  final String? incidentId;
  final String? errorCode;
  final String? message;

  const SosResult._({
    required this.success,
    this.incidentId,
    this.errorCode,
    this.message,
  });

  const SosResult.triggered({required this.incidentId})
      : success = true,
        errorCode = null,
        message = null;

  const SosResult.dialerOpened()
      : success = true,
        incidentId = null,
        errorCode = null,
        message = 'Phone dialer opened for the configured emergency number.';

  const SosResult.failure({
    required this.errorCode,
    required this.message,
  })  : success = false,
        incidentId = null;
}

/// Result of creating a share link.
class ShareLinkResult {
  final bool success;
  final SharedTripLink? link;
  final String? errorCode;
  final String? message;

  const ShareLinkResult._({
    required this.success,
    this.link,
    this.errorCode,
    this.message,
  });

  const ShareLinkResult.created({required this.link})
      : success = true,
        errorCode = null,
        message = null;

  const ShareLinkResult.failure({
    required this.errorCode,
    required this.message,
  })  : success = false,
        link = null;
}

/// A tokenized public tracking link for one ride.
class SharedTripLink {
  final String id;
  final String rideId;
  final String label;
  final String token;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const SharedTripLink({
    required this.id,
    required this.rideId,
    required this.label,
    required this.token,
    required this.createdAt,
    this.expiresAt,
  });

  factory SharedTripLink.fromJson(Map<String, dynamic> json) {
    return SharedTripLink(
      id: json['id'] as String,
      rideId: json['ride_id'] as String,
      label: json['label'] as String? ?? 'My trip',
      token: json['token'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
    );
  }

  /// Public web URL a contact can open without the app installed.
  String get publicUrl => 'https://nidus.app/track/$token';
}

/// A person the rider trusts with live trip data.
class TrustedContact {
  final String id;
  final String name;
  final String phone;
  final bool autoNotify;

  const TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    this.autoNotify = true,
  });

  factory TrustedContact.fromJson(Map<String, dynamic> json) {
    return TrustedContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      autoNotify: json['auto_notify'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'auto_notify': autoNotify,
      };
}

/// One position sample streamed to viewers of a shared trip.
class SharedTripLocation {
  final double lat;
  final double lng;
  final String rideStatus;
  final DateTime timestamp;

  const SharedTripLocation({
    required this.lat,
    required this.lng,
    required this.rideStatus,
    required this.timestamp,
  });

  factory SharedTripLocation.fromJson(Map<String, dynamic> json) {
    return SharedTripLocation(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      rideStatus: json['status'] as String? ?? 'unknown',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

// ============================================================================
// IMPLEMENTATION
// ============================================================================

class SafetyRepositoryImpl implements SafetyRepository {
  static const String emergencyNumber = String.fromEnvironment(
    'NIDUS_EMERGENCY_NUMBER',
    defaultValue: '911',
  );
  static const String _base = '/api/v1/nidus/safety';

  final ApiClient _apiClient;
  final WebSocketClient _webSocketClient;

  final Map<String, StreamController<SharedTripLocation>> _subscriptions = {};

  SafetyRepositoryImpl({
    required ApiClient apiClient,
    required WebSocketClient webSocketClient,
  })  : _apiClient = apiClient,
        _webSocketClient = webSocketClient;

  @override
  Future<SosResult> triggerSos({
    required String rideId,
    required double lat,
    required double lng,
    String? message,
  }) async {
    final emergencyUri = Uri(scheme: 'tel', path: emergencyNumber);
    try {
      final opened = await launchUrl(
        emergencyUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        return SosResult.failure(
          errorCode: 'EMERGENCY_DIALER_UNAVAILABLE',
          message: 'Could not open the phone dialer. Call $emergencyNumber directly now.',
        );
      }
      return const SosResult.dialerOpened();
    } catch (_) {
      return SosResult.failure(
        errorCode: 'EMERGENCY_DIALER_UNAVAILABLE',
        message: 'Could not open the phone dialer. Call $emergencyNumber directly now.',
      );
    }
  }

  @override
  Future<ShareLinkResult> createShareLink({
    required String rideId,
    required String label,
  }) async => const ShareLinkResult.failure(
        errorCode: 'SAFETY_UNAVAILABLE',
        message: 'Trip sharing is unavailable until secure link storage and expiry are operational.',
      );

  @override
  Future<List<SharedTripLink>> listActiveShareLinks(String rideId) async {
    throw const SafetyFailure('SAFETY_UNAVAILABLE', 'Trip sharing is unavailable.');
  }

  @override
  Future<bool> revokeShareLink(String linkId) async => false;

  @override
  Future<List<TrustedContact>> listTrustedContacts() async {
    throw const SafetyFailure('SAFETY_UNAVAILABLE', 'Trusted-contact management is unavailable.');
  }

  @override
  Future<TrustedContact> addTrustedContact({
    required String name,
    required String phone,
    bool autoNotify = true,
  }) async {
    throw const SafetyFailure('SAFETY_UNAVAILABLE', 'Trusted-contact management is unavailable.');
  }

  @override
  Future<bool> removeTrustedContact(String contactId) async => false;

  @override
  Future<bool> updateTrustedContact(
    String contactId, {
    String? name,
    String? phone,
    bool? autoNotify,
  }) async => false;

  // ==========================================================================
  // WEBSOCKET SUBSCRIPTIONS
  // ==========================================================================

  @override
  Stream<SharedTripLocation> subscribeToSharedTrip(String linkToken) =>
      Stream<SharedTripLocation>.error(
        const SafetyFailure('SAFETY_UNAVAILABLE', 'Trip sharing is unavailable.'),
      );

  @override
  void unsubscribeFromSharedTrip(String linkToken) {
    final controller = _subscriptions.remove(linkToken);
    if (controller != null) {
      controller.close();
      _webSocketClient.unsubscribe('shared_trip:$linkToken');
    }
  }

  Map<String, dynamic>? _decodeMessage(dynamic message) {
    if (message is Map<String, dynamic>) return _unwrap(message);
    if (message is String) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) return _unwrap(decoded);
      } catch (e) {
        debugPrint('Shared trip payload not valid JSON: $e');
      }
    }
    return null;
  }

  /// Unwraps the gateway's `{data: {...}}` envelope when present, returning
  /// the inner map; otherwise passes the map through unchanged.
  Map<String, dynamic>? _unwrap(Map<String, dynamic>? json) {
    if (json == null) return null;
    final data = json['data'];
    if (data is Map<String, dynamic>) return data;
    return json;
  }

  // ==========================================================================
  // CLEANUP
  // ==========================================================================

  void dispose() {
    for (final controller in _subscriptions.values) {
      controller.close();
    }
    _subscriptions.clear();
  }
}

/// Thrown by [SafetyRepositoryImpl.addTrustedContact] on unrecoverable errors.
class SafetyFailure implements Exception {
  final String code;
  final String message;

  const SafetyFailure(this.code, this.message);

  @override
  String toString() => 'SafetyFailure($code): $message';
}

// ============================================================================
// TEST / PREVIEW DOUBLE
// ============================================================================

/// No-op implementation used in widget tests and Flutter previews. It never
/// reports successful safety writes when no backend is configured.
class NoopSafetyRepository implements SafetyRepository {
  const NoopSafetyRepository();

  @override
  Future<SosResult> triggerSos({
    required String rideId,
    required double lat,
    required double lng,
    String? message,
  }) async {
    return const SosResult.failure(errorCode: 'SAFETY_UNAVAILABLE', message: 'Emergency delivery is not configured.');
  }

  @override
  Future<ShareLinkResult> createShareLink({
    required String rideId,
    required String label,
  }) async {
    return const ShareLinkResult.failure(errorCode: 'SAFETY_UNAVAILABLE', message: 'Secure trip sharing is not configured.');
  }

  @override
  Future<List<SharedTripLink>> listActiveShareLinks(String rideId) async =>
      const [];

  @override
  Future<bool> revokeShareLink(String linkId) async => false;

  @override
  Future<List<TrustedContact>> listTrustedContacts() async => const [];

  @override
  Future<TrustedContact> addTrustedContact({
    required String name,
    required String phone,
    bool autoNotify = true,
  }) async {
    throw const SafetyFailure('SAFETY_UNAVAILABLE', 'Trusted-contact storage is not configured.');
  }

  @override
  Future<bool> removeTrustedContact(String contactId) async => false;

  @override
  Future<bool> updateTrustedContact(
    String contactId, {
    String? name,
    String? phone,
    bool? autoNotify,
  }) async {
    return false;
  }

  @override
  Stream<SharedTripLocation> subscribeToSharedTrip(String linkToken) =>
      const Stream<SharedTripLocation>.empty();

  @override
  void unsubscribeFromSharedTrip(String linkToken) {}
}
