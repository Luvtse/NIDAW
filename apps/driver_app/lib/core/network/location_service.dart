import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Core location service (Phase A/A10).
///
/// Wraps the `geolocator` plugin and exposes a single stream of positions to
/// the app while forwarding each fix to the backend so riders/dispatch can
/// track the driver. Blocks that depend on this service:
///   - features/home/presentation/bloc/driver_home_bloc.dart
///   - features/ride/presentation/bloc/active_ride_bloc.dart
///   - core/di/injection.dart
class LocationService {
  // geolocator's LocationSettings.distanceFilter is an int (meters).
  static const int _distanceFilterMeters = 20;
  static const Duration _timeInterval = Duration(seconds: 5);

  StreamSubscription<Position>? _subscription;
  final Future<void> Function(double lat, double lng, double heading, double speed)?
      onLocationUpdate;
  final StreamController<Position> _controller = StreamController.broadcast();

  LocationService({this.onLocationUpdate});

  /// Broadcast stream of driver positions while tracking is active.
  Stream<Position> get locationStream => _controller.stream;

  bool get isTracking => _subscription != null;

  /// Request permissions and start streaming GPS fixes.
  ///
  /// Phase 5 (§4.3/§5.2): callers must only invoke this when the driver
  /// state machine permits collection (server-confirmed online OR an active
  /// trip). The startup coordinator enforces that gate via
  /// `DriverStartupSnapshot.trackingPermitted`; this service stays focused on
  /// the mechanics (permissions, stream, disposal) and remains independent of
  /// map rendering and screen startup.
  Future<void> startTracking() async {
    if (_subscription != null) return;

    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled on this device');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }

    _subscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        timeLimit: _timeInterval * 12,
      ),
    ).listen(
      (position) {
        if (!_controller.isClosed) _controller.add(position);
      },
      onError: (Object error) {
        if (!_controller.isClosed) _controller.addError(error);
      },
    );
  }

  /// Stop streaming GPS fixes (keeps the service reusable).
  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Push a position fix to the backend through the configured repository callback.
  Future<void> updateLocation(
    double lat,
    double lng,
    double heading,
    double speed,
  ) async {
    final update = onLocationUpdate;
    if (update == null) {
      throw StateError('Driver location upload is not configured');
    }
    await update(lat, lng, heading, speed);
  }

  /// Release all resources. After dispose the instance must not be reused.
  Future<void> dispose() async {
    await stopTracking();
    await _controller.close();
  }
}
