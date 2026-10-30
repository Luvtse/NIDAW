# NIDAW Flutter UI redesign — Pass 18

## Scope

Focused on driver navigation and ride-completion workflow for the Nidus driver experience.

## Changes

- Navigation presents the next relevant destination: pickup before the ride is in progress, drop-off once the ride is in progress.
- The driver's Complete Ride control opens the existing ride completion/summary page instead of submitting completion immediately with a hard-coded zero tip. The driver can review the server-reported fare and choose the existing optional tip flow before confirming.
- External navigation launch failures are caught and surfaced with an actionable message rather than allowing a platform launch exception to escape the UI.

## Validation

- Source changes were inspected and the resulting ZIP archive was integrity-checked.
- Flutter/Dart SDKs are unavailable in this environment; `dart format`, `flutter analyze`, compilation, and device-level checks were not run.
