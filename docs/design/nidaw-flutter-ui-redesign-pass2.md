# NIDAW Flutter UI Redesign — Pass 2

## Scope

This pass extends the lavender / aubergine / warm-paper visual system beyond the home screens into authentication, account, ride lifecycle, safety, wallet, driver earnings, documents, and vehicle/profile areas. It intentionally preserves existing page widgets, BLoC events, route names, form controllers, and domain interactions.

## Visual system

- Primary: lavender `#7658D6`.
- Ink: aubergine `#21172F`.
- Canvas: warm lavender-white `#F7F4FC`.
- Surface: `#FFFEFF`.
- Supporting accent: restrained coral `#E47D70`.
- Use clear page titles, restrained app-bar elevation, open canvas, consistent horizontal spacing, and high-contrast action states.

## Pass 2 coverage

### Consumer
- Registration
- Ride history
- Safety toolkit
- Profile and settings

### Driver
- Login, registration and onboarding
- Ride navigation and completion
- Earnings overview and details
- Driver profile, vehicle information and documents

## Preservation constraints

- No new endpoints, data fields, or mocked business states were introduced.
- Existing BLoC/event wiring and GoRouter route identifiers were left intact.
- Existing UI states and actions remain owned by the original feature implementations.

## Validation limitations

The source archive was inspected and edited. ZIP integrity and source-level checks can be performed in this environment, but Flutter/Dart analysis and device builds require an installed Flutter SDK and should be run before merging.

## Remaining redesign scope

A complete screen-by-screen visual QA pass remains necessary for consumer hotel, food, freight and corporate flows; ride tracking and chat; receipts and notifications; legal/consent flows; driver chat; and all dialogs, loading states, empty states, errors, and responsive layouts. This pass is an incremental redesign, not a claim that every screen is complete.
