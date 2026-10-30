import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../bloc/earnings_bloc.dart';

class EarningsOverviewPage extends StatefulWidget {
  const EarningsOverviewPage({super.key});

  @override
  State<EarningsOverviewPage> createState() => _EarningsOverviewPageState();
}

class _EarningsOverviewPageState extends State<EarningsOverviewPage> {
  String _selectedPeriod = 'Daily';

  @override
  void initState() {
    super.initState();
    _loadSelectedPeriod();
  }

  void _loadSelectedPeriod() {
    final now = DateTime.now();
    if (_selectedPeriod == 'Weekly') {
      final startOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - DateTime.monday));
      context.read<EarningsBloc>().add(LoadWeeklyEarnings(startDate: startOfWeek));
    } else {
      context.read<EarningsBloc>().add(LoadDailyEarnings(date: now));
    }
  }

  void _selectPeriod(String period) {
    if (_selectedPeriod == period) return;
    setState(() => _selectedPeriod = period);
    _loadSelectedPeriod();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Earnings'),
      ),
      body: BlocBuilder<EarningsBloc, EarningsState>(
        builder: (context, state) {
          if (state is EarningsLoading || state is EarningsInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is EarningsError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.primary),
                    const SizedBox(height: 12),
                    const Text('Earnings are temporarily unavailable',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('Check your connection and try again.',
                        style: TextStyle(color: AppColors.textSecondary),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loadSelectedPeriod,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state is! EarningsLoaded) {
            return const Center(child: Text('Earnings are not available yet.'));
          }

          final report = state.report;
          final breakdown = report.dailyBreakdown;
          final maxEarnings = breakdown.fold<double>(
            0,
            (maximum, item) => item.earnings > maximum ? item.earnings : maximum,
          );

          return RefreshIndicator(
            onRefresh: () async => _loadSelectedPeriod(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border.withOpacity(.7)),
                  ),
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'Daily', label: Text('Daily')),
                      ButtonSegment(value: 'Weekly', label: Text('Weekly')),
                    ],
                    selected: {_selectedPeriod},
                    onSelectionChanged: (selected) => _selectPeriod(selected.first),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primary.withOpacity(.78)],
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withOpacity(.2), blurRadius: 22, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: Text('Total earnings', style: TextStyle(color: Colors.white70, fontSize: 14))),
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(13)),
                            child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('ETB ${report.totalEarnings.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontSize: 31, height: 1.15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(_selectedPeriod == 'Daily' ? 'Today so far' : 'This week so far',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text('Earnings activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Container(
                  height: 250,
                  padding: const EdgeInsets.fromLTRB(12, 22, 18, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border.withOpacity(.65)),
                  ),
                  child: breakdown.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bar_chart_rounded, size: 38, color: AppColors.textSecondary.withOpacity(.7)),
                              const SizedBox(height: 8),
                              Text('No earnings activity for this period', style: TextStyle(color: AppColors.textSecondary)),
                            ],
                          ),
                        )
                      : BarChart(
                          BarChartData(
                            maxY: maxEarnings <= 0 ? 1 : maxEarnings * 1.18,
                            gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxEarnings > 0 ? maxEarnings / 4 : 1),
                            borderData: FlBorderData(show: false),
                            titlesData: const FlTitlesData(
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            barGroups: breakdown.asMap().entries.map((entry) {
                              return BarChartGroupData(
                                x: entry.key,
                                barRods: [
                                  BarChartRodData(
                                    toY: entry.value.earnings < 0 ? 0 : entry.value.earnings,
                                    color: AppColors.primary,
                                    width: breakdown.length > 7 ? 10 : 18,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                ),
                const SizedBox(height: 22),
                const Text('Your summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _buildStatCard('Total rides', report.totalRides.toString(), Icons.directions_car_filled_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatCard('Tips', 'ETB ${report.tips.toStringAsFixed(2)}', Icons.volunteer_activism_outlined)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _buildStatCard('Online hours', report.onlineHours?.toStringAsFixed(1) ?? 'Unavailable', Icons.schedule_rounded)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatCard('Per hour', report.earningsPerHour == null ? 'Unavailable' : 'ETB ${report.earningsPerHour!.toStringAsFixed(2)}', Icons.trending_up_rounded)),
                ]),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => context.go('/earnings/detail'),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('View detailed breakdown'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withOpacity(.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 12),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, height: 1.2, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
