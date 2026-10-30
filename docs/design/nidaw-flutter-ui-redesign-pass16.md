# NIDAW Flutter UI redesign — Pass 16

## Scope
Driver ride acceptance and active-ride state handling, within the Nidus/driver priority scope.

## Changes
- Injected the existing `RideRepository` into `ActiveRideBloc`, matching its existing WebSocket ride-update subscription and the dependency-injection registration.
- Ignored ride-update messages for a different ride while a ride is already active or completed, preventing unrelated updates from replacing the current ride state.
- Started the offer countdown only after the requested offer has loaded successfully.
- Prevented repeated accept taps and dismiss actions while ride acceptance is in progress.
- Paused the offer timer while an acceptance request is pending and resumed the remaining countdown after a recoverable failure.
- Added a retry action when the ride offer cannot be loaded.

## Validation
- ZIP integrity and source delimiter checks performed.
- Flutter/Dart SDK was not available in this environment, so `dart format`, `flutter analyze`, builds, and device-level tests could not be run.
