import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/restaurant.dart';

abstract class RestaurantRepository {
  Future<List<RestaurantSummary>> listRestaurants({int limit = 100});
  Future<List<MenuItem>> getMenu(String restaurantId);
  Future<Map<String, dynamic>> createOrder({required String restaurantId, required String deliveryAddress, required Map<String, int> quantities, double? deliveryLat, double? deliveryLng});
  Future<Map<String, dynamic>> trackOrder(String orderId);
  Future<List<Map<String, dynamic>>> listOrders({int limit = 20});
}

class RestaurantRepositoryImpl implements RestaurantRepository {
  final ApiClient apiClient;
  RestaurantRepositoryImpl({required this.apiClient});

  @override
  Future<List<RestaurantSummary>> listRestaurants({int limit = 100}) async {
    final response = await apiClient.get<Map<String, dynamic>>(AppConstants.restaurantsEndpoint, queryParameters: {'limit': limit});
    final items = response.data?['items'];
    if (items is! List) return const [];
    return items.whereType<Map<String, dynamic>>().map(RestaurantSummary.fromJson).toList(growable: false);
  }

  @override
  Future<List<MenuItem>> getMenu(String restaurantId) async {
    final response = await apiClient.get<Map<String, dynamic>>('${AppConstants.restaurantsEndpoint}/$restaurantId/menu');
    final items = response.data?['items'];
    if (items is! List) return const [];
    return items.whereType<Map<String, dynamic>>().map(MenuItem.fromJson).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> createOrder({required String restaurantId, required String deliveryAddress, required Map<String, int> quantities, double? deliveryLat, double? deliveryLng}) async {
    if (quantities.isEmpty) throw ArgumentError('At least one menu item is required');
    final response = await apiClient.post<Map<String, dynamic>>(
      AppConstants.ordersEndpoint,
      data: {
        'restaurant_id': restaurantId,
        'delivery_address': deliveryAddress,
        if (deliveryLat != null && deliveryLng != null) 'delivery_lat': deliveryLat,
        if (deliveryLat != null && deliveryLng != null) 'delivery_lng': deliveryLng,
        'items': quantities.entries.map((entry) => {'menu_item_id': entry.key, 'quantity': entry.value}).toList(growable: false),
      },
    );
    return response.data ?? const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> trackOrder(String orderId) async {
    final response = await apiClient.get<Map<String, dynamic>>('${AppConstants.ordersEndpoint}/$orderId/tracking');
    return response.data ?? const <String, dynamic>{};
  }

  @override
  Future<List<Map<String, dynamic>>> listOrders({int limit = 20}) async {
    final response = await apiClient.get<Map<String, dynamic>>(AppConstants.ordersEndpoint, queryParameters: {'limit': limit});
    final items = response.data?['items'];
    if (items is! List) return const [];
    return items.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}
