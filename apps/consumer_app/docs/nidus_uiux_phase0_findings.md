# Nidus UI/UX Remediation — Phase 0 Findings Sheet (Triage & Truth-Setting)

Date: 2026-11-01 · App: `apps/consumer_app` · Scope: `lib/features/nidus/**` + router + tests
Method: exhaustive grep/read of current tree. **Constraint: repo history is a single grafted commit**
(`7ff8aa7`, depth 1; `git log --all`=1, reflog=2, no stashes) — git blame cannot distinguish
"deleted vs rewired vs never wired". Triage below therefore relies on structural evidence in code.

## A. Ride-options event/state pair — VERDICT: NEVER WIRED (orphaned §2.6 path)

Evidence:
1. Zero references to `LoadRideOptions` / `RideOptionsLoaded` / `RideOptionsFailed` outside
   `ride_bloc.dart` across all of `lib/` and `test/`.
2. `RideTypeSelector` (the carousel) is mounted at `ride_request_page.dart:641` with ONLY
   `selectedType` + `onTypeSelected`. Its `options`, `loading`, `error`, `onRetry` params are
   never passed → widget always renders `_UnavailableState` ("Prices unavailable — set pickup and
   dropoff to load live fares.") with no retry callback.
3. The page instead dispatches `GetFareEstimate` (lines 647, 901, 994) and consumes
   `FareEstimateLoaded` (683, 1196) — a parallel single-estimate path.
4. `getRideOptionEstimates` (repository) has exactly one caller: `_onLoadRideOptions` (bloc:1609).
5. Related orphans in same family: `SelectRideOption` and `RideOptionSelectionChanged` events are
   registered (bloc:968-969) but **never dispatched from any UI**; the doc comment claims "the page
   mirrors it into its local selection" — no page does.
Conclusion for Phase 2: delete-vs-reconnect decision is unconstrained by history; reconnect is
feasible (widget already supports the full contract), delete requires keeping some reachable retry
affordance. Note: today's request-page failure UX is NOT broken — `RideError` (incl.
`ESTIMATE_FAILED`) renders inline via `_buildErrorMessage` (page:687).

## B. Doc-contract audit (`///` contracts vs implementation)

| Contract (location) | Claim | Status |
|---|---|---|
| `ride_bloc.dart:773` RideOptionsFailed | "carousel must render retryable 'Prices unavailable' strip" | **ORPHAN** — carousel exists but unwired; no retry ever fires |
| `ride_bloc.dart:196-200` LoadRideOptions | "emits RideOptionSelectionChanged so the page can update its own selection state" | **ORPHAN** — page never listens/dispatches |
| `ride_repository.dart:88-89` getRideOptionEstimates | "callers must render retryable 'Prices unavailable', never hardcoded cards" | Only caller is dead path → contract unreachable |
| `ride_type_selector.dart:4-13` widget doc | "renders honest retryable 'Prices unavailable' state" | PARTIAL — unavailability renders; **retry never available** (onRetry never supplied); empty-state copy says "pull to refresh" but request page has no RefreshIndicator |
| `ride_request_page.dart:32,184,1193,1568,1700` never-* docs | honest coords/spinner/null estimate/map fallback | CONFIRMED implemented |
| `pre_selfie_repository.dart:68,124` | verbatim reason display; not_sent distinction | CONFIRMED (sheet renders server reason) |
| `safety_widgets` / tracking §4.5 RideCheck, §4.6 price-extension, §4.1 AR triple-gate | as documented | CONFIRMED implemented |
| `receipt_pdf_document.dart:21` | callers surface honest error, never fake success toast | CONFIRMED |
| `chat_repository.dart:201` | "unavailable — retry", never fake data | CONFIRMED (chat_page has retry + optimistic bubbles) |
| `ride_repository.dart` honesty cluster (121,157-158,526-527,613,667,773,840,892,1815) | null≠zero, em-dash receipts, no fabricated ETA/photos | CONFIRMED — spot-checked stop_charge/receipt/ETA paths |

Net: 3 true orphan contracts (all in the §2.6 ride-options family) + 1 partial (selector retry).
Audit's "two orphans" undercounted slightly: `SelectRideOption`/`RideOptionSelectionChanged` are a
third dead event pair.

## C. Test coverage

- Nidus tests present: `test/features/nidus/data/ride_eta_dto_test.dart`,
  `test/features/nidus/presentation/ride_bloc_eta_test.dart` (ETA precedence/no-fabrication only).
