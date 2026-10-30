import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/hotel_repository.dart';
import '../../domain/entities/hotel.dart';

abstract class HotelSearchEvent extends Equatable {
  const HotelSearchEvent();
  @override
  List<Object?> get props => [];
}

class SearchHotels extends HotelSearchEvent {
  final String city;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  const SearchHotels({required this.city, required this.checkIn, required this.checkOut, required this.guests});
  @override
  List<Object?> get props => [city, checkIn, checkOut, guests];
}

abstract class HotelSearchState extends Equatable {
  const HotelSearchState();
  @override
  List<Object?> get props => [];
}
class HotelSearchInitial extends HotelSearchState { const HotelSearchInitial(); }
class HotelSearchLoading extends HotelSearchState { const HotelSearchLoading(); }
class HotelSearchLoaded extends HotelSearchState {
  final List<HotelSummary> hotels;
  const HotelSearchLoaded(this.hotels);
  @override
  List<Object?> get props => [hotels];
}
class HotelSearchFailure extends HotelSearchState {
  final String message;
  const HotelSearchFailure(this.message);
  @override
  List<Object?> get props => [message];
}

class HotelSearchBloc extends Bloc<HotelSearchEvent, HotelSearchState> {
  final HotelRepository hotelRepository;
  HotelSearchBloc({required this.hotelRepository}) : super(const HotelSearchInitial()) {
    on<SearchHotels>(_search);
  }

  Future<void> _search(SearchHotels event, Emitter<HotelSearchState> emit) async {
    if (!event.checkOut.isAfter(event.checkIn) || event.guests < 1) {
      emit(const HotelSearchFailure('Choose a valid check-in, check-out and guest count.'));
      return;
    }
    emit(const HotelSearchLoading());
    try {
      // Discovery does not guarantee availability; Haven verifies dated room
      // inventory atomically when a booking is submitted.
      final hotels = await hotelRepository.searchHotels(city: event.city);
      emit(HotelSearchLoaded(hotels));
    } catch (_) {
      emit(const HotelSearchFailure('Hotels could not be loaded. Check your connection and try again.'));
    }
  }
}
