import 'package:equatable/equatable.dart';

// ============================================================================
// FARE INTEGRITY Phase 2 — driver-side READ-ONLY stop-charge models.
//
// Design rule (abuse-prevention): the DRIVER can never create, approve or
// negotiate a stop charge. Stops are rider-triggered and fees are
// rider-approved only; these classes mirror the backend wire shapes
// (StopChargeInfo / StopQuotePreviewResponse) so the driver sees exactly the
// frozen contract the rider accepted — nothing is recomputed client-side.
// Money is integer santim (1/100 of the major unit); display formatting
// divides once, at render time.
// ============================================================================

/// santim → display string with exactly two decimals ("Br 10.00").
String formatSantim(int santim, {String currency = 'ETB'}) {
  final sign = santim < 0 ? '-' : '';
  final abs = santim < 0 ? -santim : santim;
  final whole = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  final symbol = currency == 'ETB' ? 'Br' : currency;
  return '$symbol $sign$whole.$frac';
}

/// Wire shape of a persisted ride_stop_charges row (backend StopChargeInfo).
/// All values are server-authoritative: dwell_minutes is SERVER-measured,
/// waiting_charge_santim is computed at timer close from the ORIGINAL frozen
/// booking fare (exact ½, non-compounding), and total_santim is what gets
/// added to the payable at completion.
class StopChargeState extends Equatable {
  final int seq;
  final bool approvedByRider;
  final DateTime? approvedAt;
  final int stopFeeSantim;
  final int waitingChargeSantim;
  final int totalSantim;
  final int dwellMinutes;
  final DateTime? timerStartedAt;
  final DateTime? timerEndedAt;
  final bool waitingEligible;
  final int waitingThresholdMinutes;
  final String policyVersion;
  final String currency;

  const StopChargeState({
    required this.seq,
    required this.approvedByRider,
    this.approvedAt,
    required this.stopFeeSantim,
    required this.waitingChargeSantim,
    required this.totalSantim,
    required this.dwellMinutes,
    this.timerStartedAt,
    this.timerEndedAt,
    required this.waitingEligible,
    required this.waitingThresholdMinutes,
    required this.policyVersion,
    required this.currency,
  });

  /// Honest "no fee approved" is represented by ABSENCE of a state object on
  /// the stop — never a zero-filled instance. This constructor exists only
  /// for explicit empty-list defaults in tests/callers that want one.
  static const StopChargeState none = StopChargeState(
    seq: 0,
    approvedByRider: false,
    stopFeeSantim: 0,
    waitingChargeSantim: 0,
    totalSantim: 0,
    dwellMinutes: 0,
    waitingEligible: false,
    waitingThresholdMinutes: 10,
    policyVersion: '',
    currency: 'ETB',
  );

  bool get timerRunning =>
      timerStartedAt != null &&
      timerEndedAt == null &&
      waitingChargeSantim == 0 &&
      dwellMinutes == 0;

  bool get timerClosed => timerEndedAt != null;

  factory StopChargeState.fromJson(Map<String, dynamic> json) {
    DateTime? d(Object? v) => v is String ? DateTime.tryParse(v) : null;
    int i(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return StopChargeState(
      seq: i(json['seq'], 0),
      approvedByRider: json['approved_by_rider'] == true,
      approvedAt: d(json['approved_at']),
      stopFeeSantim: i(json['stop_fee_santim'], 0),
      waitingChargeSantim: i(json['waiting_charge_santim'], 0),
      totalSantim: i(json['total_santim'], 0),
      dwellMinutes: i(json['dwell_minutes'], 0),
      timerStartedAt: d(json['timer_started_at']),
      timerEndedAt: d(json['timer_ended_at']),
      waitingEligible: json['waiting_eligible'] == true,
      waitingThresholdMinutes: i(json['waiting_threshold_minutes'], 10),
      policyVersion: json['policy_version'] as String? ?? '',
      currency: json['currency'] as String? ?? 'ETB',
    );
  }

  @override
  List<Object?> get props => [
        seq,
        approvedByRider,
        approvedAt,
        stopFeeSantim,
        waitingChargeSantim,
        totalSantim,
        dwellMinutes,
        timerStartedAt,
        timerEndedAt,
        waitingEligible,
        waitingThresholdMinutes,
        policyVersion,
        currency,
      ];
}

/// One intermediate stop (§3.5) plus its rider-approved charge projection.
/// [charge] is null when NO fee was approved for this stop — the UI must then
/// render "no fee approved", never assume zero. When present, every number is
/// the persisted, server-frozen amount.
class RideStopView extends Equatable {
  final int seq;
  final double lat;
  final double lng;
  final String address;
  final DateTime? arrivedAt;
  final StopChargeState? charge;

  const RideStopView({
    required this.seq,
    required this.lat,
    required this.lng,
    required this.address,
    this.arrivedAt,
    this.charge,
  });

  factory RideStopView.fromJson(Map<String, dynamic> json) => RideStopView(
        seq: json['seq'] is num ? (json['seq'] as num).toInt() : 0,
        lat: (json['lat'] as num?)?.toDouble() ?? 0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0,
        address: json['address'] as String? ?? '',
        arrivedAt: json['arrived_at'] is String
            ? DateTime.tryParse(json['arrived_at'] as String)
            : null,
        // Honest nullable read: absent/null key stays null ("no fee
        // approved"), never silently zero-filled.
        charge: json['charge'] is Map<String, dynamic>
            ? StopChargeState.fromJson(json['charge'] as Map<String, dynamic>)
            : null,
      );

  @override
  List<Object?> get props => [seq, lat, lng, address, arrivedAt, charge];
}
