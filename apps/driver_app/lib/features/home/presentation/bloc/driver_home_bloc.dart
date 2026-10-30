import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/network/location_service.dart';
import '../../domain/entities/driver_stats.dart';
import '../../data/repositories/driver_home_repository.dart';
import '../../domain/usecases/get_driver_stats_usecase.dart';
import '../../domain/usecases/toggle_availability_usecase.dart';

// Events
abstract class DriverHomeEvent extends Equatable {
  const DriverHomeEvent();

  @override
  List<Object?> get props => [];
}

class LoadDriverStats extends DriverHomeEvent {
  const LoadDriverStats();
}

class ToggleAvailability extends DriverHomeEvent {
  final bool isOnline;

  const ToggleAvailability({required this.isOnline});

  @override
  List<Object?> get props => [isOnline];
}

class StartLocationTracking extends DriverHomeEvent {
  const StartLocationTracking();
}

class StopLocationTracking extends DriverHomeEvent {
  const StopLocationTracking();
}

class RideOfferReceived extends DriverHomeEvent {
  final String rideId;
  const RideOfferReceived({required this.rideId});
  @override
  List<Object?> get props => [rideId];
}

class ClearPendingRideOffer extends DriverHomeEvent {
  const ClearPendingRideOffer();
}

class LocationUpdated extends DriverHomeEvent {
  final Position position;

  const LocationUpdated({required this.position});

  @override
  List<Object?> get props => [position];
}

// States
abstract class DriverHomeState extends Equatable {
  const DriverHomeState();

  @override
  List<Object?> get props => [];
}

class DriverHomeInitial extends DriverHomeState {
  const DriverHomeInitial();
}

class DriverHomeLoading extends DriverHomeState {
  const DriverHomeLoading();
}

class DriverHomeLoaded extends DriverHomeState {
  final DriverStats stats;
  final bool isOnline;
  final bool isTracking;
  final bool isAvailabilityChanging;
  final Position? currentPosition;
  final String? pendingRideId;
  final String? message;

  const DriverHomeLoaded({
    required this.stats,
    required this.isOnline,
    required this.isTracking,
    this.isAvailabilityChanging = false,
    this.currentPosition,
    this.pendingRideId,
    this.message,
  });

