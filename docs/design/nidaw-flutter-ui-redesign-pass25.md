# NIDAW Flutter UI redesign — Pass 25

## Scope
Consumer Nidus ride-cancellation request safety.

## Changes
- Added a per-ride in-flight cancellation guard in `RideBloc` so rapid repeated cancellation events cannot trigger concurrent cancellation requests for the same ride.
- Rejects blank ride identifiers before starting a request and trims the identifier used for request/stream-unsubscribe operations.
- Releases the guard in `finally`, including success, API errors, unexpected exceptions, and early returns from the result handling.
- Preserves the existing repository method, cancellation reason, server-provided fee/currency, and current state transitions; no endpoint or DTO was added.

## Validation limits
Source-level checks and ZIP integrity are performed for this pass. Flutter/Dart analysis, compilation, and device testing are not available in the current environment.
