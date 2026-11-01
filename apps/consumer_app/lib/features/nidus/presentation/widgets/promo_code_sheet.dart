import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/phase2_money_repository.dart';

/// §3.2 Promo Codes & Coupons — entry sheet on the Request page.
///
/// Two ways to attach a code: type one in (validated against
/// POST /promotions/redeem with the current estimated fare) or pick from
/// GET /promotions/mine. The projected discount returned by the server is
/// what [onApplied] receives; nothing is ever computed client-side, and a
/// failed validation shows the server's reason instead of silently keeping
/// a stale code (Global Rule: no fabricated numbers).
class PromoCodeSheet extends StatefulWidget {
  /// Current estimated fare used for the redeem projection. When null the
  /// "Apply" button stays disabled with an explanatory hint — projecting a
  /// discount against an unknown fare would be fabrication.
  final double? estimatedFare;
  final String currency;
  final String rideType;

  /// Currently attached code (if any), shown pre-filled so the rider can
  /// clear it.
  final String? currentCode;

  /// Called with the normalized code + server-projected discount when a
  /// validation succeeds, or with (null, null) when the rider clears the
  /// promo.
  final void Function(String? code, double? projectedDiscount) onApplied;

  const PromoCodeSheet({
    super.key,
    required this.estimatedFare,
    required this.currency,
    required this.rideType,
    required this.onApplied,
    this.currentCode,
  });

  static Future<void> show(
    BuildContext context, {
    required double? estimatedFare,
    required String currency,
    required String rideType,
    String? currentCode,
    required void Function(String? code, double? projectedDiscount) onApplied,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: PromoCodeSheet(
          estimatedFare: estimatedFare,
          currency: currency,
          rideType: rideType,
          currentCode: currentCode,
          onApplied: onApplied,
        ),
      ),
    );
  }

  @override
  State<PromoCodeSheet> createState() => _PromoCodeSheetState();
}

class _PromoCodeSheetState extends State<PromoCodeSheet> {
  final TextEditingController _controller = TextEditingController();
  final Phase2MoneyRepository _repo = getIt<Phase2MoneyRepository>();

  List<PromoCodeInfo>? _myCodes;
  bool _loadingMine = false;
  bool _validating = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    if (widget.currentCode != null) {
      _controller.text = widget.currentCode!;
    }
    _loadMine();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    setState(() => _loadingMine = true);
    final result = await _repo.listMyPromos();
    if (!mounted) return;
    setState(() {
      _loadingMine = false;
      // Honest empty/unavailable states are rendered below; we never show a
      // fake list when the endpoint failed.
      _myCodes = result.ok ? result.codes : null;
    });
  }

  Future<void> _validateAndApply(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      setState(() => _validationError = context.l10n.promoCodeEnterFirst);
      return;
    }
    final fare = widget.estimatedFare;
    if (fare == null) {
      setState(() => _validationError = context.l10n.promoCodeNeedRoute);
      return;
    }
    setState(() {
      _validating = true;
      _validationError = null;
    });
    final result = await _repo.redeemPromo(
      code: trimmed,
      fare: fare,
      currency: widget.currency,
      rideType: widget.rideType,
    );
    if (!mounted) return;
    setState(() => _validating = false);
    if (result.ok && result.projection != null) {
      widget.onApplied(result.projection!.code,
          result.projection!.projectedDiscount);
      Navigator.of(context).pop();
    } else {
      // A real server reason stays primary (honesty rule); the localized
      // copy is only the fallback for an absent/empty message.
      final serverMessage = result.message;
      setState(() => _validationError =
          (serverMessage != null && serverMessage.isNotEmpty)
              ? serverMessage
              : context.l10n.promoCodeInvalid);
    }
  }

  void _clear() {
    widget.onApplied(null, null);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.promoCodeTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if ((widget.currentCode ?? '').isNotEmpty)
                  TextButton(
                    onPressed: _validating ? null : _clear,
                    child: Text(l10n.promoCodeRemove),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              enabled: !_validating,
              decoration: InputDecoration(
                hintText: l10n.promoCodeHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.local_offer_outlined),
                errorText: _validationError,
              ),
              onSubmitted: _validateAndApply,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _validating
                    ? null
                    : () => _validateAndApply(_controller.text),
                icon: _validating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_validating
                    ? l10n.promoCodeChecking
                    : l10n.promoCodeValidateApply),
              ),
            ),
            if (widget.estimatedFare == null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.promoCodeNeedsFare,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              l10n.promoCodeYourCodes,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (_loadingMine)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                      color: AppColors.primary),
                ),
              )
            else if (_myCodes == null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.promoCodeLoadFailed,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadMine,
                    child: Text(l10n.promoCodeRetry),
                  ),
                ],
              )
            else if (_myCodes!.isEmpty)
              Text(
                l10n.promoCodeEmpty,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _myCodes!.length,
                  itemBuilder: (_, i) {
                    final c = _myCodes![i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.confirmation_number_outlined),
                      title: Text(c.code),
                      subtitle: Text(_describe(c, l10n)),
                      trailing: _validating
                          ? null
                          : TextButton(
                              onPressed: () => _validateAndApply(c.code),
                              child: Text(l10n.promoCodeUse),
                            ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Builds the condition line for one saved-code row. Every number comes
  /// verbatim from the server DTO (Global Rule: no fabricated values); only
  /// the surrounding words are localized.
  String _describe(PromoCodeInfo c, AppLocalizations l10n) {
    final parts = <String>[];
    if (c.type == 'percent') {
      parts.add(l10n.promoOffPercent(c.value.toStringAsFixed(0)));
      if (c.maxDiscount != null) {
        parts.add(l10n.promoMaxCap(
            widget.currency, c.maxDiscount!.toStringAsFixed(2)));
      }
    } else {
      parts.add(l10n.promoOffFixed(
          widget.currency, c.value.toStringAsFixed(2)));
    }
    if (c.minFare > 0) {
      parts.add(l10n.promoMinFare(
          widget.currency, c.minFare.toStringAsFixed(2)));
    }
    if (c.validTo != null) {
      parts.add(l10n.promoUntil(c.validTo!.toLocal().toString().split(' ').first));
    }
    return parts.join(' • ');
  }
}
