class RideOffer {
  final String id;
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double dropoffLat;
  final double dropoffLng;
  final String dropoffAddress;
  final double? fareAmount;
  final String currency;
  final String status;
  final String rideType;
  final DateTime requestedAt;

  const RideOffer({
    required this.id,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.dropoffAddress,
    required this.fareAmount,
    required this.currency,
    required this.status,
    required this.rideType,
    required this.requestedAt,
  });
}
