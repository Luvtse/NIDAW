import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/hotel_repository.dart';
import '../../domain/entities/hotel.dart';

class BookingPage extends StatefulWidget {
  final String hotelId;
  const BookingPage({super.key, required this.hotelId});
  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final _formKey = GlobalKey<FormState>();
  final _guestsController = TextEditingController(text: '2');
  final _roomsController = TextEditingController(text: '1');
  late Future<HotelDetails> _hotelFuture;
  DateTime _checkIn = DateTime.now().add(const Duration(days: 1));
  DateTime _checkOut = DateTime.now().add(const Duration(days: 3));
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _createdBooking;

  @override
  void initState() {
    super.initState();
    _hotelFuture = GetIt.I<HotelRepository>().getHotel(widget.hotelId);
  }

  @override
  void dispose() { _guestsController.dispose(); _roomsController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review your stay')),
    body: FutureBuilder<HotelDetails>(
      future: _hotelFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError || !snapshot.hasData) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Hotel details could not be loaded.'), TextButton(onPressed: () => setState(() => _hotelFuture = GetIt.I<HotelRepository>().getHotel(widget.hotelId)), child: const Text('Retry'))])));
        final hotel = snapshot.data!;
        if (_createdBooking != null) return _bookingCreated();
        final price = hotel.summary.pricePerNight;
        final nights = _checkOut.difference(_checkIn).inDays;
        final estimate = price != null && price > 0 && nights > 0 ? price * nights * (int.tryParse(_roomsController.text) ?? 1) : null;
        return Form(
          key: _formKey,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(hotel.summary.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(hotel.address ?? hotel.summary.city, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            Text(price != null && price > 0 ? '${hotel.summary.currency} ${price.toStringAsFixed(2)} per room / night' : 'Booking unavailable: no nightly price is configured.', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            _dateField('Check-in', _checkIn, (date) => setState(() { _checkIn = date; if (!_checkOut.isAfter(date)) _checkOut = date.add(const Duration(days: 1)); })),
            const SizedBox(height: 12),
            _dateField('Check-out', _checkOut, (date) => setState(() => _checkOut = date)),
            const SizedBox(height: 16),
            TextFormField(controller: _guestsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Guests', border: OutlineInputBorder()), validator: (value) { final n = int.tryParse(value ?? ''); return n == null || n < 1 || n > 20 ? 'Enter 1–20 guests' : null; }),
            const SizedBox(height: 12),
            TextFormField(controller: _roomsController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rooms', border: OutlineInputBorder()), validator: (value) { final n = int.tryParse(value ?? ''); return n == null || n < 1 || n > 10 ? 'Enter 1–10 rooms' : null; }),
            const SizedBox(height: 20),
            if (estimate != null) Text('Estimated total: ${hotel.summary.currency} ${estimate.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('The final amount and availability are verified by the server. A booking starts as pending; payment is not taken by this screen.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _isLoading || price == null || price <= 0 ? null : () => _submit(hotel), child: _isLoading ? const SizedBox(width: 20,height: 20,child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Request booking')),
          ]),
        );
      },
    ),
  );

  Widget _dateField(String label, DateTime date, ValueChanged<DateTime> onSelected) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(DateFormat.yMMMd().format(date)),
    trailing: const Icon(Icons.calendar_month),
    onTap: () async {
      final picked = await showDatePicker(context: context, initialDate: date.isBefore(DateTime.now()) ? DateTime.now() : date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
      if (picked != null) onSelected(picked);
    },
  );

  Future<void> _submit(HotelDetails hotel) async {
    if (!_formKey.currentState!.validate()) return;
    if (!_checkOut.isAfter(_checkIn)) { setState(() => _error = 'Check-out must be after check-in.'); return; }
    setState(() { _isLoading = true; _error = null; });
    try {
      final result = await GetIt.I<HotelRepository>().createBooking(
        hotelId: widget.hotelId, checkIn: _checkIn, checkOut: _checkOut,
        guests: int.parse(_guestsController.text), rooms: int.parse(_roomsController.text),
      );
      if (!mounted) return;
      setState(() => _createdBooking = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Booking was not created. The dates may have no configured room inventory, or the request could not be completed. Please review your dates and try again.');
    } finally { if (mounted) setState(() => _isLoading = false); }
  }

  Widget _bookingCreated() {
    final booking = _createdBooking!;
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.check_circle_outline, color: AppColors.success, size: 64),
      const SizedBox(height: 16),
      const Text('Booking request created', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('Status: ${booking['status'] ?? 'pending'}'),
      if (booking['id'] != null) SelectableText('Reference: ${booking['id']}'),
      const SizedBox(height: 16),
      const Text('Your booking is not confirmed until the appropriate confirmation workflow completes.', textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: () => context.go('/haven/search'), child: const Text('Back to hotels')),
    ])));
  }
}
