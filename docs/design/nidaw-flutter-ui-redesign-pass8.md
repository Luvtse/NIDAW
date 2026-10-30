# NIDAW Flutter UI Redesign — Pass 8

## Scope

This pass improves the consumer wallet's real data and recovery experience rather than changing the underlying payment contracts.

## Changes

- Keep the last successful wallet view available while top-up, dispute, refresh, and pagination events are in progress.
- Cache every successful `WalletLoaded` state, including loaded-to-loaded refresh and pagination emissions.
- Apply the balance returned by a successful top-up immediately to the cached wallet view when available.
- Trigger transaction pagination as the user approaches the end of the list, using the existing `LoadMoreTransactions` event.
- Prevent repeated pagination dispatches while a page request is in flight.
- Show a recoverable error banner over the cached wallet when a refresh or pagination request fails, instead of discarding the usable view.
- Add a designed empty state for accounts without transactions.
- Keep dispute auto-opening limited to once per page instance.

## Preserved behavior

- No endpoints, DTO fields, payment methods, or backend contracts were added.
- Existing wallet top-up, dispute, balance refresh, and transaction pagination events are reused.

## Validation

The modified source was inspected and the generated ZIP archive was integrity-checked. Flutter/Dart SDKs are unavailable in this environment, so `dart format`, `flutter analyze`, app builds, and device-level visual checks were not run.
