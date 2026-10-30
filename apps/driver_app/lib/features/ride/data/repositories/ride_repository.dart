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
}