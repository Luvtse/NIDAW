import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ServiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const ServiceCard({super.key, required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.nidusPaper,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.nidusLine)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withOpacity(.11), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color, size: 25)),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.nidusInk)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.nidusMuted)),
          ]),
        ),
      ),
    );
  }
}
