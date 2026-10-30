import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/hotel_repository.dart';
import '../../domain/entities/hotel.dart';

class HotelDetailPage extends StatefulWidget {
  final String hotelId;
  const HotelDetailPage({super.key, required this.hotelId});
  @override
  State<HotelDetailPage> createState() => _HotelDetailPageState();
}

class _HotelDetailPageState extends State<HotelDetailPage> {
  late Future<HotelDetails> _hotelFuture;
  @override
  void initState() {
    super.initState();
    _hotelFuture = GetIt.I<HotelRepository>().getHotel(widget.hotelId);
  }

  void _reload() => setState(() => _hotelFuture = GetIt.I<HotelRepository>().getHotel(widget.hotelId));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Your stay')),
    body: FutureBuilder<HotelDetails>(
      future: _hotelFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError || !snapshot.hasData) return _loadError();
        final hotel = snapshot.data!;
        final summary = hotel.summary;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: hotel.images.isNotEmpty
                ? Image.network(hotel.images.first, height: 230, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _imageFallback())
                : SizedBox(height: 180, child: _imageFallback()),
            ),
            const SizedBox(height: 20),
            Text(summary.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text([summary.city, hotel.address].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · '), style: const TextStyle(color: Colors.black54)),
            if (summary.starRating > 0) ...[
              const SizedBox(height: 12),
              Row(children: List.generate(summary.starRating.clamp(0, 5).toInt(), (_) => const Icon(Icons.star, color: Colors.amber))),
            ],
            const SizedBox(height: 20),
            Text(hotel.description?.trim().isNotEmpty == true ? hotel.description! : 'No description is available for this property.', style: const TextStyle(height: 1.5)),
            const SizedBox(height: 20),
            if (hotel.amenities.isNotEmpty) ...[
              const Text('Amenities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: hotel.amenities.map((item) => Chip(label: Text(item))).toList()),
              const SizedBox(height: 20),
            ],
            Text(
              summary.pricePerNight != null && summary.pricePerNight! > 0
                ? '${summary.currency} ${summary.pricePerNight!.toStringAsFixed(2)} per night'
                : 'Price unavailable',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: summary.pricePerNight != null && summary.pricePerNight! > 0 ? () => context.push('/haven/booking/${summary.id}') : null,
              child: const Text('Continue to booking'),
            ),
          ],
        );
      },
    ),
  );

  Widget _loadError() => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.hotel_outlined, size: 48),
      const SizedBox(height: 12),
      const Text('Hotel details could not be loaded.', textAlign: TextAlign.center),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: _reload, child: const Text('Try again')),
    ]),
  ));

  Widget _imageFallback() => Container(color: Colors.grey.shade200, alignment: Alignment.center, child: const Icon(Icons.hotel, size: 64, color: Colors.grey));
}
