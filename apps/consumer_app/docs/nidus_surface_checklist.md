# Nidus Surface Checklist (Phase 7 — Convention Codification)

One page. Apply it to **the next file you touch**, not as a big-bang retrofit.
Every rule below exists because a real defect in this feature violated it during
the 2026-10-28 UI/UX audit; the "Proven by" column names the remediation phase
and the regression lock that now pins the behavior. A new Nidus surface that
breaks a rule without breaking its listed test is a review failure, not an
oversight.

Scope: `apps/consumer_app/lib/features/nidus/**` (pages, widgets, bloc, router
entries for `/nidus/*`). Receipt PDF (`receipt_pdf_document.dart`) stays
English-only **by decision** — rules 2 does not apply to the PDF document body.

## The checklist

1. **Route via `RouteNames` + GoRouter — never raw `Navigator.push(MaterialPageRoute(...))`.**
   Any surface a user can deep-link to or share must be a named GoRouter route
   (`RouteNames.rideChat`, `RouteNames.rideReceipt`, …) so flag gates, web URL
   sync, and deep links keep working. Modal confirm dialogs and the documented
   `SelfieComparisonView` push (verify_driver_card.dart:66) are the only
   sanctioned exceptions.
   *Proven by:* Phase 6 (`phase6_navigation_test.dart` source-convention guard;
   zero `push(MaterialPageRoute` under `lib/features/nidus` except that one).

2. **Wrap every user-facing string in `context.l10n` (ARB keys in en/am/om).**
   No hardcoded English literals in primary flows. Amharic must be Ethiopic
   script; Oromo must be Latin (Afaan Oromoo) — the l10n tests include a
   script-mixup regression guard. Run `tool/sync_l10n.py` after editing ARBs.
   Raw server messages are demoted to secondary detail; the localized string is
   primary (empty-string payloads must not render a blank error).
   *Proven by:* Phase 1 (safety strings), Phase 3 sweep (selector, driver_card,
   verify_driver_card, split_fare_sheet, promo_code_sheet l10n tests).

3. **Add `Semantics` labels / tooltips to custom gestures and icon-only actions.**
   Slide-to-confirm, call/chat buttons, filter chips, status icons,
   share/download actions — anything interactive without default a11y gets an
   explicit label resolvable through l10n.
   *Proven by:* Phase 1 (SOS slider), Phase 4 (`phase4_accessibility_test.dart`).

4. **Degrade avatars/placeholders honestly — no fake identity silhouettes.**
   When no photo is available, render initials + an explicit label (or the
   "photo missing" note), never `Icons.person` next to a real selfie. Same rule
   for any image decode failure. An explicit "selfie not sent" state icon
   (`Icons.person_off_outlined`) is blame-ours copy, not a fake silhouette.
   *Proven by:* Phase 4 (driver_card.dart:54 initials +
   `driverAvatarInitialsLabel`, aligned to verify_driver_card.dart's rule).

5. **Pre-load states render a skeleton, never an empty state.**
   `RideInitial` and any foreign/not-yet-loaded bloc state shows the loading
   skeleton; "No rides found" may only appear after a completed, successful
   load with zero rows. Loading failures say they failed — with retry — they
   never masquerade as empty.
   *Proven by:* Phase 1 (`history_fallback_test.dart`).

6. **Lists get `RefreshIndicator`; failing paths get a reachable retry.**
   Every Nidus list/history/inbox surface supports pull-to-refresh as the
   generic recovery gesture, complementing sheet-local retries. A documented
   contract that promises "Prices unavailable — retry" must actually wire
   `onRetry` (see the reconnected `LoadRideOptions` → `RideOptionsLoaded` /
   `RideOptionsFailed` carousel path).
   *Proven by:* Phase 3 reconnect (`ride_options_carousel_test.dart`),
   Phase 5 (`phase5_connectivity_test.dart`).

7. **Persistent banners for durable/destructive outcomes; snackbars only for transient confirmations.**
   Cancel fees, payment failures, silent-ejection risks, and reconnecting
   states use persistent banners with explicit user actions (stay/leave,
   acknowledge, retry). Never `pop()` a user out of tracking without an
   explanatory banner and their consent.
   *Proven by:* Phase 1 (silent pop fix), Phase 5 (reconnecting banner),
   Phase 6 (`ride_error_banner_test.dart`, `phase6_navigation_test.dart`).

8. **State honesty about connectivity.**
   Network/offline state resolves through `OfflineService` / the WS health
   signal — never guess "offline" on first frame, never fake "reconnected",
   and absent flags/services fail closed (absent ≠ ON). Active filters survive
   navigation and refresh round-trips.
   *Proven by:* Phase 5, Phase 6 (`ArNavigationGate` single source of truth).

9. **Doc contracts and implementation stay married.**
   If a `///` comment promises UI behavior ("carousel renders retryable strip"),
   either implement it or delete the comment in the same PR. Orphaned doc
   contracts were three of the audit's findings — reviewers should grep `///`
   claims in touched files against callers before approving.
   *Proven by:* Phase 0 findings sheet §B, Phase 3 resolution.

10. **Lock new conventions with a widget/bloc test in the same PR.**
    Each rule above has a matching test under
    `test/features/nidus/presentation/`; extend the nearest one rather than
    trusting prose. Note: CI runs `flutter analyze`/`flutter test` — local
    environments without the Flutter SDK cannot claim a pass.

## RideBloc split candidates (captured only — no action per roadmap)

`ride_bloc.dart` (~2,670 lines, 17 event/state classes) currently spans at
least four concerns and is a split candidate when next touched:

* **Tracking/telemetry:** WS subscription lifecycle, ETA timer, reconnect
  state (`_rideUpdateSubscription`, `_etaUpdateTimer`).
* **Safety/SOS:** countdown timers, ride-check anomaly detection, safety repo
  calls (`_sosCountdownTimer`, `_sosActive`, `SafetyRepository`).
* **Request/options/fare:** `LoadRideOptions`, `GetFareEstimate`, promo/split
  orchestration — natural `RideOptionsCubit` boundary.
* **History:** list/filter state — natural `RideHistoryCubit` boundary.

Recommendation for future phases: extract options and history first (smallest
blast radius, existing dedicated tests), keep SOS inside RideBloc until the
tracking socket abstraction is settled.

## Review usage

In PR templates/reviews for `features/nidus/**`, copy items 1–10 into the
review checklist and require the author to mark each "applies / n-a (why)".
Exit criterion for Phase 7: this file is referenced from the review process and
new Nidus surfaces conform on first pass.
