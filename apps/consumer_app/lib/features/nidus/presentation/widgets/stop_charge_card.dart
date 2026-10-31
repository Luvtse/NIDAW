import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/di/injection.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/ride_repository.dart';
import 'approve_stop_sheet.dart';

/// FARE INTEGRITY Phase 2 — per-stop charge status card shown on the rider
/// tracking sheet while a ride with stopovers is in progress.
///
/// State machine mirrors the backend exactly (server is always authoritative):
///   no charge        → "Approve stop fee" button opens the quote sheet.
///   approved, no     → driver/rider can start the server-clock dwell timer.
///   timer running    → live dwell display ticking LOCALLY from the server's
///                      started_at (display only!); the money decision happens
///                      server-side at close using its own clock. "Stop timer"
///                      closes the window and persists any waiting charge.
///   timer closed     → read-only summary of the frozen outcome: fixed fee +
///                      waiting charge (0 when under threshold) + total.
/// A null charge after refresh renders "No fee approved" honestly — never a
/// zero-filled ETB 0.00 that would imply a settled contract.
class StopChargeCard extends StatefulWidget {
  final String rideId;
  final RideStop stop;

  /// Invoked after any successful transition so the parent re-fetches the
  /// ride (GET /rides/{id} embeds the persisted charge projection).
  final VoidCallback onChanged;

  const StopChargeCard({
    super.key,
    required this.rideId,
    required this.stop,
    required this.onChanged,
  });

  @override
  State<StopChargeCard> createState() => _StopChargeCardState();
}

class _StopChargeCardState extends State<StopChargeCard> {
  final RideRepository _repository = getIt<RideRepository>();

  Timer? _ticker;
  int _elapsedSeconds = 0;
  bool _busy = false;
  String? _errorCopy;

  StopChargeState? get _charge => widget.stop.charge;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant StopChargeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync whenever the parent delivers a fresher persisted state.
    if (oldWidget.stop.charge?.timerStartedAt !=
            _charge?.timerStartedAt ||
        oldWidget.stop.charge?.timerEndedAt != _charge?.timerEndedAt) {
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Starts/stops the LOCAL display ticker off the SERVER's started_at. The
  /// displayed number is informational only — the billed dwell is computed
  /// from the server clock at timer close, so even a wrong local clock can
  /// never change money.
  void _syncTicker() {
    _ticker?.cancel();
    final c = _charge;
    if (c == null || !c.timerRunning || c.timerStartedAt == null) {
      setState(() => _elapsedSeconds = 0);
      return;
    }
    final started = c.timerStartedAt!.toLocal();
    setState(() {
      _elapsedSeconds = DateTime.now().difference(started).inSeconds.clamp(
            0,
            24 * 3600,
          );
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds += 1);
    });
  }

  Future<void> _runTransition(
      Future<StopChargeState> Function() call, String failurePrefix) async {
    setState(() {
      _busy = true;
      _errorCopy = null;
    });
    try {
      await call();
      if (!mounted) return;
      widget.onChanged(); // parent refetches the authoritative ride
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCopy = switch (e.errorCode) {
          'STOP_TIMER_ALREADY_STARTED' =>
            'The dwell timer was already started (by the other participant).',
          'STOP_TIMER_NOT_RUNNING' =>
            'The timer is not running — nothing to close.',
          'STOP_TIMER_CLOSED' =>
            'This dwell window is already finalized. It cannot be rewritten.',
          'STOP_NOT_APPROVED' =>
            'The rider has not approved a fee for this stop yet.',
          _ => '$failurePrefix (${e.errorCode}).',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorCopy = '$failurePrefix — network error.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dwellLabel() {
    final m = _elapsedSeconds ~/ 60;
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _charge;
    final currency = c?.currency ?? 'ETB';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.nidusLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                c == null
                    ? Icons.location_off_outlined
                    : c.timerClosed
                        ? Icons.check_circle_outline
                        : c.timerRunning
                            ? Icons.timer_outlined
                            : Icons.hourglass_empty,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stop ${widget.stop.seq}'
                  '${widget.stop.address != null && widget.stop.address!.isNotEmpty ? ' • ${widget.stop.address}' : ''}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ---- State copy ---------------------------------------------------
          if (c == null)
            const Text(
              'No fee approved for this stop yet. If you want the driver to '
              'wait here, approve the stop fee first.',
              style: TextStyle(fontSize: 12, height: 1.4),
            )
          else if (c.timerClosed) ...[
            _row('Stop fee', formatSantim(c.stopFeeSantim, currency: currency)),
            _row(
              'Waiting charge (${c.dwellMinutes} min dwell'
              '${c.waitingEligible ? ', \u2265 ${c.waitingThresholdMinutes} min' : ', under ${c.waitingThresholdMinutes} min'} )',
              formatSantim(c.waitingChargeSantim, currency: currency),
            ),
            const Divider(height: 16),
            _row('Added by this stop',
                formatSantim(c.totalSantim, currency: currency),
                bold: true),
          ] else if (c.timerRunning) ...[
            Row(
              children: [
                Text('Dwell $_dwellLabel()',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '(display only — billed from the server clock)',
                    style: TextStyle(
                        fontSize: 10.5, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            _row('Approved stop fee',
                formatSantim(c.stopFeeSantim, currency: currency)),
            if (c.waitingEligible)
              _row(
                  'Waiting if \u2265 ${c.waitingThresholdMinutes} min',
                  formatSantim(c.waitingChargeSantim, currency: currency)),
          ] else ...[
            _row('Approved stop fee',
                formatSantim(c.stopFeeSantim, currency: currency)),
            if (c.waitingEligible)
              _row(
                  'Waiting if \u2265 ${c.waitingThresholdMinutes} min',
                  formatSantim(c.waitingChargeSantim, currency: currency)),
            const Text(
              'Waiting charge starts accruing only once the dwell timer is '
              'closed past the threshold.',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary, height: 1.4),
            ),
          ],

          if (_errorCopy != null) ...[
            const SizedBox(height: 6),
            Text(_errorCopy!,
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.error)),
          ],

          // ---- Actions --------------------------------------------------------
          const SizedBox(height: 8),
          if (c == null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => ApproveStopSheet.show(
                          context,
                          rideId: widget.rideId,
                          seq: widget.stop.seq,
                          stopAddress: widget.stop.address,
                          onApproved: (_) => widget.onChanged(),
                        ),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text('Approve stop fee'),
              ),
            )
          else if (c.approvedByRider && !c.timerRunning && !c.timerClosed)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _runTransition(
                          () => _repository.startStopTimer(
                              widget.rideId, widget.stop.seq),
                          'Could not start the dwell timer',
                        ),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Start wait timer'),
              ),
            )
          else if (c.timerRunning)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _runTransition(
                          () => _repository.stopStopTimer(
                              widget.rideId, widget.stop.seq),
                          'Could not close the dwell timer',
                        ),
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: Text(_busy
                    ? 'Finalizing…'
                    : 'End wait & settle'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }
}
