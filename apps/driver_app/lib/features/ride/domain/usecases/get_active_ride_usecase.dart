import '../../data/repositories/ride_repository.dart';
import '../entities/active_ride.dart';

class GetActiveRideUseCase {
  final RideRepository _repository;

  GetActiveRideUseCase(this._repository);

  Future<ActiveRide?> execute() => _repository.getActiveRide();
}
