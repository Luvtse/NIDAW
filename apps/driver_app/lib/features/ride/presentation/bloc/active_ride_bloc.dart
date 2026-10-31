import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/network/location_service.dart';
import '../../domain/entities/active_ride.dart';
import '../../data/repositories/ride_repository.dart';
import '../../domain/usecases/get_active_ride_usecase.dart';
import '../../domain/usecases/accept_ride_usecase.dart';
import '../../domain/usecases/start_ride_usecase.dart';
import '../../domain/usecases/complete_ride_usecase.dart';

// Events
abstract class ActiveRideEvent extends Equatable {
  const ActiveRideEvent();

  @override
  List<Object?> get props => [];
}

class AcceptRideRequested extends ActiveRideEvent {
  final String rideId;

  const AcceptRideRequested({required this.rideId});

  @override
  List<Object?> get props => [rideId];
}

class StartRideRequested extends ActiveRideEvent {
  final String rideId;

  const StartRideRequested({required this.rideId});

  @override
  List<Object?> get props => [rideId];
}

class CompleteRideRequested extends ActiveRideEvent {
  final String rideId;
  final double tipAmount;

  const CompleteRideRequested({
    required this.rideId,
    required this.tipAmount,
  });

  @override
  List<Object?> get props => [rideId, tipAmount];
}

class RideUpdated extends ActiveRideEvent {
  final ActiveRide ride;

  const RideUpdated({required this.ride});

  @override
  List<Object?> get props => [ride];
}

class ClearActiveRide extends ActiveRideEvent {
  const ClearActiveRide();
}

class RecoverActiveRideRequested extends ActiveRideEvent {
  const RecoverActiveRideRequested();
}

// States
abstract class ActiveRideState extends Equatable {
  const ActiveRideState();

  @override
  List<Object?> get props => [];
}

class ActiveRideInitial extends ActiveRideState {
  const ActiveRideInitial();
}

class ActiveRideLoading extends ActiveRideState {
  const ActiveRideLoading();
}

class ActiveRideLoaded extends ActiveRideState {
  final ActiveRide ride;

  const ActiveRideLoaded({required this.ride});

  @override
  List<Object?> get props => [ride];
}

class ActiveRideCompleted extends ActiveRideState {
  final ActiveRide ride;

  const ActiveRideCompleted({required this.ride});

  @override
  List<Object?> get props => [ride];
}

class ActiveRideError extends ActiveRideState {
  final String message;

  const ActiveRideError({required this.message});

  @override
  List<Object?> get props => [message];
}

// BLoC
class ActiveRideBloc extends Bloc<ActiveRideEvent, ActiveRideState> {
  final AcceptRideUseCase _acceptRideUseCase;
  final StartRideUseCase _startRideUseCase;
  final CompleteRideUseCase _completeRideUseCase;
  // ignore: unused_field — retained for trip-scoped location wiring (Phase 5 §4.3).
  final LocationService _locationService;
  final GetActiveRideUseCase _getActiveRideUseCase;
  final RideRepository _rideRepository;

  StreamSubscription<ActiveRide>? _rideUpdateSubscription;
  bool _completionInFlight = false;

  ActiveRideBloc({
    required AcceptRideUseCase acceptRideUseCase,
    required StartRideUseCase startRideUseCase,
    required CompleteRideUseCase completeRideUseCase,
    required LocationService locationService,
    required GetActiveRideUseCase getActiveRideUseCase,
    required RideRepository rideRepository,
  })  : _acceptRideUseCase = acceptRideUseCase,
        _startRideUseCase = startRideUseCase,
        _completeRideUseCase = completeRideUseCase,
        _locationService = locationService,
        _getActiveRideUseCase = getActiveRideUseCase,
        _rideRepository = rideRepository,
        super(const ActiveRideInitial()) {
    on<AcceptRideRequested>(_onAcceptRideRequested);
    on<StartRideRequested>(_onStartRideRequested);
    on<CompleteRideRequested>(_onCompleteRideRequested);
    on<RideUpdated>(_onRideUpdated);
    on<ClearActiveRide>(_onClearActiveRide);
    on<RecoverActiveRideRequested>(_onRecoverActiveRideRequested);
    _rideUpdateSubscription = _rideRepository.getRideUpdates().listen((ride) {
      add(RideUpdated(ride: ride));
    });
    add(const RecoverActiveRideRequested());
  }

