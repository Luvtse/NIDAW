class RestaurantSummary {
  final String id;
  final String name;
  final String cuisineType;
  final double rating;
  final double deliveryFee;
  final int estimatedDeliveryMinutes;
  final String? imageUrl;
  final double? distanceKm;

  const RestaurantSummary({required this.id, required this.name, required this.cuisineType, required this.rating, required this.deliveryFee, required this.estimatedDeliveryMinutes, this.imageUrl, this.distanceKm});

  factory RestaurantSummary.fromJson(Map<String, dynamic> json) {
    final images = json['images'];
    final imageUrl = images is List && images.isNotEmpty && images.first is String ? images.first as String : null;
    return RestaurantSummary(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unnamed restaurant',
      cuisineType: json['cuisine_type'] as String? ?? 'Other',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0,
      estimatedDeliveryMinutes: (json['estimated_delivery_minutes'] as num?)?.toInt() ?? 30,
      imageUrl: imageUrl,
    );
  }
}

class MenuItem {
  final String id;
  final String restaurantId;
  final String name;
  final String? description;
  final double price;
  final String currency;
  final String? category;
  final String? imageUrl;
  final bool isAvailable;

  const MenuItem({required this.id, required this.restaurantId, required this.name, this.description, required this.price, required this.currency, this.category, this.imageUrl, required this.isAvailable});

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    id: json['id']?.toString() ?? '',
    restaurantId: json['restaurant_id']?.toString() ?? '',
    name: json['name'] as String? ?? 'Menu item',
    description: json['description'] as String?,
    price: (json['price'] as num?)?.toDouble() ?? 0,
    // Phase 4 (ETB-only standardization): NIDAW has no multi-currency
    // runtime. Missing/legacy tags normalize to ETB; historical amounts
    // are rendered by core/utils/formatters which maps legacy 'USD'
    // labels to Br without implying a live dollar price.
    currency: json['currency'] as String? ?? 'ETB',
    category: json['category'] as String?,
    imageUrl: json['image_url'] as String?,
    isAvailable: json['is_available'] as bool? ?? false,
  );
}
