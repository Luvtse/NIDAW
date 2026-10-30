import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/restaurant_repository.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  void _loadOrders() {
    _ordersFuture = GetIt.I<RestaurantRepository>().listOrders();
  }

  Future<void> _refresh() async {
    setState(_loadOrders);
    try {
      await _ordersFuture;
    } catch (_) {
      // The FutureBuilder below presents the failure and retry action.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Your food orders')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _ordersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _state(
                icon: Icons.cloud_off_rounded,
                title: 'Orders could not be loaded',
                message: 'Check your connection and try again.',
                actionLabel: 'Try again',
                onAction: () => setState(_loadOrders),
              );
            }
            final orders = snapshot.data ?? const <Map<String, dynamic>>[];
            if (orders.isEmpty) {
              return _state(
                icon: Icons.receipt_long_rounded,
                title: 'Your table is still empty',
                message: 'When you place a food order, its progress will appear here.',
                actionLabel: 'Explore restaurants',
                onAction: () => context.go('/vorax/restaurants'),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final order = orders[index];
                  final id = order['id']?.toString() ?? '';
                  final status = order['status']?.toString() ?? 'unknown';
                  final canTrack = id.isNotEmpty;
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: canTrack ? () => context.push('/vorax/order/$id/tracking') : null,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(color: AppColors.voraxOrange.withOpacity(.10), borderRadius: BorderRadius.circular(15)),
                            child: const Icon(Icons.delivery_dining_rounded, color: AppColors.voraxOrange),
                          ),
                          const SizedBox(width: 13),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Order ${_shortId(id)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            const SizedBox(height: 5),
                            Text(_label(status), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ])),
                          const SizedBox(width: 8),
                          Icon(canTrack ? Icons.chevron_right_rounded : Icons.info_outline_rounded, color: AppColors.textSecondary),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      );

  Widget _state({required IconData icon, required String title, required String message, String? actionLabel, VoidCallback? onAction}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 76, height: 76, decoration: BoxDecoration(color: AppColors.voraxOrange.withOpacity(.10), shape: BoxShape.circle), child: Icon(icon, color: AppColors.voraxOrange, size: 34)),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.45)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ]),
        ),
      );

  String _shortId(String id) => id.length > 10 ? '${id.substring(0, 8)}…' : id.isEmpty ? 'reference unavailable' : id;

  String _label(String value) => value.split('_').map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}').join(' ');
}
