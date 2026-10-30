import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../data/repositories/ride_repository.dart';
import '../../domain/entities/ride_offer.dart';
import '../bloc/active_ride_bloc.dart';

class RideAcceptancePage extends StatefulWidget {
  final String rideId;

  const RideAcceptancePage({
    super.key,
    required this.rideId,
  });

  @override
  State<RideAcceptancePage> createState() => _RideAcceptancePageState();
}

class _RideAcceptancePageState extends State<RideAcceptancePage> {
  int _timeLeft = 30;
  Timer? _timer;
  RideOffer? _offer;
  bool _loading = true;
  bool _accepting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadOffer();
  }

  Future<void> _loadOffer() async {
    try {
      final response = await getIt<ApiClient>().get('/api/v1/nidus/drivers/pending-rides');
      final body = response.data as Map<String, dynamic>;
      final offers = body['rides'];
      if (offers is! List) throw StateError('Ride offer is unavailable');
      final matches = offers.whereType<Map<String, dynamic>>().where((item) {
        return (item['ride_id'] ?? item['id'])?.toString() == widget.rideId;
      });
      if (matches.isEmpty) throw StateError('Ride offer has expired or is no longer available');
      final offer = matches.first;
      final fare = offer['estimated_fare'];
      final requestedAt = DateTime.parse(offer['requested_at'] as String);
      final offerModel = RideOffer(
        id: widget.rideId,
        pickupLat: (offer['pickup_lat'] as num).toDouble(),
        pickupLng: (offer['pickup_lng'] as num).toDouble(),
        pickupAddress: offer['pickup_address'] as String? ?? '',
        dropoffLat: (offer['dropoff_lat'] as num).toDouble(),
        dropoffLng: (offer['dropoff_lng'] as num).toDouble(),
        dropoffAddress: offer['dropoff_address'] as String? ?? '',
        fareAmount: (fare as num?)?.toDouble(),
        currency: offer['currency'] as String? ?? '',
        status: offer['status'] as String? ?? 'requested',
        rideType: offer['ride_type'] as String? ?? '',
        requestedAt: requestedAt,
      );
      if (!mounted) return;
      setState(() {
        _offer = offerModel;
        _loading = false;
        _loadError = null;
      });
      _startTimer();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _retryLoadOffer() async {
    if (!mounted) return;
    _timer?.cancel();
    setState(() {
      _loading = true;
      _loadError = null;
      _timeLeft = 30;
    });
    await _loadOffer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_accepting || _timeLeft <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() => _timeLeft--);
      } else {
        timer.cancel();
        if (!_accepting) _autoDecline();
      }
    });
  }

  Future<void> _dismissOffer({bool expired = false}) async {
    if (_accepting) return;
    final offer = _offer;
    if (offer != null && offer.status == 'matched') {
      try {
        await getIt<RideRepository>().cancelRide(offer.id, 'driver_declined');
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to release this offer: $error')),
          );
        }
      }
    }
    if (!mounted) return;
    if (expired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride offer expired'), backgroundColor: AppColors.warning),
      );
    }
    context.pop();
  }

  void _autoDecline() {
    _dismissOffer(expired: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final offer = _offer;
    if (offer == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                _loadError ?? 'Ride offer is unavailable',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _retryLoadOffer,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => context.pop(), child: const Text('Close')),
            ]),
          ),
        ),
      );
    }

    return BlocListener<ActiveRideBloc, ActiveRideState>(
      listener: (context, state) {
        if (state is ActiveRideLoaded &&
            state.ride.id == widget.rideId &&
            state.ride.status != 'matched' &&
            state.ride.status != 'requested' &&
            state.ride.status != 'searching') {
          context.go('/ride/navigate/${widget.rideId}');
        } else if (state is ActiveRideError) {
          if (_accepting && mounted) {
            setState(() => _accepting = false);
            _startTimer();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.nidusInk,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
              child: Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.bolt_rounded, color: Color(0xFFDCD2FF)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('NEW RIDE OFFER', style: TextStyle(color: Color(0xFFDCD2FF), fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w800)),
                    SizedBox(height: 3),
                    Text('Your next trip', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  ])),
                  IconButton(onPressed: _accepting ? null : () { _timer?.cancel(); _dismissOffer(); }, icon: const Icon(Icons.close_rounded, color: Colors.white70)),
                ],
              ),
            ),
            // Timer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: CircularProgressIndicator(
                      value: _timeLeft / 30,
                      strokeWidth: 7,
                      backgroundColor: Colors.white.withOpacity(0.12),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  Text(
                    '$_timeLeft',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFEFF),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFDCD2FF), width: 1),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.16), blurRadius: 28, offset: const Offset(0, 12))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Fare
                    Center(
                      child: Text(
                        offer.fareAmount != null && offer.fareAmount! > 0 ? '${offer.currency} ${offer.fareAmount!.toStringAsFixed(2)}' : 'Fare unavailable',
                        style: const TextStyle(
                          fontSize: 42,
                          letterSpacing: -1.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Center(child: Text('ESTIMATED EARNINGS', style: TextStyle(fontSize: 10, letterSpacing: 1.4, color: AppColors.nidusMuted, fontWeight: FontWeight.w800))),
                    const SizedBox(height: 26),
                    
                    // Pickup
                    _buildLocationRow(
                      icon: Icons.circle,
                      iconColor: AppColors.success,
                      label: 'Pickup',
                      address: offer.pickupAddress,
                    ),
                    const SizedBox(height: 16),
                    
                    // Dropoff
                    _buildLocationRow(
                      icon: Icons.circle,
                      iconColor: AppColors.error,
                      label: 'Dropoff',
                      address: offer.dropoffAddress,
                    ),
                    const SizedBox(height: 32),
                    
                    const Spacer(),
                    
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _accepting ? null : () {
                              _timer?.cancel();
                              _dismissOffer();
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 17),
                              side: const BorderSide(color: Color(0xFFE8E1F2)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text(
                              'Dismiss',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppColors.nidusMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _accepting || _timeLeft <= 0 ? null : () {
                              setState(() => _accepting = true);
                              _timer?.cancel();
                              context.read<ActiveRideBloc>().add(
                                    AcceptRideRequested(rideId: offer.id),
                                  );
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 17),
                              backgroundColor: AppColors.primary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(
                              _accepting ? 'Accepting…' : 'Accept',
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String address,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}