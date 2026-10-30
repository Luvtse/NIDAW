import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/active_ride.dart';
import '../bloc/active_ride_bloc.dart';

class RideCompletionPage extends StatefulWidget {
  final String rideId;

  const RideCompletionPage({super.key, required this.rideId});

  @override
  State<RideCompletionPage> createState() => _RideCompletionPageState();
}

class _RideCompletionPageState extends State<RideCompletionPage> {
  double _tipAmount = 0;
  bool _submitted = false;
  final List<double> _tipOptions = [0, 2, 5, 10, 20];

  String _money(ActiveRide ride, double amount) =>
      ride.currency.isEmpty ? 'Amount unavailable' : '${ride.currency} ${amount.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ActiveRideBloc, ActiveRideState>(
      listener: (context, state) {
        if (state is ActiveRideCompleted && state.ride.id == widget.rideId) {
          setState(() => _submitted = false);
        } else if (state is ActiveRideError) {
          setState(() => _submitted = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ride completion failed: ${state.message}'), backgroundColor: AppColors.error),
          );
        }
      },
      builder: (context, state) {
        if (state is ActiveRideLoading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (state is ActiveRideInitial) {
          return Scaffold(
            appBar: AppBar(title: const Text('Complete Ride')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.primary),
                    const SizedBox(height: 16),
                    const Text('No active ride found.', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Refresh the active ride before trying to complete it.', textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => context.read<ActiveRideBloc>().add(const RecoverActiveRideRequested()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh ride'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (state is ActiveRideError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Complete Ride')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 56, color: AppColors.error),
                    const SizedBox(height: 16),
                    const Text(
                      'We could not load the active ride.',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
            ),
          );
        }
        final ActiveRide? ride = state is ActiveRideLoaded
            ? state.ride
            : state is ActiveRideCompleted
                ? state.ride
                : null;
        if (ride == null || ride.id != widget.rideId) {
          return Scaffold(
            appBar: AppBar(title: const Text('Complete Ride')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.primary),
                    const SizedBox(height: 16),
                    const Text(
                      'Ride details are unavailable.',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Refresh the active ride before continuing.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => context.read<ActiveRideBloc>().add(const RecoverActiveRideRequested()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh ride'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final completed = state is ActiveRideCompleted || ride.isCompleted;
        final canComplete = !completed && ride.isInProgress && !_submitted;
        return Scaffold(
          appBar: AppBar(title: Text(completed ? 'Ride Summary' : 'Complete Ride')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(completed ? Icons.check_circle : Icons.receipt_long, size: 88, color: completed ? AppColors.success : AppColors.primary),
                const SizedBox(height: 20),
                Text(completed ? 'Ride completed' : 'Review ride completion', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Ride ${ride.id}', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _buildEarningsRow('Server-reported fare', _money(ride, ride.fareAmount)),
                      const Divider(height: 24),
                      _buildEarningsRow('Tip', _money(ride, completed ? ride.tipAmount : _tipAmount)),
                      const Divider(height: 24),
                      _buildEarningsRow('Fare + tip', _money(ride, ride.fareAmount + (completed ? ride.tipAmount : _tipAmount)), isTotal: true),
                    ],
                  ),
                ),
                if (!completed && ride.isInProgress) ...[
                  const SizedBox(height: 28),
                  const Text('Optional tip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: _tipOptions.map((amount) {
                      final selected = _tipAmount == amount;
                      return ChoiceChip(
                        label: Text(amount == 0 ? 'No tip' : _money(ride, amount)),
                        selected: selected,
                        onSelected: _submitted ? null : (value) { if (value) setState(() => _tipAmount = amount); },
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600),
                      );
                    }).toList(),
                  ),
                ] else if (!completed) ...[
                  const SizedBox(height: 16),
                  const Text('The server has not marked this ride as in progress, so completion is unavailable.', textAlign: TextAlign.center),
                ],
                const SizedBox(height: 36),
                if (completed)
                  ElevatedButton(onPressed: () => context.go('/home'), child: const Text('Return Home'))
                else
                  ElevatedButton(
                    onPressed: canComplete ? _completeRide : null,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18), backgroundColor: AppColors.success),
                    child: Text(_submitted ? 'Submitting…' : 'Confirm completion'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEarningsRow(String label, String amount, {bool isTotal = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: isTotal ? 17 : 15, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal))),
          const SizedBox(width: 12),
          Text(amount, style: TextStyle(fontSize: isTotal ? 20 : 16, fontWeight: FontWeight.bold, color: isTotal ? AppColors.primary : null)),
        ],
      );

  void _completeRide() {
    if (_submitted) return;
    setState(() => _submitted = true);
    context.read<ActiveRideBloc>().add(CompleteRideRequested(rideId: widget.rideId, tipAmount: _tipAmount));
  }
}
