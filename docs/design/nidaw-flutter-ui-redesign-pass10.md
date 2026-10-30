# NIDAW Flutter UI redesign — Pass 10

## Scope

This pass focuses on live Nidus ride tracking and driver chat reliability. It stays within existing service contracts and does not add backend endpoints or DTO fields.

## Implemented

- Converted ride WebSocket status payloads into `RideBloc` events before changing state. The stream callback no longer tries to use an `Emitter` after the subscription handler has completed.
- Tracked the active ride subscription ID and ignored late updates for a different ride, preventing stale WebSocket messages from changing the current ride state.
- Made unsubscribe events ignore stale ride IDs instead of accidentally cancelling a newer ride's subscription.
- Unsubscribed from ride updates when the consumer tracking page is disposed, while retaining the bloc reference needed for safe cleanup.
- Guarded driver chat history polling against overlapping requests so slow responses do not stack up every polling interval.

## Files changed

- `apps/consumer_app/lib/features/nidus/presentation/bloc/ride_bloc.dart`
- `apps/consumer_app/lib/features/nidus/presentation/pages/ride_tracking_page.dart`
- `apps/driver_app/lib/features/ride/presentation/pages/driver_chat_page.dart`
- `docs/design/nidaw-flutter-ui-redesign-pass10.md`

## Validation

- Inspected the modified event registration, subscription lifecycle, and polling cleanup paths.
- Flutter/Dart SDK is not available in this environment; analyzer, builds, and device tests remain outstanding.
- No tests, endpoints, or DTO fields were added.
