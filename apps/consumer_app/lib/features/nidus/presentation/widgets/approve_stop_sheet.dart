import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/ride_repository.dart';

/// FARE INTEGRITY Phase 2 — rider stop-approval sheet.
///
/// The amounts shown here are the server's own numbers, fetched from
/// GET /rides/{id}/stops/{seq}/quote (the SAME pure stops-v1 policy the
/// settlement finalizer uses) and rendered VERBATIM: fixed stop fee plus the
/// waiting charge that applies once dwell ≥ threshold, where the waiting
/// charge is exactly ½ of the ORIGINAL frozen booking fare — never compounding.
///
/// Integrity rules this widget upholds:
/// - No client-side fee math anywhere. If the quote fetch fails we say so and
///   offer retry; we NEVER fall back to a hardcoded "Br 10.00".
/// - The approve POST body carries no amount field at all — the backend
///   re-freezes the fee from config, so a tampered client cannot negotiate it.
/// - Exactly-once approval: a second attempt surfaces STOP_ALREADY_APPROVED
///   (409) and the sheet switches to the persisted state instead of charging.
class ApproveStopSheet extends StatefulWidget {
  final String rideId;
  final int seq;
  final String? stopAddress;

  /// Called after a successful approval with the persisted charge echo, so
  /// the tracking page can refresh its stop list from the server truth.
  final void Function(StopChargeState approved)? onApproved;

  const ApproveStopSheet({
    super.key,
    required this.rideId,
    required this.seq,
    this.stopAddress,
    this.onApproved,
  });

  static Future<void> show(
    BuildContext context, {
    required String rideId,
    required int seq,
    String? stopAddress,
    void Function(StopChargeState approved)? onApproved,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ApproveStopSheet(
        rideId: rideId,
        seq: seq,
        stopAddress: stopAddress,
        onApproved: onApproved,
      ),
    );
  }

  @override
  State<ApproveStopSheet> createState() => _ApproveStopSheetState();
}

enum _QuoteStatus { loading, ready, failed }

class _ApproveStopSheetState extends State<ApproveStopSheet> {
  final RideRepository _repository = getIt<RideRepository>();

  _QuoteStatus _status = _QuoteStatus.loading;
  StopChargeQuote? _quote;
  String? _failureCopy;

  bool _approving = false;

  @override
  void initState() {
    super.initState();
    _fetchQuote();
  }

  Future<void> _fetchQuote() async {
    setState(() {
      _status = _QuoteStatus.loading;
      _failureCopy = null;
    });
    try {
      final quote = await _repository.quoteStop(widget.rideId, widget.seq);
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _status = _QuoteStatus.ready;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // Honest, code-specific degradation. NO_BOOKING_CONTRACT means there is
      // no frozen fare to anchor the ½ waiting charge against — approving now
      // would be quoting on air, so we refuse rather than guess.
      setState(() {
        _status = _QuoteStatus.failed;
        _failureCopy = switch (e.errorCode) {
          'NO_BOOKING_CONTRACT' =>
            'This ride has no frozen fare contract yet, so the stop fee '
                'cannot be quoted. Try again shortly.',
          'STOP_CHARGES_UNAVAILABLE' =>
            'Stop fees are temporarily unavailable. Nothing was charged.',
          'STOP_SEQ_OUT_OF_RANGE' =>
            'This stop is not part of the ride any more. Refresh the trip.',
          _ => 'Could not load the stop fee. Nothing was charged — retry.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _QuoteStatus.failed;
        _failureCopy =
            'Could not load the stop fee. Nothing was charged — retry.';
      });
    }
  }

  Future<void> _approve() async {
    setState(() => _approving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final charge =
          await _repository.approveStop(widget.rideId, widget.seq);
      if (!mounted) return;
      widget.onApproved?.call(charge);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Stop ${charge.seq} approved — '
          '${formatSantim(charge.stopFeeSantim, currency: _symbol)} stop fee'
          '${charge.waitingEligible ? ' + waiting if \u2265 ${charge.waitingThresholdMinutes} min' : ''}.',
        ),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.errorCode == 'STOP_ALREADY_APPROVED') {
        // Idempotency surfaced honestly: close the sheet, the caller's
        // refresh will render the persisted approval.
        Navigator.of(context).pop();
        messenger.showSnackBar(const SnackBar(
          content: Text('This stop was already approved — you were not '
              'charged twice.'),
        ));
        return;
      }
      setState(() => _approving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(e.errorCode == 'FORBIDDEN'
            ? 'Only the rider who booked this ride can approve stop fees.'
            : 'Approval failed (${e.errorCode ?? 'ERROR'}). Nothing changed.'),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _approving = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('Approval failed — network error. Nothing changed.'),
      ));
    }
  }

  String get _symbol =>
      stopCurrencySymbol(_quote?.currency ?? widgetCurrencyFallback);

  /// Currency for display when the quote hasn't loaded yet. ETB is the only
  /// market the stops-v1 policy ships against; the authoritative symbol still
  /// comes from the quote itself once loaded.
  String get widgetCurrencyFallback => 'ETB';

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.stopAddress != null &&
                          widget.stopAddress!.isNotEmpty
                      ? 'Stop at ${widget.stopAddress}'
                      : 'Stop ${widget.seq}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Approving adds these charges to your fare. The waiting charge '
            'applies only if the stop lasts long enough, and is always half '
            'of your original booking fare — it never compounds.',
            style: TextStyle(fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 16),

          // ---- Quote states -----------------------------------------------
          if (_status == _QuoteStatus.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(strokeWidth: 2.5),
                    SizedBox(height: 12),
                    Text('Loading the exact fee from the server…',
                        style: TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            )
          else if (_status == _QuoteStatus.failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _failureCopy ?? 'The fee could not be loaded.',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.error),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _fetchQuote,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (q != null) ...[
            _FeeRow(
              label: 'Fixed stop fee',
              value: formatSantim(q.fixedFeeSantim, currency: q.currency),
            ),
            _FeeRow(
              label:
                  'Waiting charge if the stop lasts \u2265 ${q.waitingThresholdMinutes} min',
              value:
                  formatSantim(q.waitingChargeIfLongSantim, currency: q.currency),
              hint: 'Exactly ½ of your original booking fare (server-frozen)',
            ),
            const Divider(height: 24),
            _FeeRow(
              label: 'Maximum added by this stop',
              value: formatSantim(
                  q.fixedFeeSantim + q.waitingChargeIfLongSantim,
                  currency: q.currency),
              emphasize: true,
            ),
            const SizedBox(height: 6),
            // Verbatim disclosure line — same words the plan mandates:
            // "Br 10.00 stop fee; stops ≥ 10 min add Br {½·F0} waiting".
            Text(
              q.disclosureLine,
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _approving ? null : _approve,
                icon: _approving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_approving
                    ? 'Approving…'
                    : 'Approve stop fee'),
              ),
            ),
          ],

          const SizedBox(height: 10),
          Center(
            child: Text(
              'Policy ${q?.policyVersion ?? 'stops-v1'} • amounts frozen '
              'server-side; this screen never edits them',
              style: const TextStyle(
                  fontSize: 10.5, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final bool emphasize;

  const _FeeRow({
    required this.label,
    required this.value,
    this.hint,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: emphasize ? 14 : 13,
                    fontWeight: emphasize ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: emphasize ? 15 : 13.5,
                  fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
          if (hint != null)
            Text(
              hint!,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
