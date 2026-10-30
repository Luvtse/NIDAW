# NIDAW Flutter UI Redesign — Pass 19

## Scope

Focused on Vorax consumer order tracking and its status/recovery states.

## Changes

- Normalized server-provided order statuses defensively, including non-string or empty values.
- Unified terminal-status detection for polling and rendering, including cancellation, failure, rejection, and completed variants.
- Stopped periodic polling when a terminal status is received while preserving explicit manual refresh.
- Added a clear fallback when the server returns a status this client does not yet recognize, instead of silently showing no journey or explanation.
- Preserved the order reference and existing server-provided tracking data.

## Validation

- Reviewed the changed source and checked archive integrity.
- Flutter/Dart formatting, analysis, compilation, and device testing were not run because the SDK is unavailable in this environment.
