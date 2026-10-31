import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_client.dart';
import '../../domain/entities/active_ride.dart';

abstract class RideRepository {
  Future<ActiveRide> acceptRide(String rideId);
  Future<ActiveRide> startRide(String rideId);
  Future<ActiveRide> completeRide(String rideId, double tipAmount);
  Future<ActiveRide?> getActiveRide();
  Future<void> cancelRide(String rideId, String reason);
  Stream<ActiveRide> getRideUpdates();

  /// FARE INTEGRITY Phase 2 — READ-ONLY disclosure quote for one stop on this
  /// ride (fixed fee + waiting rule from the frozen booking contract). The
  /// driver can NEVER approve a charge: approval is rider-only by design so a
  /// driver cannot manufacture fees. This GET is write-free and safe to call;
  /// it throws when the caller is not a ride participant or no frozen
  /// contract exists (fail-closed server-side).
  Future<StopChargeQuoteView> quoteStop(String rideId, int seq);
}

/// Minimal read projection of the backend StopQuotePreviewResponse used by the
/// driver's "what will this stop cost" info sheet. Integer santim only.
class StopChargeQuoteView {
  final int seq;
  final int fixedFeeSantim;
  final int waitingChargeIfLongSantim;
  final int waitingThresholdMinutes;
  final String policyVersion;
  final String currency;

  const StopChargeQuoteView({
    required this.seq,
    required this.fixedFeeSantim,
    required this.waitingChargeIfLongSantim,
    required this.waitingThresholdMinutes,
    required this.policyVersion,
    required this.currency,
  });

  factory StopChargeQuoteView.fromJson(Map<String, dynamic> json) {
    int i(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return StopChargeQuoteView(
      seq: i(json['seq'], 0),
      fixedFeeSantim: i(json['fixed_fee_santim'], 0),
      waitingChargeIfLongSantim: i(json['waiting_charge_if_long_santim'], 0),
      waitingThresholdMinutes: i(json['waiting_threshold_minutes'], 10),
      policyVersion: json['policy_version'] as String? ?? '',
      currency: json['currency'] as String? ?? 'ETB',
    );
  }
}

class RideRepositoryImpl implements RideRepository {
  final ApiClient _apiClient;
  final WebSocketClient _webSocketClient;

  RideRepositoryImpl({
    required ApiClient apiClient,
    required WebSocketClient webSocketClient,
  })  : _apiClient = apiClient,
        _webSocketClient = webSocketClient;

  @override
  Future<ActiveRide> acceptRide(String rideId) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/nidus/rides/$rideId/accept',
      );
      final data = response.data as Map<String, dynamic>;
      _webSocketClient.subscribe('ride:$rideId');
      return ActiveRide.fromJson(data);
    } catch (e) {
      throw Exception('Failed to accept ride: ${e.toString()}');
    }
  }

  @override
  Future<ActiveRide> startRide(String rideId) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/nidus/rides/$rideId/start',
      );
      final data = response.data as Map<String, dynamic>;
      return ActiveRide.fromJson(data);
    } catch (e) {
      throw Exception('Failed to start ride: ${e.toString()}');
    }
  }

  @override
  Future<ActiveRide> completeRide(String rideId, double tipAmount) async {
    try {
      final response = await _apiClient.post(
        '/api/v1/nidus/rides/$rideId/complete',
        data: {'tip_amount': tipAmount},
      );
      final data = response.data as Map<String, dynamic>;
      return ActiveRide.fromJson(data);
    } catch (e) {
      throw Exception('Failed to complete ride: ${e.toString()}');
    }
  }

  @override
  Future<ActiveRide?> getActiveRide() async {
    try {
      final response = await _apiClient.get('/api/v1/nidus/drivers/active-ride');
      final data = response.data as Map<String, dynamic>;
      final ride = ActiveRide.fromJson(data);
      _webSocketClient.subscribe('ride:${ride.id}');
      return ride;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw Exception('Failed to get active ride: ${e.toString()}');
    } catch (e) {
      throw Exception('Failed to get active ride: ${e.toString()}');
    }
  }

  @override
  Future<void> cancelRide(String rideId, String reason) async {
    try {
      await _apiClient.post(
        '/api/v1/nidus/rides/$rideId/cancel',
        data: {'reason': reason, 'cancelled_by': 'driver'},
      );
    } catch (e) {
      throw Exception('Failed to cancel ride: ${e.toString()}');
    }
  }

  @override
  Stream<ActiveRide> getRideUpdates() {
    return _webSocketClient.messageStream
        .where((message) => message['type'] == 'ride_update')
        .asyncExpand((message) async* {
          final payload = message['payload'];
          if (payload is! Map<String, dynamic>) return;
          final inner = payload['data'];
          final data = inner is Map<String, dynamic> ? inner : payload;
          final rideId = (data['ride_id'] ?? data['id'])?.toString();
          if (rideId == null || rideId.isEmpty) return;
          try {
            final response = await _apiClient.get('/api/v1/nidus/rides/$rideId');
            final rideData = response.data as Map<String, dynamic>;
            yield ActiveRide.fromJson(rideData);
          } catch (_) {}
        });
  }

  @override
  Future<StopChargeQuoteView> quoteStop(String rideId, int seq) async {
    // Read-only disclosure GET — write-free by construction on the server.
    // No approve/timer calls exist on the driver side ON PURPOSE: only the
    // rider can trigger/approve stop charges (driver-manipulation defense).
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/v1/nidus/rides/$rideId/stops/$seq/quote',
      );
      final raw = response.data;
      if (raw == null) {
        throw const FormatException('Empty response from stop quote endpoint');
      }
      var data = raw;
      final inner = raw['data'];
      if (inner is Map<String, dynamic>) data = inner;
      return StopChargeQuoteView.fromJson(data);
    } catch (e) {
      throw Exception('Failed to quote stop: ${e.toString()}');
    }
  }
}