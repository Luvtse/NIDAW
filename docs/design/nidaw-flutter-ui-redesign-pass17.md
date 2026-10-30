# NIDAW Flutter UI Redesign — Pass 17

## Scope

This pass stays within the consumer Nidus/Vorax and driver-app priority.

## Changes

- Active-ride recovery now emits a loading state while the repository lookup is in progress, separating the lookup from a confirmed no-active-ride result.
- Driver navigation and ride completion now present explicit retryable empty states instead of showing an indefinite spinner when no active ride exists.
- Vorax order tracking continues to stop automatic polling for terminal orders, while allowing the rider to manually refresh a terminal order to verify the latest server status.

## Validation

The changed source was inspected and the archive integrity was checked. Flutter/Dart formatting, analysis, builds, and device-level verification were not available in this environment.
