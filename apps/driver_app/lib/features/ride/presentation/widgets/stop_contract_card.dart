import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/active_ride.dart';
import '../../domain/entities/stop_charge.dart';

/// FARE INTEGRITY Phase 2 — driver-side READ-ONLY stop-contract view.
///
/// Deliberately contains NO buttons that mutate money: stops are triggered by
/// the rider and fees are approved by the rider only (a driver pressing a
/// "stop" button could manufacture dwell time and inflate earnings — so the
/// driver surface exposes observation, never control). At completion the
/// backend looks up the persisted rider-approved charges and adds them to the
/// payable; if nothing was approved, the original frozen booking fare is what
/// is payable. This card mirrors exactly that truth.
class StopContractCard extends StatelessWidget {
  final ActiveRide ride;

  const StopContractCard({super.key, required this.ride});

  @override
  Widget build(BuildContext context) {
    // No stops on the trip → render nothing at all (the payable is simply the
    // booked fare; an empty card would be noise).
    if (ride.stops.isEmpty) return const SizedBox.shrink();

    final extraSantim = ride.approvedStopChargesSantim;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.nidusLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 16),
              const SizedBox(width: 6),
              Text(
                'Stops on this trip',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              // Honest summary chip: what completion WILL add, computed by
              // summing persisted server amounts (never client-side fee math).
              Text(
                extraSantim > 0
                    ? '+${formatSantim(extraSantim, currency: _currency)}'
                    : 'No fees approved',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: extraSantim > 0 ? Colors.black87 : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...ride.stops.map((s) => _StopRow(stop: s, currency: _currency)),
          const SizedBox(height: 6),
          Text(
            'Stop fees are set by the rider\'s approval. You cannot change '
            'them; they are added automatically when the ride completes.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }

  String get _currency {
    for (final s in ride.stops) {
      if (s.charge != null && s.charge!.currency.isNotEmpty) {
        return s.charge!.currency;
      }
    }
    return 'ETB';
  }
}

class _StopRow extends StatelessWidget {
  final RideStopView stop;
  final String currency;

  const _StopRow({required this.stop, required this.currency});

  @override
  Widget build(BuildContext context) {
    final charge = stop.charge;
    final String stateLine;
    final Color stateColor;
    if (charge == null) {
      // Absent charge object = honest "no fee approved", never zero-filled.
      stateLine = 'No fee approved';
      stateColor = Colors.grey;
    } else if (charge.timerRunning) {
      stateLine = 'Waiting timer running (rider-controlled)';
      stateColor = Colors.blueGrey;
    } else if (charge.waitingChargeSantim > 0) {
      stateLine =
          'Dwell ${charge.dwellMinutes} min · waiting +${formatSantim(charge.waitingChargeSantim, currency: currency)}';
      stateColor = Colors.black87;
    } else if (charge.timerClosed) {
      stateLine = 'Dwell ${charge.dwellMinutes} min · under '
          '${charge.waitingThresholdMinutes} min, no waiting charge';
      stateColor = Colors.grey.shade700;
    } else {
      stateLine = 'Approved by rider · timer not started';
      stateColor = Colors.grey.shade700;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: AppColors.nidusLine,
            child: Text('${stop.seq}',
                style: const TextStyle(fontSize: 11, height: 1)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.address.isNotEmpty ? stop.address : 'Stop ${stop.seq}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                Text(stateLine,
                    style: TextStyle(fontSize: 11, color: stateColor)),
              ],
            ),
          ),
          if (charge != null)
            Text(
              formatSantim(charge.totalSantim, currency: currency),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}
