# NIDAW Flutter UI Redesign — Pass 15

Scope: consumer Nidus payment recovery and ride cancellation failure handling.

## Changes

- Retain the original `RequestRide` payload when a payment failure is emitted, so the recovery sheet can retry the actual booking instead of falling back to a generic exit.
- Preserve intermediate stops when retrying a failed payment with the same or a different payment rail.
- Keep the payment recovery sheet mounted while the wallet top-up sheet is displayed.
- Removed automatic ride submission after a fixed two-second delay following top-up initiation. The rider must explicitly retry after top-up confirmation, avoiding an unverified race between wallet settlement and ride creation.
- Cancellation failures now use a dedicated error code so the tracking screen shows recoverable feedback and remains available rather than navigating away as if the ride had reached a terminal state.

## Validation

- Source edits inspected manually.
- ZIP integrity check performed after packaging.
- Flutter/Dart SDK unavailable in this environment; analyzer, compilation, and device-level checks were not run.
