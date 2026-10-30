# NIDAW Flutter UI redesign — Pass 13

## Scope
Focused on driver availability reliability for the driver app, staying within the Nidus/Vorax and driver-first scope.

## Changes
- Added explicit availability-transition state to the driver home bloc.
- Prevented duplicate availability requests while one is already in flight.
- Disabled the availability switch during the transition and displayed a compact progress indicator.
- Kept the transition pending until location tracking starts successfully when going online.
- If location tracking cannot start, attempted to revert server availability to offline and surfaced a truthful recovery message.
- Made the location tracking failure state distinguish between a successful server-side rollback and a failed rollback.

## Files changed
- `apps/driver_app/lib/features/home/presentation/bloc/driver_home_bloc.dart`
- `apps/driver_app/lib/features/home/presentation/pages/driver_home_page.dart`

## Validation
Source inspected and ZIP integrity checked. Flutter/Dart analyzer, compilation, and device-level verification were not available in this environment.
