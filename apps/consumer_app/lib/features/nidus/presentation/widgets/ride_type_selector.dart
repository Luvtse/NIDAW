import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/ride_repository.dart';

/// §2.6 Real ride-option carousel.
///
/// Every card is driven by a server-sourced [RideOptionEstimate] from the
/// pricing service — display name, price band, ETA, capacity, surge badge and
/// availability all come from `GET /rides/estimates`. The previous three
/// hardcoded cards and their fake "$12–15" strings are gone: when estimates
/// cannot be fetched this widget renders an honest retryable "Prices
/// unavailable" state instead of inventing numbers. Shared and Wheelchair
/// options now appear because the backend returns them.
class RideTypeSelector extends StatelessWidget {
  /// Estimates for the current pickup/dropoff pair. Empty list => the caller
  /// has not fetched yet; combine with [loading]/[error] for full states.
  final List<RideOptionEstimate> options;
  final String selectedType;
  final ValueChanged<String> onTypeSelected;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  const RideTypeSelector({
    super.key,
    required this.selectedType,
    required this.onTypeSelected,
    this.options = const [],
    this.loading = false,
    this.error,
    this.onRetry,
  });

  static const double _cardExtent = 164;

  @override
  Widget build(BuildContext context) {
    if (loading && options.isEmpty) {
      return const _CarouselSkeleton();
    }
    if (options.isEmpty) {
      return _UnavailableState(
        message: error != null
            ? 'Prices unavailable — pull to refresh or tap Retry.'
            : 'Prices unavailable — set pickup and dropoff to load live fares.',
        onRetry: onRetry,
      );
    }
    if (error != null) {
      // Stale-but-real data with an honest degradation notice: we keep the
      // last good server estimates rather than replacing them with fakes.
      // (The banner above the carousel is owned by the page.)
    }

    return SizedBox(
      height: _cardExtent + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final option = options[index];
          return _RideOptionCard(
            option: option,
            isSelected: option.rideType == selectedType && option.available,
            onTap: option.available
                ? () => onTypeSelected(option.rideType)
                : null,
          );
        },
      ),
    );
  }
}

/// One server-driven option card: icon, display name, price range, ETA,
/// capacity, and a surge badge (multiplier + reason) when surge > 1.
class _RideOptionCard extends StatelessWidget {
  final RideOptionEstimate option;
  final bool isSelected;
  final VoidCallback? onTap;

  const _RideOptionCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  static IconData iconFor(String? key) {
    switch (key) {
      case 'car':
        return Icons.directions_car;
      case 'star':
        return Icons.star;
      case 'electric_car':
        return Icons.electric_car;
      case 'groups':
        return Icons.groups;
      case 'accessible':
        return Icons.accessible;
      default:
        return Icons.directions_car;
    }
  }

  @override
  Widget build(BuildContext context) {
    final surging = option.surgeMultiplier > 1.0;
    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${option.displayName ?? option.rideType}, ${option.priceRangeLabel}'
          '${option.etaMinutes > 0 ? ', ${option.etaMinutes} min away' : ''}'
          '${surging ? ', surge ${option.surgeMultiplier.toStringAsFixed(1)}x' : ''}'
          '${option.available ? '' : ', unavailable'}',
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: option.available ? 1.0 : 0.45,
          child: Container(
            width: RideTypeSelector._cardExtent,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.nidusLilacWash : AppColors.nidusPaper,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppColors.nidusPurple : AppColors.nidusLine,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: AppColors.nidusPurple.withOpacity(.10),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.nidusLilac : AppColors.nidusWash,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        iconFor(option.iconKey),
                        color: isSelected ? AppColors.nidusInk : AppColors.nidusMuted,
                        size: 24,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.nidusPurple,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'CHOSEN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                    if (surging)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${option.surgeMultiplier.toStringAsFixed(1)}x',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  option.displayName ?? option.rideType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: -.2,
                    color: isSelected ? AppColors.nidusInk : AppColors.textPrimary,
                  ),
                ),
                Text(
                  option.priceRangeLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.nidusPurple,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  option.etaMinutes > 0
                      ? '${option.etaMinutes} min away'
                      : 'ETA unavailable',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  option.capacity == null
                      ? 'Capacity not provided'
                      : '${option.capacity} seat${(option.capacity ?? 0) == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (surging && option.surgeReason != null &&
                    option.surgeReason!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    option.surgeReason!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.warning,
                    ),
                  ),
                ],
                if (!option.available)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      'Unavailable',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading skeleton — real shimmer-free placeholders that convey structure,
/// not fabricated prices.
class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: RideTypeSelector._cardExtent + 8,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              width: RideTypeSelector._cardExtent,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Honest degraded state with retry — satisfies the global rule that an
/// unavailable dynamic value shows a real "unavailable" state, never a fake.
class _UnavailableState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _UnavailableState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.price_check_outlined,
              color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
