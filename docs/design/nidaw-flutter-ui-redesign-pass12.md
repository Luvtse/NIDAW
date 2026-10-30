# NIDAW Flutter UI redesign — Pass 12

Scope remains limited to Nidus consumer, Vorax consumer, and the driver app.

## Nidus ride request reliability

- Added a pickup mutation sequence so delayed last-known/current GPS reads cannot overwrite a newer manual pin or selected place.
- Invalidated pending reverse-geocoding when the rider manually drags the pickup pin or selects a pickup suggestion, preventing an old lookup from replacing the selected address.
- Cleared the location-loading indicator when a manual pickup choice supersedes a pending GPS read.
- Added a local submission guard to prevent duplicate ride-request dispatches before the bloc's loading state rebuilds the button.
- Releases the submission guard on known request failure/no-driver/payment-failure states.

## Vorax restaurant discovery

- Once restaurant data is loaded, search now filters the in-memory catalogue without showing a full-page loading spinner on each keystroke.
- Initial load and load-failure behavior remain repository-backed and unchanged.

## Validation

- Source-level review and archive integrity checks only.
- Flutter/Dart SDK is unavailable in this environment; `dart format`, `flutter analyze`, builds, and device-level checks have not been run.
