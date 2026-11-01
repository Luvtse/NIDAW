import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/router/app_router.dart';
import '../../data/repositories/ride_repository.dart';
import '../bloc/ride_bloc.dart';
import '../widgets/cancel_ride_sheet.dart';

class RideHistoryPage extends StatefulWidget {
  const RideHistoryPage({super.key});

  @override
  State<RideHistoryPage> createState() => _RideHistoryPageState();
}

class _RideHistoryPageState extends State<RideHistoryPage> {
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    context.read<RideBloc>().add(const LoadRideHistory());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // §4.3: routed through the ARB catalog (was a hardcoded English literal).
        title: Text(context.l10n.historyTitle),
        // §4.4: theme token (was hardcoded Colors.white) for dark-mode parity.
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            // §4.4: theme token (was hardcoded Colors.white).
            color: AppColors.surface,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Phase 1 §3: chip labels route through the ARB catalog
                  // (were hardcoded English literals).
                  _buildFilterChip('all', context.l10n.historyFilterAll),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                      'completed', context.l10n.historyFilterCompleted),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                      'cancelled', context.l10n.historyFilterCancelled),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                      'in_progress', context.l10n.historyFilterInProgress),
                ],
              ),
            ),
          ),

          // Ride list
          Expanded(
            child: BlocBuilder<RideBloc, RideState>(
              builder: (context, state) {
                if (state is RideLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is RideHistoryLoaded) {
                  if (state.rides.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.rides.length,
                    itemBuilder: (context, index) {
                      return _buildRideCard(state.rides[index]);
                    },
                  );
                }

                if (state is RideError) {
                  return _buildErrorState(state.message);
                }

                // Phase 1 §3 (history loading/empty conflation): every
                // pre-load state — RideInitial, or any foreign bloc state
                // arriving before our first LoadRideHistory result lands —
                // renders the skeleton, NEVER a 'No rides found' message.
                // The old fallback here showed a false empty state during
                // the initial frame and whenever the shared RideBloc was in
                // an unrelated state, which read as "your history is gone".
                return _buildLoadingSkeleton();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Skeleton placeholder for pre-load states. Mirrors the ride-card layout
  /// so the list area never flashes content it does not have yet.
  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      itemBuilder: (context, index) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 140,
                          height: 14,
                          color: Colors.grey[200],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 80,
                          height: 10,
                          color: Colors.grey[200],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 12, color: Colors.grey[200]),
              const SizedBox(height: 8),
              Container(width: 200, height: 12, color: Colors.grey[200]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedFilter = value);
        context.read<RideBloc>().add(
              LoadRideHistory(status: value == 'all' ? null : value),
            );
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        // §4.4: named token — the chip's selected background is the primary
        // (dark) fill, so white foreground is intentional; use the token so
        // the intent is explicit rather than a raw Colors.white.
        color: isSelected ? AppColors.textOnDark : AppColors.textPrimary,
      ),
    );
  }

  Widget _buildRideCard(Ride ride) {
    final statusColor = _getStatusColor(ride.status);
    final statusIcon = _getStatusIcon(ride.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/nidus/tracking/${ride.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(ride.requestedAt),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        // §3.6: scheduled rides show WHEN the pickup is due,
                        // not when the request was placed. The backend keeps
                        // the real pickup time in scheduled_at; requestedAt
                        // stays as the secondary line for traceability.
                        if (_isScheduledUpcoming(ride)) ...[
                          Text(
                            'Pickup ${DateFormat('MMM d • h:mm a').format(ride.scheduledAt!.toLocal())}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Requested ${_formatTime(ride.requestedAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ] else
                          Text(
                            _formatTime(ride.requestedAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // §3.6 "Scheduled" chip — rendered from the ride's own
                  // data (scheduled_at present + non-terminal status), so
                  // it can never claim "scheduled" for a ride that already
                  // ran or was cancelled.
                  if (_isScheduledUpcoming(ride)) ...[
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule,
                              size: 12, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            'Scheduled',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _formatStatus(ride.status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Route
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Container(
                        width: 2,
                        height: 40,
                        color: Colors.grey[300],
                      ),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride.pickupAddress ?? 'Pickup location',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          ride.dropoffAddress ?? 'Dropoff location',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.directions_car, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${ride.distanceKm?.toStringAsFixed(1) ?? '0'} km',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${ride.durationMinutes ?? 0} min',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  Text(
                    '${ride.currency} ${ride.fareAmount?.toStringAsFixed(2) ?? "—"}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),

              // Dispute shortcut for completed rides (Phase H Step 1):
              // opens the wallet with the dispute form pre-filled.
              if (ride.status == 'completed') ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => context.goWalletDispute(ride.id),
                    icon: const Icon(Icons.gavel, size: 16),
                    label: const Text('File a dispute'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                  ),
                ),
              ],

              // §3.6 scheduled-ride cancel action. Routed through the SAME
              // authoritative CancelRideSheet as the tracking page — it
              // fetches GET /rides/{id}/cancellation-quote, so the fee the
              // rider sees here is the fee the backend charges under the
              // scheduled-ride cancellation policy. No client-side estimate.
              if (_isScheduledUpcoming(ride)) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _cancelScheduledRide(ride),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel scheduled ride'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// A ride counts as "scheduled & upcoming" when the backend attached a
  /// pickup time (§3.6) and the status has not reached a terminal state.
  /// Completed/cancelled rows render as normal history entries even if
  /// they were created via the schedule flow.
  bool _isScheduledUpcoming(Ride ride) {
    if (ride.scheduledAt == null) return false;
    const terminal = {'completed', 'cancelled', 'no_drivers_found'};
    return !terminal.contains(ride.status);
  }

  Future<void> _cancelScheduledRide(Ride ride) async {
    await CancelRideSheet.show(
      context,
      rideId: ride.id,
      onConfirmed: (reason) async {
        context.read<RideBloc>().add(
              CancelRide(rideId: ride.id, reason: reason),
            );
        // Refresh the list so the cancelled row drops its Scheduled chip
        // immediately instead of waiting for the next manual reload.
        context.read<RideBloc>().add(
              LoadRideHistory(
                status: _selectedFilter == 'all' ? null : _selectedFilter,
              ),
            );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          // Phase 1 §3: localized primary; the filtered variant takes the
          // filter label as an argument (was string-interpolated English).
          Text(
            _selectedFilter == 'all'
                ? context.l10n.historyEmpty
                : context.l10n.historyEmptyFiltered(
                    _filterLabel(_selectedFilter)),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              // Phase 1 §3: ARB catalog (were hardcoded English literals).
              _selectedFilter == 'all'
                  ? context.l10n.historyEmptyBody
                  : context.l10n.historyEmptyFilteredBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 24),
          if (_selectedFilter != 'all')
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _selectedFilter = 'all');
                context.read<RideBloc>().add(const LoadRideHistory());
              },
              icon: const Icon(Icons.filter_alt_off),
              // Phase 1 §3: ARB catalog (was a hardcoded English literal).
              label: Text(context.l10n.historyClearFilter),
            )
          else
            ElevatedButton.icon(
              onPressed: () => context.push('/nidus/request'),
              icon: const Icon(Icons.add),
              // Phase 1 §3: ARB catalog (was a hardcoded English literal).
              label: Text(context.l10n.historyRequestRide),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          // Phase 1 §3: localized primary headline (was hardcoded English
          // 'Error loading rides'). The raw server message is demoted to a
          // detail line below — useful for support, never the headline.
          Text(
            context.l10n.historyErrorPrimary,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              context.read<RideBloc>().add(
                    LoadRideHistory(
                      status: _selectedFilter == 'all' ? null : _selectedFilter,
                    ),
                  );
            },
            // Phase 1 §3: ARB catalog (was a hardcoded English literal).
            child: Text(context.l10n.historyRetry),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'in_progress':
        return AppColors.primary;
      case 'requested':
      case 'matched':
        return AppColors.warning;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      case 'in_progress':
        return Icons.directions_car;
      case 'requested':
        return Icons.hourglass_empty;
      case 'matched':
        return Icons.person;
      default:
        return Icons.help;
    }
  }

  String _filterLabel(String value) {
    switch (value) {
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'in_progress':
        return 'In progress';
      default:
        return 'All';
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }

  String _formatTime(DateTime date) {
    return DateFormat('h:mm a').format(date);
  }

  String _formatStatus(String status) {
    return status.replaceAll('_', ' ').split(' ').map((word) {
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }
}