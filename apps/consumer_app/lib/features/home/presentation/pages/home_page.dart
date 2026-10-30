import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.nidusCanvas,
      body: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) {
          final user = state is AuthAuthenticated ? state.user : null;
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHero(context, user)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 0),
                sliver: SliverToBoxAdapter(child: _buildSectionHeading('Where to next?', 'Choose your way to move')),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(child: _buildNidusFeature(context)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                sliver: SliverToBoxAdapter(child: _buildSectionHeading('More from NIDAW', 'One account. More ways to go.')),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(child: _buildServices(context)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                sliver: SliverToBoxAdapter(child: _buildWalletShortcut(context)),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          );
        },
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildHero(BuildContext context, dynamic user) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.nidusInk, Color(0xFF49336D), AppColors.primary],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -42,
            top: 60,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(.08), width: 28),
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: 34,
            child: Transform.rotate(
              angle: -.35,
              child: Icon(Icons.route_rounded, size: 88, color: Colors.white.withOpacity(.10)),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(.13), borderRadius: BorderRadius.circular(15)),
                        child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 11),
                      const Text('NIDAW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2.4, fontSize: 17)),
                      const Spacer(),
                      _roundAction(Icons.notifications_none_rounded, () => context.push('/nidus/notifications')),
                      const SizedBox(width: 9),
                      _roundAction(Icons.person_outline_rounded, () => context.push('/profile')),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text('GOOD ${_timeOfDay().toUpperCase()}', style: TextStyle(color: AppColors.nidusLilac.withOpacity(.95), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2.1)),
                  const SizedBox(height: 8),
                  Text(
                    '${user?.fullName?.toString().split(' ').first ?? 'Traveler'},\nwhere to?',
                    style: const TextStyle(color: Colors.white, fontSize: 34, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: -1.2),
                  ),
                  const SizedBox(height: 22),
                  Material(
                    color: AppColors.nidusPaper,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      onTap: () => context.push('/nidus/request'),
                      borderRadius: BorderRadius.circular(22),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(color: AppColors.nidusLilacWash, borderRadius: BorderRadius.circular(15)),
                              child: const Icon(Icons.search_rounded, color: AppColors.primary, size: 25),
                            ),
                            const SizedBox(width: 13),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Set your destination', style: TextStyle(color: AppColors.nidusInk, fontWeight: FontWeight.w800, fontSize: 15)),
                                  SizedBox(height: 4),
                                  Text('Pickup, drop-off, and ride options', style: TextStyle(color: AppColors.nidusMuted, fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_rounded, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundAction(IconData icon, VoidCallback onTap) => Material(
        color: Colors.white.withOpacity(.13),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(width: 42, height: 42, child: Icon(icon, color: Colors.white, size: 21)),
        ),
      );

  Widget _buildSectionHeading(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 23, height: 1.1, letterSpacing: -.7, fontWeight: FontWeight.w800, color: AppColors.nidusInk)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.nidusMuted)),
        ],
      );

  Widget _buildNidusFeature(BuildContext context) => Material(
        color: AppColors.nidusLilacWash,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: () => context.push('/nidus/request'),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 19, 14, 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white.withOpacity(.8), borderRadius: BorderRadius.circular(30)), child: const Text('NIDUS  /  RIDES', style: TextStyle(color: AppColors.primaryDark, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2))),
                      const SizedBox(height: 16),
                      const Text('The city,\non your terms.', style: TextStyle(color: AppColors.nidusInk, fontSize: 25, height: 1.05, letterSpacing: -.7, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      const Text('Find a ride that fits your day.', style: TextStyle(color: AppColors.nidusMuted, fontSize: 12)),
                      const SizedBox(height: 17),
                      Container(width: 42, height: 42, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), child: const Icon(Icons.arrow_forward_rounded, color: Colors.white)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 112,
                  height: 150,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(width: 104, height: 104, decoration: BoxDecoration(color: Colors.white.withOpacity(.65), shape: BoxShape.circle)),
                      Transform.rotate(angle: -.22, child: const Icon(Icons.directions_car_filled_rounded, size: 88, color: AppColors.primary)),
                      Positioned(right: 2, top: 10, child: Container(width: 23, height: 23, decoration: const BoxDecoration(color: AppColors.nidusCoral, shape: BoxShape.circle), child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 15))),
                      Positioned(left: 0, bottom: 8, child: Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), boxShadow: [BoxShadow(color: AppColors.nidusInk.withOpacity(.08), blurRadius: 12, offset: const Offset(0, 5))]), child: const Icon(Icons.route_rounded, color: AppColors.primary, size: 22))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildServices(BuildContext context) {
    final services = <_ServiceItem>[
      _ServiceItem('Haven', 'Stays & hotels', Icons.hotel_rounded, AppColors.havenPurple, () => context.push('/haven/search'), '01'),
      _ServiceItem('Vorax', 'Food to your door', Icons.restaurant_rounded, AppColors.voraxOrange, () => context.push('/vorax/restaurants'), '02'),
      _ServiceItem('Logix', 'Move your cargo', Icons.local_shipping_rounded, AppColors.logixGreen, null, '03'),
      _ServiceItem('Corpus', 'Work travel', Icons.business_center_rounded, AppColors.corpusTeal, null, '04'),
    ];
    return Column(
      children: [
        for (var i = 0; i < services.length; i += 2) ...[
          Row(children: [Expanded(child: _serviceCard(services[i])), const SizedBox(width: 12), Expanded(child: _serviceCard(services[i + 1]))]),
          if (i == 0) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _serviceCard(_ServiceItem service) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: service.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 145),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.nidusLine)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: service.color.withOpacity(.11), borderRadius: BorderRadius.circular(14)), child: Icon(service.icon, color: service.color, size: 23)), const Spacer(), Text(service.index, style: TextStyle(color: service.color.withOpacity(.65), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1))]),
                const SizedBox(height: 18),
                Text(service.title, style: const TextStyle(color: AppColors.nidusInk, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(service.subtitle, style: const TextStyle(color: AppColors.nidusMuted, fontSize: 11.5)),
              ],
            ),
          ),
        ),
      );

  Widget _buildWalletShortcut(BuildContext context) => Material(
        color: AppColors.nidusInk,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () => context.goNamed(RouteNames.wallet),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
            child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.white.withOpacity(.10), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.nidusLilac, size: 23)), const SizedBox(width: 13), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Your NIDAW wallet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)), SizedBox(height: 4), Text('Manage your balance and payments', style: TextStyle(color: Color(0xFFC9C0D8), fontSize: 11.5))])), const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.nidusLilac, size: 17)]),
          ),
        ),
      );

  String _timeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  Widget _buildBottomNav(BuildContext context) => Container(
        decoration: BoxDecoration(color: Colors.white, border: const Border(top: BorderSide(color: AppColors.nidusLine)), boxShadow: [BoxShadow(color: AppColors.nidusInk.withOpacity(.04), blurRadius: 18, offset: const Offset(0, -5))]),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: 0,
            backgroundColor: Colors.white,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.nidusMuted,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            elevation: 0,
            onTap: (index) {
              switch (index) {
                case 1: context.push('/nidus/history'); break;
                case 3: context.push('/profile'); break;
                default: break;
              }
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), activeIcon: Icon(Icons.explore_rounded), label: 'Explore'),
              BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long_rounded), label: 'Trips'),
              BottomNavigationBarItem(icon: Icon(Icons.bookmark_border_rounded), activeIcon: Icon(Icons.bookmark_rounded), label: 'Saved'),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), activeIcon: Icon(Icons.person_rounded), label: 'Profile'),
            ],
          ),
        ),
      );
}

class _ServiceItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String index;

  const _ServiceItem(this.title, this.subtitle, this.icon, this.color, this.onTap, this.index);
}
