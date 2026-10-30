import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/earnings_repository.dart';
import '../../domain/entities/earnings_report.dart';

class EarningsDetailPage extends StatefulWidget {
  const EarningsDetailPage({super.key});

  @override
  State<EarningsDetailPage> createState() => _EarningsDetailPageState();
}

class _EarningsDetailPageState extends State<EarningsDetailPage> {
  late final EarningsRepository _repository = GetIt.I<EarningsRepository>();
  EarningsReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    try {
      final report = await _repository.getWeeklyEarnings(start);
      if (!mounted) return;
      setState(() { _report = report; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Earnings details are unavailable. Retry when connected.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Earnings Details'), actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), ElevatedButton(onPressed: _load, child: const Text('Retry'))])))
              : report == null
                  ? const Center(child: Text('Earnings are unavailable.'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('This Week', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                              const SizedBox(height: 8),
                              Text('ETB ${report.totalEarnings.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary)),
                              const SizedBox(height: 16),
                              Row(children: [
                                _buildMiniStat('Rides', report.totalRides.toString()),
                                const SizedBox(width: 24),
                                _buildMiniStat('Hours', report.onlineHours?.toStringAsFixed(1) ?? 'Unavailable'),
                                const SizedBox(width: 24),
                                _buildMiniStat('Tips', 'ETB ${report.tips.toStringAsFixed(2)}'),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('Daily Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        if (report.dailyBreakdown.isEmpty)
                          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No ledger earnings recorded for this period.', textAlign: TextAlign.center))
                        else
                          ...report.dailyBreakdown.map(_buildDailyCard),
                      ],
                    ),
    );
  }

  Widget _buildMiniStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      );

  Widget _buildDailyCard(DailyEarnings day) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(DateFormat('dd').format(day.date), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
                Text(DateFormat('MMM').format(day.date), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ),
          title: Text('ETB ${day.earnings.toStringAsFixed(2)}'),
          subtitle: Text('${day.rides} completed rides · Tips ETB ${day.tips.toStringAsFixed(2)}'),
        ),
      );
}
