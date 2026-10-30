class HotelSummary {
  final String id;
  final String name;
  final String city;
  final int starRating;
  final double? pricePerNight;
  final String currency;
  final String? imageUrl;

  const HotelSummary({
    required this.id,
    required this.name,
    required this.city,
    required this.starRating,
    required this.pricePerNight,
    required this.currency,
    this.imageUrl,
  });

  factory HotelSummary.fromJson(Map<String, dynamic> json) {
    final images = json['images'];
    final imageUrl = images is List && images.isNotEmpty && images.first is String
        ? images.first as String
        : null;
    return HotelSummary(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Unnamed hotel',
      city: json['city'] as String? ?? '',
      starRating: (json['star_rating'] as num?)?.toInt() ?? 0,
      pricePerNight: (json['price_per_night'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'USD',
      imageUrl: imageUrl,
    );
  }
}

class HotelDetails {
  final HotelSummary summary;
  final String? description;
  final String? address;
  final List<String> amenities;
  final List<String> images;

  const HotelDetails({required this.summary, this.description, this.address, this.amenities = const [], this.images = const []});

  factory HotelDetails.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic value) => value is List ? value.whereType<String>().toList(growable: false) : const [];
    return HotelDetails(
      summary: HotelSummary.fromJson(json),
      description: json['description'] as String?,
      address: json['address'] as String?,
      amenities: strings(json['amenities']),
      images: strings(json['images']),
    );
  }
}
