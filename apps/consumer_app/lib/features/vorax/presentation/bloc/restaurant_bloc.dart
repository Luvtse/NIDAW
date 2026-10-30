import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/restaurant_repository.dart';
import '../../domain/entities/restaurant.dart';

abstract class RestaurantEvent extends Equatable {
  const RestaurantEvent();
  @override
  List<Object?> get props => [];
}
class SearchRestaurants extends RestaurantEvent {
  final String query;
  const SearchRestaurants(this.query);
  @override
  List<Object?> get props => [query];
}
class FilterByCategory extends RestaurantEvent {
  final String category;
  const FilterByCategory(this.category);
  @override
  List<Object?> get props => [category];
}
class RefreshRestaurants extends RestaurantEvent {
  const RefreshRestaurants();
}

abstract class RestaurantState extends Equatable {
  const RestaurantState();
  @override
  List<Object?> get props => [];
}
class RestaurantInitial extends RestaurantState { const RestaurantInitial(); }
class RestaurantLoading extends RestaurantState { const RestaurantLoading(); }
class RestaurantLoaded extends RestaurantState {
  final List<RestaurantSummary> restaurants;
  const RestaurantLoaded(this.restaurants);
  @override
  List<Object?> get props => [restaurants];
}
class RestaurantFailure extends RestaurantState {
  final String message;
  const RestaurantFailure(this.message);
  @override
  List<Object?> get props => [message];
}

class RestaurantBloc extends Bloc<RestaurantEvent, RestaurantState> {
  final RestaurantRepository restaurantRepository;
  List<RestaurantSummary> _all = const [];
  Future<List<RestaurantSummary>>? _loadFuture;
  String _query = '';
  String _category = 'All';

  RestaurantBloc({required this.restaurantRepository}) : super(const RestaurantInitial()) {
    on<SearchRestaurants>(_search);
    on<FilterByCategory>(_filter);
    on<RefreshRestaurants>(_refresh);
  }

  Future<void> _search(SearchRestaurants event, Emitter<RestaurantState> emit) async {
    _query = event.query.trim();
    // Once the catalogue is in memory, search is a local operation. Keep the
    // existing results on screen instead of flashing a full-page spinner for
    // every keystroke.
    if (_all.isNotEmpty) {
      emit(RestaurantLoaded(_filtered()));
      return;
    }
    emit(const RestaurantLoading());
    try {
      _loadFuture ??= restaurantRepository.listRestaurants();
      _all = await _loadFuture!;
      emit(RestaurantLoaded(_filtered()));
    } catch (_) {
      _loadFuture = null;
      emit(const RestaurantFailure('Restaurants could not be loaded. Check your connection and try again.'));
    }
  }

  Future<void> _refresh(RefreshRestaurants event, Emitter<RestaurantState> emit) async {
    _loadFuture = null;
    _all = const [];
    emit(const RestaurantLoading());
    try {
      _loadFuture = restaurantRepository.listRestaurants();
      _all = await _loadFuture!;
      emit(RestaurantLoaded(_filtered()));
    } catch (_) {
      _loadFuture = null;
      emit(const RestaurantFailure('Restaurants could not be refreshed. Check your connection and try again.'));
    }
  }

  void _filter(FilterByCategory event, Emitter<RestaurantState> emit) {
    _category = event.category;
    if (_all.isEmpty) {
      add(const SearchRestaurants(''));
      return;
    }
    emit(RestaurantLoaded(_filtered()));
  }

  List<RestaurantSummary> _filtered() => _all.where((restaurant) {
    final queryMatch = _query.isEmpty || restaurant.name.toLowerCase().contains(_query.toLowerCase()) || restaurant.cuisineType.toLowerCase().contains(_query.toLowerCase());
    final categoryMatch = _category == 'All' || restaurant.cuisineType.toLowerCase().contains(_category.toLowerCase());
    return queryMatch && categoryMatch;
  }).toList(growable: false);
}
