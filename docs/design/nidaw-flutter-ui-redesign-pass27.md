# NIDAW Flutter UI Redesign — Pass 27

## Scope
Consumer Vorax order tracking: protect the tracking page when its order ID changes while the widget instance is reused.

## Changes
- Added `didUpdateWidget` handling so a changed order reference resets terminal/polling state and starts tracking the new order.
- Added request generations to ignore stale responses from an earlier order after the page switches to a new order.
- Centralized polling startup so the timer is cancelled before being replaced and on disposal.
- Captured the order ID at request start so the repository call is tied to the request generation.

## Validation limitations
Flutter/Dart SDK is unavailable in this environment, so analyzer, formatter, build, and device verification were not run. Source-level checks and archive integrity checks are performed separately.
