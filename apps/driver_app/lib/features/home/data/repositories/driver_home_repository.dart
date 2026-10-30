import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_client.dart';
import '../../domain/entities/driver_stats.dart';

abstract class DriverHomeRepository {
  Future<DriverStats> getDriverStats();
  Future<void> toggleAvailability(bool isOnline);
  Future<void> updateLocation(double lat, double lng, double heading, double speed);
  Stream<Map<String, dynamic>> getRideRequests();
}

class DriverHomeRepositoryImpl implements DriverHomeRepository {
  final ApiClient _apiClient;
  final WebSocketClient _webSocketClient;

  DriverHomeRepositoryImpl({
    required ApiClient apiClient,
    required WebSocketClient webSocketClient,
  })  : _apiClient = apiClient,
        _webSocketClient = webSocketClient;

  @override
  Future<DriverStats> getDriverStats() async {
    try {
      final response = await _apiClient.get('/api/v1/nidus/drivers/stats');
      final data = response.data as Map<String, dynamic>;
      return DriverStats.fromJson(data);
    } catch (e) {
      throw Exception('Failed to get driver stats: ${e.toString()}');
    }
  }

  @override
  Future<void> toggleAvailability(bool isOnline) async {
    try {
      if (isOnline) {
        await _apiClient.post('/api/v1/nidus/drivers/online');
      } else {
        await _apiClient.post('/api/v1/nidus/drivers/offline');
      }
    } catch (e) {
      throw Exception('Failed to toggle availability: ${e.toString()}');
    }
  }

  @override
  Future<void> updateLocation(
    double lat,
    double lng,
    double heading,
    double speed,
  ) async {
    try {
      await _apiClient.post(
        '/api/v1/nidus/location/update',
        data: {
          'lat': lat,
          'lng': lng,
          'heading': heading,
          'speed': speed * 3.6,
        },
      );
    } catch (e) {
      throw Exception('Failed to update location: ${e.toString()}');
    }
  }

  @override
  Stream<Map<String, dynamic>> getRideRequests() {
    _webSocketClient.subscribe('driver:offers');
    return _webSocketClient.messageStream.where((message) {
      final payload = message['payload'];
      return message['type'] == 'notification_inbox' &&
          payload is Map<String, dynamic> &&
          payload['topic'] == 'driver:offers' &&
          payload['ride_id'] is String;
    }).map((message) => Map<String, dynamic>.from(message['payload'] as Map));
  }
}