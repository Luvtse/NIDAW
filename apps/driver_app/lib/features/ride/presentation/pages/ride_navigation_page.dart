import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;
import '../../../../core/theme/app_colors.dart';
import '../bloc/active_ride_bloc.dart';
import '../widgets/rider_info_card.dart';
import '../widgets/navigation_controls.dart';
import '../widgets/stop_contract_card.dart';
import '../data/repositories/masked_call_repository.dart' show MaskedCallRepository, MaskedCallException;
import 'driver_chat_page.dart';
import 'ride_completion_page.dart';

class RideNavigationPage extends StatelessWidget {
  final String rideId;

  const RideNavigationPage({super.key, required this.rideId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.nidusCanvas,
      body: BlocBuilder<ActiveRideBloc, ActiveRideState>(
        builder: (context, state) {
          if (state is ActiveRideLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ActiveRideInitial) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.route_outlined, size: 56, color: AppColors.primary),
                    const SizedBox(height: 16),
                    const Text(
                      'No active ride found.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.nidusInk),
                    ),
                    const SizedBox(height: 8),
                    const Text('Refresh your active ride or return to the driver home screen.', textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => context.read<ActiveRideBloc>().add(const RecoverActiveRideRequested()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh ride'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state is ActiveRideError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 54, color: AppColors.error),
                    const SizedBox(height: 16),
                    const Text(
                      'Ride information is unavailable.',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.nidusInk),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(state.message, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => context.read<ActiveRideBloc>().add(const RecoverActiveRideRequested()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state is ActiveRideCompleted) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 60, color: AppColors.success),
                    const SizedBox(height: 16),
                    const Text('This ride is complete.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Return to the ride summary to review the final fare.', textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Back to ride summary')),
                  ],
                ),
              ),
            );
          }
          if (state is! ActiveRideLoaded || state.ride.id != rideId) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.route_outlined, size: 54, color: AppColors.primary),
                    const SizedBox(height: 16),
                    const Text('The requested ride is not active.', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Refresh the active ride before using navigation.', textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => context.read<ActiveRideBloc>().add(const RecoverActiveRideRequested()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh ride'),
                    ),
                  ],
                ),
              ),
            );
          }

          return Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF0EBFF), Color(0xFFF9F6FD), Color(0xFFE9E2F7)]),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.fromLTRB(24, 100, 24, 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 76, height: 76, decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.12), blurRadius: 26, offset: const Offset(0, 10))]), child: const Icon(Icons.navigation_rounded, size: 36, color: AppColors.primary)),
                    const SizedBox(height: 18),
                    const Text('YOUR ROUTE, AT A GLANCE', style: TextStyle(fontSize: 10, letterSpacing: 1.8, color: AppColors.nidusMuted, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                      'Turn-by-turn navigation opens in your configured maps app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.nidusInk, height: 1.5),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () => _openNavigation(
                        context,
                        state.ride.isInProgress ? state.ride.dropoffLat : state.ride.pickupLat,
                        state.ride.isInProgress ? state.ride.dropoffLng : state.ride.pickupLng,
                      ),
                      icon: Icon(state.ride.isInProgress ? Icons.flag : Icons.directions),
                      label: Text(state.ride.isInProgress ? 'Navigate to drop-off' : 'Navigate to pickup'),
                      style: OutlinedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.nidusInk, side: const BorderSide(color: AppColors.nidusLine), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13)),
                    ),
                  ],
                ),
              ),

              // Top Bar
              Positioned(
                top: 50,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        state.ride.currency.isEmpty ? 'Fare unavailable' : '${state.ride.currency} ${state.ride.fareAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Sheet
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                    border: Border.all(color: const Color(0xFFE8E1F2)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 38, height: 4, decoration: BoxDecoration(color: AppColors.nidusLine, borderRadius: BorderRadius.circular(99))),
                      const SizedBox(height: 18),
                      // Status
                      _buildStatusIndicator(state.ride.status),

                      const SizedBox(height: 20),

                      // Rider Info
                      RiderInfoCard(
                        riderName: state.ride.riderName,
                        riderRating: state.ride.riderRating,
                        pickupAddress: state.ride.pickupAddress,
                        dropoffAddress: state.ride.dropoffAddress,
                        onCall: () => _callRider(context),
                        onChat: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DriverChatPage(rideId: rideId),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // FARE INTEGRITY Phase 2: read-only stop contract view.
                      // Renders nothing when the trip has no stops; never any
                      // money-mutating control (approval is rider-only).
                      StopContractCard(ride: state.ride),

                      // Navigation Controls
                      NavigationControls(
                        status: state.ride.status,
                        onNavigateToPickup: () {
                          _openNavigation(
                            context,
                            state.ride.pickupLat,
                            state.ride.pickupLng,
                          );
                        },
                        onStartRide: () {
                          context.read<ActiveRideBloc>().add(StartRideRequested(rideId: rideId));
                        },
                        onCompleteRide: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => RideCompletionPage(rideId: rideId),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      // Action Buttons

                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _callRider(BuildContext context) async {
    try {
      await MaskedCallRepository().callRideParticipant(rideId);
    } on MaskedCallException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masked calling is not available for this ride yet.')),
      );
    }
  }

  Widget _buildStatusIndicator(String status) {
    String text;
    Color color;
    IconData icon;

    switch (status) {
      case 'driver_en_route':
        text = 'En route to pickup';
        color = AppColors.info;
        icon = Icons.directions_car;
        break;
      case 'in_progress':
        text = 'Ride in progress';
        color = AppColors.success;
        icon = Icons.navigation;
        break;
      default:
        text = 'Preparing';
        color = Colors.grey;
        icon = Icons.hourglass_empty;
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Future<void> _openNavigation(
    BuildContext context,
    double lat,
    double lng,
  ) async {
    if (!lat.isFinite || !lng.isFinite || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Navigation coordinates are unavailable.')),
      );
      return;
    }
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '$lat,$lng',
      'travelmode': 'driving',
    });
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open a navigation app.')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open navigation. Check that a maps app or browser is available.')),
      );
    }
  }
}