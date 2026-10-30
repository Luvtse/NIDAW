# NIDAW Flutter UI redesign — Pass 26

## Vorax restaurant discovery refresh correctness

- Added an explicit `RefreshRestaurants` BLoC event that invalidates the in-memory restaurant catalogue and requests fresh data from the existing repository.
- Wired pull-to-refresh to wait for a loaded or failure state rather than re-dispatching a search that only filters the cached catalogue.
- Kept the current query and category filters applied to the refreshed catalogue.
- Updated the search hint to match supported behavior: restaurant names and cuisine types are searchable; menu dishes are not searched by this page.

## Files changed

- `apps/consumer_app/lib/features/vorax/presentation/bloc/restaurant_bloc.dart`
- `apps/consumer_app/lib/features/vorax/presentation/pages/restaurant_list_page.dart`
- `docs/design/nidaw-flutter-ui-redesign-pass26.md`

## Validation limitations

Flutter/Dart SDK is unavailable in this environment, so `flutter analyze`, formatting, and runtime testing were not run. Source-level checks and ZIP integrity validation are performed separately.
