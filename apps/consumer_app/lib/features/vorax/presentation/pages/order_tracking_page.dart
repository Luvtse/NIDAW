import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/restaurant_repository.dart';

class OrderTrackingPage extends StatefulWidget {
  final String orderId;
  const OrderTrackingPage({super.key, required this.orderId});

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  late Future<Map<String, dynamic>> _trackingFuture;
  Timer? _pollTimer;
  DateTime? _lastUpdated;
  bool _refreshing = false;
  bool _terminalStatusSeen = false;
  int _requestGeneration = 0;

  static const _progressStatuses = <String>[
    'pending',
    'confirmed',
    'preparing',
    'ready_for_pickup',
    'picked_up',
    'delivered',
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
    _startPolling();
  }

  @override
  void didUpdateWidget(covariant OrderTrackingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId == widget.orderId) return;
    _requestGeneration++;
    _refreshing = false;
    _terminalStatusSeen = false;
    _lastUpdated = null;
    _pollTimer?.cancel();
    _refresh();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_terminalStatusSeen) _refresh();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool force = false}) async {
    if (_refreshing || (_terminalStatusSeen && !force)) return;
    _refreshing = true;
    final generation = ++_requestGeneration;
    final orderId = widget.orderId;
    final request = GetIt.I<RestaurantRepository>().trackOrder(orderId);
    if (mounted) {
      setState(() => _trackingFuture = request);
    } else {
      _trackingFuture = request;
    }
    try {
      final data = await request;
      if (!mounted || generation != _requestGeneration) return;
      final status = _normalizedStatus(data['status']);
      final terminal = _isTerminalStatus(status);
      setState(() {
        _lastUpdated = DateTime.now();
        _terminalStatusSeen = terminal;
        _refreshing = false;
      });
      if (terminal) _pollTimer?.cancel();
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Your order'),
          actions: [
            IconButton(
              tooltip: 'Refresh order status',
              onPressed: _refreshing ? null : () => _refresh(force: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _trackingFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _failureState();
            }

            final data = snapshot.data!;
            final status = _normalizedStatus(data['status']);
            final eta = data['estimated_delivery_minutes'];
            final driverId = data['driver_id'];
            final terminal = _isTerminalStatus(status) && status != 'delivered';
            final activeIndex = _progressStatuses.indexOf(status);
            if (terminal || status == 'delivered') _pollTimer?.cancel();

            return RefreshIndicator(
              onRefresh: () async {
                await _refresh(force: true);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: AppColors.voraxGradient,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 26),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('ORDER UPDATE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6))),
                          if (_refreshing)
                            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        ]),
                        const SizedBox(height: 16),
                        Text(_label(status), style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                        if (eta is num && eta >= 0) ...[
                          const SizedBox(height: 12),
                          Row(children: [
                            const Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text('Estimated delivery: ${eta.toInt()} min', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ]),
                        ],
                        if (_lastUpdated != null) ...[
                          const SizedBox(height: 10),
                          Text('Updated ${TimeOfDay.fromDateTime(_lastUpdated!).format(context)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!terminal && activeIndex >= 0) ...[
                    const Text('Your order journey', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                    const SizedBox(height: 14),
                    _statusTimeline(activeIndex),
                    const SizedBox(height: 20),
                  ] else if (terminal) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.error.withOpacity(.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.error.withOpacity(.18))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.error),
                        const SizedBox(width: 10),
                        Expanded(child: Text('The server reports this order as ${_label(status).toLowerCase()}. Refresh for the latest status or contact support if you need help.', style: const TextStyle(height: 1.4))),
                      ]),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (activeIndex < 0 && !terminal && status != 'delivered') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.voraxOrange.withOpacity(.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.voraxOrange.withOpacity(.18)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.sync_rounded, color: AppColors.voraxOrange),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'The latest order status is not recognized by this app yet. Your order reference is preserved; refresh to check for an updated status.',
                              style: TextStyle(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Order reference', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      SelectableText(widget.orderId, style: const TextStyle(color: AppColors.textSecondary)),
                      const Divider(height: 26),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.voraxOrange.withOpacity(.10), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.delivery_dining_rounded, color: AppColors.voraxOrange)),
                        title: Text(driverId != null ? 'Delivery driver assigned' : 'Finding a delivery driver', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(driverId != null ? 'Driver reference: $driverId' : 'Driver details will appear here when the server assigns one.'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  const Text('Status and estimated delivery are provided by the server. A live driver location is shown only when the service supplies authoritative location data.', style: TextStyle(color: AppColors.textSecondary, height: 1.45, fontSize: 12)),
                ],
              ),
            );
          },
        ),
      );

  Widget _statusTimeline(int activeIndex) {
    const labels = <String>[
      'Order received',
      'Restaurant confirmed',
      'Being prepared',
      'Ready for pickup',
      'On the way',
      'Delivered',
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Column(
        children: List.generate(labels.length, (index) {
          final complete = index <= activeIndex;
          final current = index == activeIndex;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 28, child: Column(children: [
              Container(width: 24, height: 24, decoration: BoxDecoration(color: complete ? AppColors.voraxOrange : AppColors.background, shape: BoxShape.circle, border: Border.all(color: complete ? AppColors.voraxOrange : AppColors.border, width: 1.5)), child: complete ? const Icon(Icons.check_rounded, color: Colors.white, size: 15) : null),
              if (index != labels.length - 1) Container(width: 2, height: 28, color: index < activeIndex ? AppColors.voraxOrange : AppColors.border),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 3, bottom: 20), child: Text(labels[index], style: TextStyle(color: complete ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: current ? FontWeight.w800 : FontWeight.w500)))),
            if (current) const Padding(padding: EdgeInsets.only(top: 4), child: Text('NOW', style: TextStyle(color: AppColors.voraxOrange, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1))),
          ]);
        }),
      ),
    );
  }

  Widget _failureState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.sync_problem_rounded, size: 48, color: AppColors.voraxOrange),
            const SizedBox(height: 16),
            const Text('Order status could not be loaded', textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Check your connection and try again. Your order reference is still available.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: _refreshing ? null : () => _refresh(force: true), icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
            const SizedBox(height: 10),
            SelectableText('Order ${widget.orderId}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ]),
        ),
      );

  String _normalizedStatus(Object? value) {
    if (value is! String || value.trim().isEmpty) return 'unknown';
    return value.toLowerCase().trim().replaceAll('-', '_').replaceAll(' ', '_');
  }

  bool _isTerminalStatus(String status) =>
      status.contains('cancel') ||
      status.contains('fail') ||
      status == 'rejected' ||
      status == 'delivered' ||
      status == 'complete' ||
      status == 'completed';

  String _label(String value) {
    if (value.isEmpty || value == 'unknown') return 'Status unavailable';
    return value.split('_').map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}').join(' ');
  }
}