  Future<void> _onRecoverActiveRideRequested(
    RecoverActiveRideRequested event,
    Emitter<ActiveRideState> emit,
  ) async {
    emit(const ActiveRideLoading());
    try {
      final ride = await _getActiveRideUseCase.execute();
      if (ride == null) {
        emit(const ActiveRideInitial());
      } else if (ride.isCompleted) {
        emit(ActiveRideCompleted(ride: ride));
      } else {
        emit(ActiveRideLoaded(ride: ride));
      }
    } catch (error) {
      emit(ActiveRideError(message: error.toString()));
    }
  }

  Future<void> _onAcceptRideRequested(
    AcceptRideRequested event,
    Emitter<ActiveRideState> emit,
  ) async {
    emit(const ActiveRideLoading());

    try {
      final ride = await _acceptRideUseCase.execute(event.rideId);
      emit(ActiveRideLoaded(ride: ride));
    } catch (e) {
      emit(ActiveRideError(message: e.toString()));
    }
  }

  Future<void> _onStartRideRequested(
    StartRideRequested event,
    Emitter<ActiveRideState> emit,
  ) async {
    emit(const ActiveRideLoading());

    try {
      final ride = await _startRideUseCase.execute(event.rideId);
      emit(ActiveRideLoaded(ride: ride));
    } catch (e) {
      emit(ActiveRideError(message: e.toString()));
    }
  }

  Future<void> _onCompleteRideRequested(
    CompleteRideRequested event,
    Emitter<ActiveRideState> emit,
  ) async {
    if (_completionInFlight) return;

    final currentState = state;
    if (currentState is ActiveRideCompleted &&
        currentState.ride.id == event.rideId) {
      return;
    }
    if (currentState is! ActiveRideLoaded ||
        currentState.ride.id != event.rideId ||
        !currentState.ride.isInProgress) {
      emit(const ActiveRideError(
        message: 'This ride is no longer active and cannot be completed.',
      ));
      return;
    }
    if (!event.tipAmount.isFinite || event.tipAmount < 0) {
      emit(const ActiveRideError(
        message: 'Enter a valid non-negative tip amount.',
      ));
      return;
    }

    _completionInFlight = true;
    emit(const ActiveRideLoading());
    try {
      final ride = await _completeRideUseCase.execute(
        event.rideId,
        event.tipAmount,
      );
      if (ride.id != event.rideId) {
        emit(const ActiveRideError(
          message: 'The server returned a different ride than requested.',
        ));
        return;
      }
      emit(ActiveRideCompleted(ride: ride));
    } catch (e) {
      emit(ActiveRideError(message: e.toString()));
    } finally {
      _completionInFlight = false;
    }
  }

  Future<void> _onRideUpdated(
    RideUpdated event,
    Emitter<ActiveRideState> emit,
  ) async {
    final currentRide = switch (state) {
      ActiveRideLoaded(:final ride) => ride,
      ActiveRideCompleted(:final ride) => ride,
      _ => null,
    };
    if (currentRide != null && currentRide.id != event.ride.id) return;
    if (event.ride.isCompleted) {
      emit(ActiveRideCompleted(ride: event.ride));
    } else {
      emit(ActiveRideLoaded(ride: event.ride));
    }
  }

  Future<void> _onClearActiveRide(
    ClearActiveRide event,
    Emitter<ActiveRideState> emit,
  ) async {
    emit(const ActiveRideInitial());
  }

  @override
  Future<void> close() async {
    await _rideUpdateSubscription?.cancel();
    return super.close();
  }
}