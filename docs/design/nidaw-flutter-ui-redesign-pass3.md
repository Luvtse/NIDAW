# NIDAW Flutter UI Redesign — Pass 3

## Scope

This pass continues the consumer-app visual redesign for the cross-product experiences that were still using generic surfaces: Haven hotel search/detail/booking, Vorax restaurant discovery/menu/order tracking, Logix shipment tracking, Corpus corporate travel dashboard, Nidus notifications, and trip receipts.

## Changes

- Haven search now uses the shared app canvas, a spacious rounded search surface, a subtle border, and restrained elevation. The search remains driven by the existing `HotelSearchBloc`.
- Haven detail and booking page titles better communicate the current task without changing booking behavior.
- Vorax restaurant discovery has a clearer editorial title and app canvas. Menu uses a clearer page title and a separated floating checkout footer.
- Vorax order tracking uses task-oriented copy while retaining server-provided order status and ETA behavior.
- Logix tracking receives a lavender map-surface treatment, rounded status overlay, and improved page spacing. Existing static/sample shipment details remain as they were and must not be mistaken for live backend data.
- Corpus dashboard receives the shared canvas, revised heading, spacing, and more rounded company header. Existing sample company/KPI values remain unchanged and must be replaced with verified data before production use.
- Nidus notification and receipt titles are clarified; data-loading, pagination, receipt actions, and notification routing are unchanged.

## Files touched

- `apps/consumer_app/lib/features/haven/presentation/pages/hotel_search_page.dart`
- `apps/consumer_app/lib/features/haven/presentation/pages/hotel_detail_page.dart`
- `apps/consumer_app/lib/features/haven/presentation/pages/booking_page.dart`
- `apps/consumer_app/lib/features/vorax/presentation/pages/restaurant_list_page.dart`
- `apps/consumer_app/lib/features/vorax/presentation/pages/menu_page.dart`
- `apps/consumer_app/lib/features/vorax/presentation/pages/order_tracking_page.dart`
- `apps/consumer_app/lib/features/logix/presentation/pages/shipment_tracking_page.dart`
- `apps/consumer_app/lib/features/corpus/presentation/pages/corporate_dashboard_page.dart`
- `apps/consumer_app/lib/features/nidus/presentation/pages/notification_inbox_page.dart`
- `apps/consumer_app/lib/features/nidus/presentation/pages/receipt_detail_page.dart`

## Validation

The source edits were inspected after patching. Flutter and Dart executables are not available in this environment, so `dart format`, `flutter analyze`, automated tests, and device builds have not been run. A local Flutter validation pass is required before treating this as production-ready.