- **No tests assert**: RideOptions* states/handler, SOS widget (`SosSlideToConfirm`), history
  fallback ("No rides found"). Grep over `test/` + `integration_test/`: zero hits.
- Implication: deleting the §2.6 path breaks no tests; reconnecting it needs new bloc+widget tests.

## D. Silent pop() on tracking — CONFIRMED REAL BUG (static proof; device run pending)

`ride_tracking_page.dart:336-349`: listener pops on ANY `RideError` whose `errorCode !=
'CANCEL_FAILED'`. Reachable emissions while tracking is mounted:
- `LOAD_FAILED` (bloc:1390) — e.g. refresh/status reload throws.
- `REQUEST_FAILED` (1370) / request-failure result (1323).
- `RATE_FAILED` (1540/1556/1561) — rating happens from post-ride surfaces sharing this bloc.
- `ESTIMATE_FAILED` (1584/1593) — a stale GetFareEstimate in flight resolves after transition.
RideBloc is app-scoped shared state, so any of these ejects the rider from live tracking with no
message. Not a timing artifact by construction. **Residual**: literal device/simulator reproduction
not performed in this environment (no Flutter run here) — mark verified-by-code, confirm on device
before shipping Phase 1.
Secondary finding: `NoDriversFound` also pops when price_extension flag off (line ~333) — that pop
is pre-§4.6 intended behavior per its doc comment; keep, but consider message.

## E. l10n coverage baseline (grep count of `context.l10n|l10n.` per file)

Localized: cancel_ride_sheet 24 · ride_tracking_page 18 · payment_method_selector 4 ·
ride_request_page 3 · ride_history_page 3 · rate_ride_sheet 2.
Zero (presentation): verify_driver_card, stop_charge_card, split_fare_sheet, safety_widgets,
ride_type_selector, promo_code_sheet, pre_selfie_capture_sheet, place_autocomplete_sheet,
location_permission_gate, location_input, in_app_notification_banner, driver_card,
approve_stop_sheet, safety_toolkit_page, receipt_detail_page, notification_inbox_page, chat_page,
ar_navigation_page. (Data/bloc/domain layers: 0 — expected.)
Baseline matches audit within ±2 (audit omitted location_permission_gate, approve_stop_sheet,
in_app_notification_banner from the zero list).

## F. New Phase-0 findings beyond the audit

1. **Ethiopic font risk (blocks Phase 3 exit criterion):** pubspec declares `Inter` from
   `assets/fonts/*.ttf`, but `assets/fonts/` DOES NOT EXIST in the repo (only assets/config,
   assets/images). Inter has no Ethiopic glyphs anyway; am/om rendering depends entirely on system
   fallback. Must resolve before claiming "font ships in bundle".
2. Audit item #8 (Navigator.push chat/receipt) CONFIRMED at tracking:552/567/581 and
   receipt_detail_page.dart:23, BUT RouteNames.chat / RouteNames.receipt do not exist yet —
   Phase 6 must add routes, not just switch calls.
3. Audit item #5 partially stale: driver_card DOES have tooltips on call/chat (lines 100,105);
   missing pieces are avatar semantics only (`Icons.person` silhouette at line 43 next to real
   selfie shown by verify_driver_card — violates its own :28 rule).
4. Audit item #4 partially stale: Semantics/tooltip appears in 11 presentation files (not 8), but
   still absent from safety_widgets.dart entirely — SOS slider has no gesture alternative. Confirmed.
5. History conflation CONFIRMED: default branch renders 'No rides found' for RideInitial/any
   non-matching state (ride_history_page.dart:90); error header hardcoded English (line 449).
6. Offline wiring CONFIRMED absent: zero refs to core/offline in features/nidus; RefreshIndicator
   only in notification_inbox_page:170 and split_fare_sheet:163.

## Verdict summary

- **Confirmed bugs**: silent-pop ejection (D); history false-empty + untranslated error (E.5);
  SOS accessibility gap (E.4); localization gaps incl. Safety Toolkit/SOS (E); unwired carousel
  retry affordance (A/B); missing fonts dir (F.1).
- **Stale docs**: §2.6 ride-options contract trio (A/B) — written for a UI that was never wired;
  selector's "pull to refresh" copy (no pull-to-refresh exists on request page).
- **Test gaps**: none of the above paths tested (C).
- **Not bugs**: NoDriversFound pop (documented kill-switch behavior); repository-layer honesty
  contracts (implemented); driver_card tooltips (already present).

Sign-off: triage complete against working tree at HEAD 7ff8aa7. Ready for Phase 1.
