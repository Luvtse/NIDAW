import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/location/device_location_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../data/repositories/safety_repository.dart';
import '../bloc/ride_bloc.dart';
import '../widgets/safety_widgets.dart';

/// Safety Toolkit hub — the shield-icon entry point regulators expect on
/// every active trip. All actions operate on the live [RideBloc] so the
/// toolkit works from any tracking surface without prop drilling.
class SafetyToolkitPage extends StatelessWidget {
  static const String _emergencyNumber = String.fromEnvironment(
    'NIDUS_EMERGENCY_NUMBER',
    defaultValue: '911',
  );

  const SafetyToolkitPage({super.key});

  /// Presents the toolkit as a full-screen route pushed above tracking.
  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const SafetyToolkitPage(),
      ),
    );
  }

  static void _requireActiveRide(BuildContext context) {
    final bloc = context.read<RideBloc>();
    final state = bloc.state;
    if (state is DriverMatched ||
        state is DriverEnRoute ||
        state is RideInProgress ||
        state is RideRequested) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Start a ride to use safety features.'),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  static String? _activeRideId(BuildContext context) {
    final state = context.read<RideBloc>().state;
    if (state is RideRequested) return state.rideId;
    if (state is DriverMatched) return state.rideId;
    if (state is DriverEnRoute) return state.rideId;
    if (state is RideInProgress) return state.ride.id;
    return null;
  }

  /// Returns a real location only when the ride state provides one. Safety
  /// actions must not manufacture coordinates when a current fix is missing.
  static List<double>? _liveLocation(BuildContext context) {
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Safety'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      backgroundColor: const Color(0xFFF7F4FC),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF30204F), Color(0xFF7658D6)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(children: [
              Icon(Icons.shield_moon_rounded, color: Color(0xFFDCD2FF), size: 34),
              SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('You’re in control', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text('Safety tools for your ride, all in one place.', style: TextStyle(color: Color(0xFFE8E1F2), fontSize: 12, height: 1.4)),
              ])),
            ]),
          ),
          _SafetyActionTile(
            icon: Icons.sos,
            iconColor: AppColors.error,
            title: l10n.sosTitle,
            subtitle: l10n.sosTileSubtitle(_emergencyNumber),
            enabled: true,
            onTap: () async {
              final rideId = _activeRideId(context);
              if (rideId == null) {
                _requireActiveRide(context);
                return;
              }
              final bloc = context.read<RideBloc>();
              // Phase 1 fix: route the toolkit SOS through the SAME tested
              // countdown flow RideCheck already uses (StartSosCountdown →
              // SosCountdownOverlay). Previously this tile only opened the
              // dialer directly, leaving SosSlideToConfirm/SosCountdownOverlay
              // orphaned and giving two safety surfaces divergent behavior.
              // The overlay keeps the rider in control: cancel ("I'm safe")
              // or escalate immediately; the phone still confirms the call.
              //
              // Phase 1 addendum: the confirm step now mounts
              // SosSlideToConfirm (the accessible slide/keyboard/AT-action
              // trigger) instead of arming the countdown on tap — pocket-
              // dials must not fire a real SOS. And we read the rider's REAL
              // position first (was lat/lng = 0,0 placeholder, which would
              // dispatch a Gulf-of-Guinea "emergency location"). Honest
              // degradation: no fix → no fake SOS, same rule as RideCheck.
              if (!context.mounted) return;
              final confirmed = await showGeneralDialog<bool>(
                context: context,
                barrierDismissible: true,
                barrierLabel: l10n.sosOverlayA11y,
                pageBuilder: (_, __, ___) => Material(
                  color: Colors.black.withOpacity(0.85),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            l10n.sosTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textOnDark,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.sosTileSubtitle(_emergencyNumber),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 24),
                          SosSlideToConfirm(
                            onConfirmed: () =>
                                Navigator.of(context).pop(true),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              if (confirmed != true) return;

              const locationService = DeviceLocationService();
              final result = await locationService.getCurrentPosition();
              if (!context.mounted) return;
              if (result is LocationGranted) {
                bloc.add(StartSosCountdown(
                  rideId: rideId,
                  lat: result.latitude,
                  lng: result.longitude,
                  message: 'Emergency SOS from Safety Toolkit.',
                ));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.sosLocationUnavailable)),
                );
                return;
              }
              if (!context.mounted) return;
              await showGeneralDialog<void>(
                context: context,
                barrierDismissible: false,
                barrierLabel: l10n.sosOverlayA11y,
                pageBuilder: (_, __, ___) => const SosCountdownOverlay(),
              );
            },
          ),
          _SafetyActionTile(
            icon: Icons.share_location,
            iconColor: AppColors.primary,
            title: 'Share My Trip',
            subtitle: 'Create a private live-tracking link to share with someone you trust.',
            enabled: true,
            onTap: () {
              final rideId = _activeRideId(context);
              if (rideId == null) {
                _requireActiveRide(context);
                return;
              }
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                // §4.4: theme token (was hardcoded Colors.white).
                backgroundColor: AppColors.surface,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (sheetContext) => Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                  ),
                  child: RepositoryProvider<SafetyRepository>(
                    create: (_) => getIt<SafetyRepository>(),
                    child: ShareTripSheet(rideId: rideId),
                  ),
                ),
              );
            },
          ),
          _SafetyActionTile(
            icon: Icons.shield_outlined,
            iconColor: AppColors.success,
            title: 'Verify your driver',
            subtitle:
                'Before getting in: match the photo, plate, and model on '
                'the driver card. Share the pickup PIN only with the '
                'matching driver.',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'If anything does not match, cancel free of charge '
                          'and report it from this menu.'),
                ),
              );
            },
          ),
          _SafetyActionTile(
            icon: Icons.report_gmailerrorred_outlined,
            iconColor: AppColors.warning,
            title: 'Report driver conduct',
            subtitle:
                'For a completed ride, use the report option on your receipt. '
                'If you are in immediate danger, call emergency services.',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Open your ride receipt after the trip ends to submit a report. '
                          'For immediate danger, call emergency services.'),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.inputBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ethiopia emergency numbers',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                SizedBox(height: 8),
                Text('Emergency: 911\nPolice: 991\nAmbulance: 907\nFire: 939',
                    style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  const _SafetyActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFFEFF),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE8E1F2))),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: iconColor.withOpacity(0.12),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: enabled ? const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.nidusMuted) : const Icon(Icons.lock_outline_rounded, color: AppColors.nidusMuted),
        onTap: enabled
            ? onTap
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$title is not available yet.')),
                ),
      ),
    );
  }
}
