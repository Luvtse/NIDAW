import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/hotel.dart';

abstract class HotelRepository {
  Future<List<HotelSummary>> searchHotels({String city = '', int limit = 20});
  Future<HotelDetails> getHotel(String hotelId);
  Future<Map<String, dynamic>> createBooking({required String hotelId, required DateTime checkIn, required DateTime checkOut, required int guests, required int rooms});
  Future<List<Map<String, dynamic>>> listBookings({int limit = 20});
}

class HotelRepositoryImpl implements HotelRepository {
  final ApiClient apiClient;
  HotelRepositoryImpl({required this.apiClient});

  @override
  Future<List<HotelSummary>> searchHotels({String city = '', int limit = 20}) async {
    final response = await apiClient.get<Map<String, dynamic>>(
      AppConstants.hotelsEndpoint,
      queryParameters: {'city': city.trim(), 'limit': limit},
    );
    final data = response.data ?? const <String, dynamic>{};
    final items = data['items'];
    if (items is! List) return const [];
    return items.whereType<Map<String, dynamic>>().map(HotelSummary.fromJson).toList(growable: false);
  }

  @override
  Future<HotelDetails> getHotel(String hotelId) async {
    final response = await apiClient.get<Map<String, dynamic>>('${AppConstants.hotelsEndpoint}/$hotelId');
    final data = response.data;
    if (data == null) throw const FormatException('Hotel response was empty');
    return HotelDetails.fromJson(data);
  }

  @override
  Future<Map<String, dynamic>> createBooking({required String hotelId, required DateTime checkIn, required DateTime checkOut, required int guests, required int rooms}) async {
    final response = await apiClient.post<Map<String, dynamic>>(
      AppConstants.bookingsEndpoint,
      data: {
        'hotel_id': hotelId,
        'check_in': _dateOnly(checkIn),
        'check_out': _dateOnly(checkOut),
        'guests': guests,
        'rooms': rooms,
      },
    );
    return response.data ?? const <String, dynamic>{};
  }

  @override
  Future<List<Map<String, dynamic>>> listBookings({int limit = 20}) async {
    final response = await apiClient.get<Map<String, dynamic>>(AppConstants.bookingsEndpoint, queryParameters: {'limit': limit});
    final items = response.data?['items'];
    if (items is! List) return const [];
    return items.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  String _dateOnly(DateTime value) => '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
