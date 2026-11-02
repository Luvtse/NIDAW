import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';

/// Derives up-to-two-word initials from a display name ("Abebe Kebede" ->
/// "AK"). Used by [DriverCard]'s honest avatar degradation: when no real
/// driver photo exists we show the rider-visible initials plus an explicit
/// semantic label, never a generic person silhouette that could be mistaken
/// for an actual photo (verify_driver_card.dart §2.3 honesty rule).
String driverAvatarInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final initials = words.take(2).map((w) => w.characters.first.toUpperCase());
  return initials.isEmpty ? '?' : initials.join('');
}

class DriverCard extends StatelessWidget {
  final String driverName;
  final double rating;
  final String carModel;
  final String plateNumber;
  final int eta;
  final VoidCallback? onCall;
  final VoidCallback? onChat;

  const DriverCard({
    super.key,
    required this.driverName,
    required this.rating,
    required this.carModel,
    required this.plateNumber,
    required this.eta,
    this.onCall,
    this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Driver Avatar — Phase 4 honest degradation. The backend does not
          // deliver a driver photo to this card, so a generic Icons.person
          // silhouette here was faking identity (and sat next to the real
          // selfie in VerifyDriverCard). We now render the driver's initials
          // with an explicit semantic label stating that no photo is
          // available — the same rule verify_driver_card.dart:28 applies to
          // a missing profile photo.
          Semantics(
            label: l10n.driverAvatarInitialsLabel(driverName),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                driverAvatarInitials(driverName),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Driver Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driverName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      rating.toString(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      carModel,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  plateNumber,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          
          Column(
            children: [
              // Phase 4 accessibility: IconButton tooltips already name the
              // action for hover/long-press; the wrapping Semantics gives
              // screen-reader users an explicit button role and excludes the
              // decorative glyph from a separate announcement.
              Semantics(
                button: true,
                label: l10n.driverCallTooltip,
                excludeSemantics: true,
                child: IconButton(
                  tooltip: l10n.driverCallTooltip,
                  onPressed: onCall,
                  icon: const Icon(Icons.call),
                ),
              ),
              Semantics(
                button: true,
                label: l10n.driverChatTooltip,
                excludeSemantics: true,
                child: IconButton(
                  tooltip: l10n.driverChatTooltip,
                  onPressed: onChat,
                  icon: const Icon(Icons.message_outlined),
                ),
              ),
            ],
          ),
          // ETA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  '$eta',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    // §4.4: token for intentional white-on-dark foreground.
                    color: AppColors.textOnDark,
                  ),
                ),
                Text(
                  l10n.driverEtaMinutesUnit,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}