  DriverHomeLoaded copyWith({
    DriverStats? stats,
    bool? isOnline,
    bool? isTracking,
    bool? isAvailabilityChanging,
    Position? currentPosition,
    String? pendingRideId,
    String? message,
    bool clearPendingRideId = false,
    bool clearMessage = false,
  }) {
    return DriverHomeLoaded(
      stats: stats ?? this.stats,
      isOnline: isOnline ?? this.isOnline,
      isTracking: isTracking ?? this.isTracking,
      isAvailabilityChanging: isAvailabilityChanging ?? this.isAvailabilityChanging,
      currentPosition: currentPosition ?? this.currentPosition,
      pendingRideId: clearPendingRideId ? null : pendingRideId ?? this.pendingRideId,
      message: clearMessage ? null : message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [stats, isOnline, isTracking, isAvailabilityChanging, currentPosition, pendingRideId, message];
}

class DriverHomeError extends DriverHomeState {
  final String message;

  const DriverHomeError({required this.message});

  @override
  List<Object?> get props => [message];
}

// BLoC
class DriverHomeBloc extends Bloc<DriverHomeEvent, DriverHomeState> {
  final GetDriverStatsUseCase _getDriverStatsUseCase;
  final DriverHomeRepository _driverHomeRepository;
  final ToggleAvailabilityUseCase _toggleAvailabilityUseCase;
  final LocationService _locationService;

  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<Map<String, dynamic>>? _rideRequestSubscription;
  String? _pendingRideId;
  bool _availabilityRequestInFlight = false;

  DriverHomeBloc({
    required GetDriverStatsUseCase getDriverStatsUseCase,
    required DriverHomeRepository driverHomeRepository,
    required ToggleAvailabilityUseCase toggleAvailabilityUseCase,
    required LocationService locationService,
  })  : _getDriverStatsUseCase = getDriverStatsUseCase,
        _driverHomeRepository = driverHomeRepository,
        _toggleAvailabilityUseCase = toggleAvailabilityUseCase,
        _locationService = locationService,
        super(const DriverHomeInitial()) {
    on<LoadDriverStats>(_onLoadDriverStats);
    on<ToggleAvailability>(_onToggleAvailability);
    on<StartLocationTracking>(_onStartLocationTracking);
    on<StopLocationTracking>(_onStopLocationTracking);
    on<LocationUpdated>(_onLocationUpdated);
    on<RideOfferReceived>(_onRideOfferReceived);
    on<ClearPendingRideOffer>(_onClearPendingRideOffer);
    _rideRequestSubscription = _driverHomeRepository.getRideRequests().listen((message) {
      final rideId = message['ride_id'];
      if (rideId is String && rideId.isNotEmpty) {
        add(RideOfferReceived(rideId: rideId));
      }
    });
  }

  Future<void> _onLoadDriverStats(
    LoadDriverStats event,
    Emitter<DriverHomeState> emit,
  ) async {
    final previous = state is DriverHomeLoaded ? state as DriverHomeLoaded : null;
    if (previous == null) emit(const DriverHomeLoading());

    try {
      final stats = await _getDriverStatsUseCase.execute();
      final current = state is DriverHomeLoaded ? state as DriverHomeLoaded : previous;
      if (current != null) {
        emit(current.copyWith(stats: stats, clearMessage: true));
      } else {
        emit(DriverHomeLoaded(
          stats: stats,
          isOnline: false,
          isTracking: false,
          pendingRideId: _pendingRideId,
        ));
      }
    } catch (e) {
      final current = state is DriverHomeLoaded ? state as DriverHomeLoaded : previous;
      if (current != null) {
        emit(current.copyWith(message: 'Could not refresh driver statistics. Check your connection and try again.'));
      } else {
        emit(DriverHomeError(message: e.toString()));
      }
    }
  }

  Future<void> _onToggleAvailability(
    ToggleAvailability event,
    Emitter<DriverHomeState> emit,
  ) async {
    if (_availabilityRequestInFlight) return;
    final previous = state is DriverHomeLoaded ? state as DriverHomeLoaded : null;
    if (previous == null || previous.isAvailabilityChanging || previous.isOnline == event.isOnline) return;

    _availabilityRequestInFlight = true;
    emit(previous.copyWith(isAvailabilityChanging: true, clearMessage: true));
    try {
      await _toggleAvailabilityUseCase.execute(event.isOnline);
      final current = state is DriverHomeLoaded ? state as DriverHomeLoaded : previous;
      if (event.isOnline) {
        emit(current.copyWith(isOnline: true, isAvailabilityChanging: true, clearMessage: true));
        add(const StartLocationTracking());
      } else {
        _pendingRideId = null;
        emit(current.copyWith(
          isOnline: false,
          isAvailabilityChanging: false,
          clearPendingRideId: true,
          clearMessage: true,
        ));
        add(const StopLocationTracking());
      }
    } catch (e) {
      final current = state is DriverHomeLoaded ? state as DriverHomeLoaded : previous;
      emit(current.copyWith(
        isAvailabilityChanging: false,
        message: 'Could not change availability. Your previous status is unchanged.',
      ));
    } finally {
      _availabilityRequestInFlight = false;
    }
  }

  Future<void> _onStartLocationTracking(
    StartLocationTracking event,
    Emitter<DriverHomeState> emit,
  ) async {
    try {
      // Re-entering online mode must not create a second location listener.
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      await _locationService.startTracking();
      _locationSubscription = _locationService.locationStream.listen(
        (position) => add(LocationUpdated(position: position)),
      );

      if (state is DriverHomeLoaded) {
        emit((state as DriverHomeLoaded).copyWith(isTracking: true, isAvailabilityChanging: false, clearMessage: true));
      }
    } catch (e) {
      // The server must not consider the driver available if this device cannot
      // publish a usable location stream.
      var reverted = true;
      try {
        await _toggleAvailabilityUseCase.execute(false);
      } catch (_) {
        reverted = false;
      }
      if (state is DriverHomeLoaded) {
        emit((state as DriverHomeLoaded).copyWith(
          isOnline: reverted ? false : (state as DriverHomeLoaded).isOnline,
          isTracking: false,
          isAvailabilityChanging: false,
          message: reverted
              ? 'Could not start location tracking. You have been set offline; check location permission and try again.'
              : 'Location tracking failed and your availability could not be reset. Check your connection and set yourself offline before continuing.',
        ));
      } else {
        emit(DriverHomeError(message: e.toString()));
      }
    }
  }

  Future<void> _onStopLocationTracking(
    StopLocationTracking event,
    Emitter<DriverHomeState> emit,
  ) async {
    try {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      await _locationService.stopTracking();
      if (state is DriverHomeLoaded) {
        emit((state as DriverHomeLoaded).copyWith(isTracking: false, isAvailabilityChanging: false, clearMessage: true));
      }
    } catch (e) {
      if (state is DriverHomeLoaded) {
        emit((state as DriverHomeLoaded).copyWith(
          isTracking: false,
          isAvailabilityChanging: false,
          message: 'Location tracking did not stop cleanly. Please check your connection and try again.',
        ));
      } else {
        emit(DriverHomeError(message: e.toString()));
      }
    }
  }

  Future<void> _onRideOfferReceived(
    RideOfferReceived event,
    Emitter<DriverHomeState> emit,
  ) async {
    final current = state;
    if (current is! DriverHomeLoaded || !current.isOnline || !current.isTracking) {
      return;
    }
    _pendingRideId = event.rideId;
    emit(current.copyWith(pendingRideId: event.rideId));
  }

  Future<void> _onClearPendingRideOffer(
    ClearPendingRideOffer event,
    Emitter<DriverHomeState> emit,
  ) async {
    _pendingRideId = null;
    if (state is DriverHomeLoaded) {
      emit((state as DriverHomeLoaded).copyWith(clearPendingRideId: true));
    }
  }

  Future<void> _onLocationUpdated(
    LocationUpdated event,
    Emitter<DriverHomeState> emit,
  ) async {
    final current = state;
    if (current is! DriverHomeLoaded || !current.isOnline || !current.isTracking) {
      return;
    }

    try {
      await _locationService.updateLocation(
        event.position.latitude,
        event.position.longitude,
        event.position.heading,
        event.position.speed,
      );
    } catch (_) {
      final latest = state;
      if (latest is DriverHomeLoaded && latest.isOnline && latest.isTracking) {
        emit(latest.copyWith(
          currentPosition: event.position,
          message: 'Your latest location could not be uploaded. Retrying with the next location update.',
        ));
      }
      return;
    }

    final latest = state;
    if (latest is DriverHomeLoaded && latest.isOnline && latest.isTracking) {
      emit(latest.copyWith(currentPosition: event.position, clearMessage: true));
    }
  }

  @override
  Future<void> close() async {
    await _locationSubscription?.cancel();
    await _rideRequestSubscription?.cancel();
    await _locationService.dispose();
    return super.close();
  }
}