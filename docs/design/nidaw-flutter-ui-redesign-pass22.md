# NIDAW Flutter UI / workflow pass 22

## Scope
Driver app availability, location publishing, and incoming ride-offer state handling.

## Changes
- Ignore queued location updates unless the current driver state is both online and actively tracking.
- Recheck online/tracking state before emitting location upload success or failure feedback, avoiding stale updates from an event that finishes after the driver goes offline.
- Accept incoming ride offers only after the driver home state is loaded, online, and tracking.
- Clear the locally pending ride offer when the driver successfully switches offline.

## Files changed
- `apps/driver_app/lib/features/home/presentation/bloc/driver_home_bloc.dart`
- `docs/design/nidaw-flutter-ui-redesign-pass22.md`

## Validation
Source was inspected after edits. Flutter/Dart SDK is not available in this environment, so analyzer, formatter, build, and runtime validation could not be run.
