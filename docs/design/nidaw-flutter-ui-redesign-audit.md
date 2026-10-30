# NIDAW Flutter UI Redesign — Audit and Implementation Notes

Date: 2026-10-29

## Direction

The consumer and driver applications share the NIDAW lavender/aubergine identity while preserving different information priorities: discovery and trip initiation for consumers; availability, incoming work, navigation, and earnings for drivers. Screens use warm paper surfaces, a soft lavender canvas, stronger typography, large rounded geometry, restrained coral accents, and clearer action hierarchy. Existing navigation and Bloc events remain the source of behavior.

## Implemented in this pass

### Consumer app

- Rebuilt `features/home/presentation/pages/home_page.dart` as a branded product hub with a dark aubergine/lavender hero, expressive route motif, prominent destination entry, dedicated Nidus feature panel, cross-product tiles, wallet shortcut, and simplified bottom navigation.
- Updated `core/theme/app_colors.dart` so Nidus's service color and shared gradients align with the lavender brand direction while retaining separate Haven, Vorax, Logix, and Corpus service colors.
- Refined `core/theme/app_theme.dart` card and control radii.
- Refined `features/home/presentation/widgets/service_card.dart` for the new surface, border, and typography language.

### Driver app

- Rebuilt `features/home/presentation/pages/driver_home_page.dart` into a map-first driver dashboard with floating brand/navigation controls, a prominent availability card, a bottom earnings panel, and compact performance indicators. Existing `DriverHomeBloc` events and route destinations are retained.
- Replaced the driver app palette in `core/theme/app_colors.dart` with the shared NIDAW lavender/aubergine system and preserved semantic status colors.
- Updated `core/theme/app_theme.dart` to align cards, controls, surfaces, and typography with the shared design language.

## Route and behavior notes

- Consumer product entry routes retained: `/nidus/request`, `/haven/search`, `/vorax/restaurants`, `/profile`, `/nidus/history`, `/nidus/notifications`, and the named wallet route.
- Logix and Corpus tiles are intentionally shown as non-interactive while their routes are not available in the inspected consumer router. This avoids routing to invented endpoints.
- Driver availability still dispatches `ToggleAvailability`; pending ride offers still dispatch `ClearPendingRideOffer` and navigate to `/ride/accept/:rideId`; menu destinations use existing routes.
- The redesigned home screens do not introduce new backend fields, endpoints, fake wallet values, or fake activity records.

## Remaining redesign audit

This is the first implementation slice, not a claim that every screen has been redesigned. The next pass should apply and validate the design system screen-by-screen across authentication/onboarding, ride request/tracking/history/safety/chat/receipts, driver acceptance/navigation/completion/chat, earnings/documents/profile/settings, and the Haven/Vorax/Logix/Corpus pages. Audit dialogs, bottom sheets, empty/error/loading states, route reachability, accessibility, and small-screen overflow as part of that pass.

## Validation

The Flutter and Dart SDKs were unavailable in the editing environment, so `flutter analyze`, formatter, and device builds could not be run. Source-level inspection and archive integrity checks are not substitutes for compiling and exercising both apps.
