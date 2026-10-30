import 'package:equatable/equatable.dart';

import 'stop_charge.dart';

class ActiveRide extends Equatable {
  final String id;
  final String riderId;
  final String riderName;
  final String riderPhone;
  final double riderRating;
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double dropoffLat;
  final double dropoffLng;
  final String dropoffAddress;
  final double distanceKm;
  final int estimatedDurationMinutes;
  final double fareAmount;
  final String currency;
  final double tipAmount;
  final String status;
  final DateTime requestedAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? riderNote;
  /// FARE INTEGRITY Phase 2: intermediate stops with their rider-approved
  /// charge projections, embedded by the backend on GET /rides/{id}. READ-ONLY
  /// for the driver — approval is rider-only by design (drivers cannot press
  /// any stop button; a manipulated client POST hits 403 STOP_NOT_APPROVABLE).
  /// Empty list means "no stops on this ride", never an unknown state.
  final List<RideStopView> stops;

  const ActiveRide({
    required this.id,
    required this.riderId,
    required this.riderName,
    required this.riderPhone,
    required this.riderRating,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.estimatedDurationMinutes,
    required this.fareAmount,
    this.currency = '',
    required this.tipAmount,
    required this.status,
    required this.requestedAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.riderNote,
    this.stops = const [],
  });

  factory ActiveRide.fromJson(Map<String, dynamic> json) {
    return ActiveRide(
      id: json['id'] as String,
      riderId: (json['rider_id'] ?? json['user_id'] ?? '') as String,
      riderName: json['rider_name'] as String? ?? '',
      riderPhone: json['rider_phone'] as String? ?? '',
      riderRating: (json['rider_rating'] as num?)?.toDouble() ?? 0,
      pickupLat: (json['pickup_lat'] as num).toDouble(),
      pickupLng: (json['pickup_lng'] as num).toDouble(),
      pickupAddress: json['pickup_address'] as String? ?? '',
      dropoffLat: (json['dropoff_lat'] as num).toDouble(),
      dropoffLng: (json['dropoff_lng'] as num).toDouble(),
      dropoffAddress: json['dropoff_address'] as String? ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      estimatedDurationMinutes: (json['estimated_duration_minutes'] as num?)?.toInt() ?? (json['duration_minutes'] as num?)?.toInt() ?? 0,
      fareAmount: (json['fare_amount'] as num?)?.toDouble() ?? (json['estimated_fare'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? '',
      tipAmount: (json['tip_amount'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String,
      requestedAt: DateTime.parse(json['requested_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      riderNote: json['rider_note'] as String?,
      stops: (json['stops'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(RideStopView.fromJson)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rider_id': riderId,
      'rider_name': riderName,
      'rider_phone': riderPhone,
      'rider_rating': riderRating,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'pickup_address': pickupAddress,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      'dropoff_address': dropoffAddress,
      'distance_km': distanceKm,
      'estimated_duration_minutes': estimatedDurationMinutes,
      'fare_amount': fareAmount,
      'currency': currency,
      'tip_amount': tipAmount,
      'status': status,
      'requested_at': requestedAt.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
      'started_at': startedAt?.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'rider_note': riderNote,
      'stops': stops
          .map((s) => {
                'seq': s.seq,
                'lat': s.lat,
                'lng': s.lng,
                'address': s.address,
                'arrived_at': s.arrivedAt?.toIso8601String(),
                'charge': s.charge == null
                    ? null
                    : {
                        'seq': s.charge!.seq,
                        'approved_by_rider': s.charge!.approvedByRider,
                        'approved_at': s.charge!.approvedAt?.toIso8601String(),
                        'stop_fee_santim': s.charge!.stopFeeSantim,
                        'waiting_charge_santim': s.charge!.waitingChargeSantim,
                        'total_santim': s.charge!.totalSantim,
                        'dwell_minutes': s.charge!.dwellMinutes,
                        'timer_started_at':
                            s.charge!.timerStartedAt?.toIso8601String(),
                        'timer_ended_at':
                            s.charge!.timerEndedAt?.toIso8601String(),
                        'waiting_eligible': s.charge!.waitingEligible,
                        'waiting_threshold_minutes':
                            s.charge!.waitingThresholdMinutes,
                        'policy_version': s.charge!.policyVersion,
                        'currency': s.charge!.currency,
                      },
              })
          .toList(),
    };
  }

  ActiveRide copyWith({
    String? status,
    DateTime? acceptedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    List<RideStopView>? stops,
  }) {
    return ActiveRide(
      id: id,
      riderId: riderId,
      riderName: riderName,
      riderPhone: riderPhone,
      riderRating: riderRating,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      pickupAddress: pickupAddress,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      dropoffAddress: dropoffAddress,
      distanceKm: distanceKm,
      estimatedDurationMinutes: estimatedDurationMinutes,
      fareAmount: fareAmount,
      currency: currency,
      tipAmount: tipAmount,
      status: status ?? this.status,
      requestedAt: requestedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      riderNote: riderNote,
      stops: stops ?? this.stops,
    );
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';

  /// FARE INTEGRITY Phase 2 (READ-ONLY view for the driver): total of all
  /// rider-approved stop charges in santim. Computed by SUMMING persisted
  /// server amounts — no client-side fee math. Zero when there are no stops
  /// or no approved fees, which is exactly what completion will add.
  int get approvedStopChargesSantim =>
      stops.fold(0, (sum, s) => sum + (s.charge?.totalSantim ?? 0));

  double get totalEarnings => fareAmount + tipAmount;

  @override
  List<Object?> get props => [
        id,
        riderId,
        status,
        pickupLat,
        pickupLng,
        dropoffLat,
        dropoffLng,
        fareAmount,
        stops,
      ];
}