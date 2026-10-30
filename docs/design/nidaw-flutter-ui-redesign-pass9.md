# NIDAW Flutter UI redesign — Pass 9

## Scope

This pass continues the consumer Nidus/Vorax and driver-app sweep. It prioritizes real controls, recovery states, and a missing Vorax order-history screen rather than changing backend contracts.

## Implemented

- Vorax restaurant discovery now exposes a working sort sheet for recommended order, rating, delivery time, and delivery fee; the current sort is visible and removable.
- Restaurant discovery now has clearer initial, empty, failure, retry, and pull-to-refresh states. Refresh preserves the active search query, and search can be cleared directly.
- Vorax menu now handles cart items that disappear or become unavailable while the menu is refreshed, removes stale cart entries, and avoids calculating a cart total from a missing item. Empty category results include a route back to all dishes.
- Added a Vorax order-history page backed by the existing `RestaurantRepository.listOrders()` method and existing orders endpoint. It supports refresh, empty/error states, and opens the existing order-tracking route when an order ID is available.
- Vorax order tracking now refreshes periodically while an order is active, presents a status journey for recognized server statuses, retains manual refresh and recovery, and explicitly avoids fabricating a driver location.
- Fixed duplicate `padding` named arguments in driver login, registration, and onboarding pages.
- Replaced the inert driver password-recovery control with an honest explanatory dialog; no password-recovery endpoint was invented.
- Removed the driver-home notification shortcut that only displayed an unavailable message, instead of presenting it as a working feature.

## Files changed

- `apps/consumer_app/lib/features/vorax/presentation/pages/restaurant_list_page.dart`
- `apps/consumer_app/lib/features/vorax/presentation/pages/menu_page.dart`
- `apps/consumer_app/lib/features/vorax/presentation/pages/order_tracking_page.dart`
- `apps/consumer_app/lib/features/vorax/presentation/pages/order_history_page.dart` (new)
- `apps/consumer_app/lib/core/router/app_router.dart`
- `apps/driver_app/lib/features/auth/presentation/pages/login_page.dart`
- `apps/driver_app/lib/features/auth/presentation/pages/register_page.dart`
- `apps/driver_app/lib/features/auth/presentation/pages/onboarding_page.dart`
- `apps/driver_app/lib/features/home/presentation/pages/driver_home_page.dart`

## Validation

- Source-level review and targeted duplicate-padding scan completed.
- ZIP integrity check performed after packaging.
- Flutter/Dart SDK is not available in this environment; `dart format`, `flutter analyze`, builds, and device visual checks could not be run.
- No tests, backend endpoints, or DTO fields were added.
