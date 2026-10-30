import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../bloc/driver_home_bloc.dart';
import '../widgets/driver_map.dart';

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  @override
  void initState() {
    super.initState();
    context.read<DriverHomeBloc>().add(const LoadDriverStats());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<DriverHomeBloc, DriverHomeState>(
        listener: (context, state) {
          if (state is DriverHomeLoaded && state.pendingRideId != null) {
            final rideId = state.pendingRideId!;
            context.read<DriverHomeBloc>().add(const ClearPendingRideOffer());
            context.push('/ride/accept/$rideId');
          }
          final message = state is DriverHomeError
              ? state.message
              : state is DriverHomeLoaded
                  ? state.message
                  : null;
          if (message != null && message.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message), backgroundColor: AppColors.error),
            );
          }
        },
        builder: (context, state) {
          if (state is DriverHomeLoading) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (state is! DriverHomeLoaded) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.textTertiary),
                  const SizedBox(height: 14),
                  const Text('Could not load your driver dashboard', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  const Text('Check your connection and try again.', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 18),
                  FilledButton(onPressed: () => context.read<DriverHomeBloc>().add(const LoadDriverStats()), child: const Text('Try again')),
                ]),
              ),
            );
          }

          return Stack(
            children: [
              Positioned.fill(child: DriverMap(currentPosition: state.currentPosition, isOnline: state.isOnline)),
              Positioned.fill(child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [AppColors.nidusInk.withOpacity(.14), Colors.transparent]))))),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                  child: Row(
                    children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.nidusInk, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: AppColors.nidusInk.withOpacity(.18), blurRadius: 14, offset: const Offset(0, 5))]), child: const Icon(Icons.all_inclusive_rounded, color: AppColors.nidusLilac, size: 26)),
                      const SizedBox(width: 11),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text('NIDAW', style: TextStyle(color: AppColors.nidusInk, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 14)), SizedBox(height: 2), Text('DRIVER MODE', style: TextStyle(color: AppColors.nidusMuted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.6))])),
                      _topAction(Icons.menu_rounded, () => _showMenu(context)),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 70,
                left: 18,
                right: 18,
                child: _availabilityCard(context, state.isOnline, state.isAvailabilityChanging),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  padding: EdgeInsets.fromLTRB(18, 18, 18, 14 + MediaQuery.of(context).padding.bottom),
                  decoration: const BoxDecoration(
                    color: AppColors.nidusPaper,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [BoxShadow(color: Color(0x1F21172F), blurRadius: 28, offset: Offset(0, -8))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: AppColors.nidusLine, borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 18),
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TODAY SO FAR', style: TextStyle(color: AppColors.nidusMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)), SizedBox(height: 6), Text('Your shift, at a glance', style: TextStyle(color: AppColors.nidusInk, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.4))])),
                        TextButton.icon(onPressed: () => context.push('/earnings'), icon: const Icon(Icons.north_east_rounded, size: 16), label: const Text('Earnings'), style: TextButton.styleFrom(foregroundColor: AppColors.primary, textStyle: const TextStyle(fontWeight: FontWeight.w800))),
                      ]),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(color: AppColors.nidusInk, borderRadius: BorderRadius.circular(22)),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('EARNED TODAY', style: TextStyle(color: Color(0xFFCDC3E0), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.3)), const SizedBox(height: 7), Text('ETB ${state.stats.todayEarnings.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.7))])),
                          Container(width: 1, height: 44, color: Colors.white.withOpacity(.16)),
                          const SizedBox(width: 16),
                          _miniMetric('${state.stats.todayRides}', 'TRIPS'),
                          const SizedBox(width: 20),
                          _miniMetric(state.stats.onlineHours?.toStringAsFixed(1) ?? '—', 'HOURS'),
                        ]),
                      ),
                      const SizedBox(height: 13),
                      Row(children: [
                        Expanded(child: _statChip(Icons.star_rounded, state.stats.averageRating.toStringAsFixed(1), 'Rating', const Color(0xFFB98225))),
                        const SizedBox(width: 9),
                        Expanded(child: _statChip(Icons.check_circle_rounded, '${state.stats.acceptanceRate.toInt()}%', 'Acceptance', AppColors.success)),
                        const SizedBox(width: 9),
                        Expanded(child: _statChip(Icons.route_rounded, '${state.stats.totalRides}', 'All trips', AppColors.primary)),
                      ]),
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

  Widget _availabilityCard(BuildContext context, bool isOnline, bool isChanging) => Container(
        padding: const EdgeInsets.fromLTRB(15, 12, 12, 12),
        decoration: BoxDecoration(color: AppColors.nidusPaper, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: AppColors.nidusInk.withOpacity(.12), blurRadius: 20, offset: const Offset(0, 7))], border: Border.all(color: AppColors.nidusLine)),
        child: Row(children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(color: isOnline ? AppColors.success : AppColors.textTertiary, shape: BoxShape.circle, boxShadow: isOnline ? [BoxShadow(color: AppColors.success.withOpacity(.35), blurRadius: 8, spreadRadius: 2)] : null)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isOnline ? 'You’re on the road' : 'You’re offline', style: const TextStyle(color: AppColors.nidusInk, fontSize: 14, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(isOnline ? 'Ready to receive ride requests' : 'Go online when you’re ready to earn', style: const TextStyle(color: AppColors.nidusMuted, fontSize: 11))])),
          if (isChanging) const SizedBox(width: 48, height: 32, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primary)))) else Switch.adaptive(value: isOnline, onChanged: (value) => context.read<DriverHomeBloc>().add(ToggleAvailability(isOnline: value)), activeColor: AppColors.primary),
        ]),
      );

  Widget _topAction(IconData icon, VoidCallback onTap) => Material(
        color: AppColors.nidusPaper,
        shape: const CircleBorder(),
        child: InkWell(onTap: onTap, customBorder: const CircleBorder(), child: SizedBox(width: 42, height: 42, child: Icon(icon, color: AppColors.nidusInk, size: 21))),
      );

  Widget _miniMetric(String value, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Color(0xFFCDC3E0), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1))]);

  Widget _statChip(IconData icon, String value, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(color: color.withOpacity(.08), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(.13))),
        child: Row(children: [Icon(icon, size: 17, color: color), const SizedBox(width: 7), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.nidusInk, fontWeight: FontWeight.w900, fontSize: 13)), const SizedBox(height: 2), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.nidusMuted, fontSize: 9))]))]),
      );

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: const BoxDecoration(color: AppColors.nidusPaper, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: AppColors.nidusLine, borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 16),
          _menuItem(sheetContext, Icons.account_balance_wallet_outlined, 'Earnings', 'Your daily and past income', '/earnings'),
          _menuItem(sheetContext, Icons.description_outlined, 'Documents', 'Keep your driver documents current', '/documents'),
          _menuItem(sheetContext, Icons.directions_car_filled_outlined, 'Vehicle', 'Vehicle details and information', '/profile/vehicle'),
          _menuItem(sheetContext, Icons.person_outline_rounded, 'Profile', 'Your driver account', '/profile'),
          _menuItem(sheetContext, Icons.settings_outlined, 'Settings', 'App preferences', '/settings'),
          ListTile(leading: const Icon(Icons.logout_rounded, color: AppColors.error), title: const Text('Log out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)), onTap: () { Navigator.pop(sheetContext); context.read<AuthBloc>().add(const LogoutRequested()); }),
        ])),
      ),
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String title, String subtitle, String route) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.nidusLilacWash, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: AppColors.primary)),
        title: Text(title, style: const TextStyle(color: AppColors.nidusInk, fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.nidusMuted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.nidusMuted),
        onTap: () { Navigator.pop(context); this.context.push(route); },
      );
}
