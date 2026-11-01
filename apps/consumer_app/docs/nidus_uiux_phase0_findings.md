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

---

## Addendum — Phase 3 (Dead Code Resolution) status update

**Decision: RECONNECT (retain), not delete.** Verified against the working tree:

- `LoadRideOptions` is dispatched from `ride_request_page.dart` (`_loadRideOptions`, wired to
  route changes, option selection, and the retry strip's `onRetry`).
- `RideOptionsLoaded` / `RideOptionsFailed` are handled by the bloc and consumed by the page;
  the carousel renders server-driven cards and the localized degraded strip.
- Contract locked by `test/features/nidus/presentation/ride_options_carousel_test.dart` (bloc-level).
- Exit criterion "failing estimate path has a user-reachable retry" MET: `_UnavailableState` strip
  shows localized headline (`requestOptionsPricesUnavailable`) + `commonRetry` action; raw server
  message demoted to secondary detail.

**Section A/B verdict superseded:** the §2.6 doc contract now HAS implementation (was "never wired").

**Phase 3 localization follow-through (selector):**
- All six English literals removed from `ride_type_selector.dart` ('CHOSEN', 'ETA unavailable',
  'Capacity not provided', 'Unavailable', 'N seats', 'N min away'); replaced with new ARB keys
  `requestOption*` in en/am/om, compiled into the committed catalogs via `tool/sync_l10n.py`.
- `RideOptionEstimate.etaMinutes` made nullable — omitted server ETA renders localized
  "ETA unavailable", never fabricated "0 min away"; real 0 renders the =0 plural case.
- Widget-level l10n test added: `test/features/nidus/presentation/ride_type_selector_l10n_test.dart`.
- Amharic mojibake fixed in `app_am.arb` + generated catalog: `እየመᣣ ል።` → `እየመጣ ነው`; stray
  sentence-final `።` removed from the other-case template.

**Session-5 verification pass (static):**
- `tool/sync_l10n.py` re-run: "Catalog already in sync with ARB files; nothing to do" — proves
  ARB↔catalog consistency for all three locales (en/am/om), including the fixed Amharic plural.
- Grep sweep of `ride_type_selector.dart`: zero remaining user-facing English literals; all card
  strings resolve via `context.l10n.requestOption*`.
- All `RideOptionEstimate` constructor call sites audited for the nullable-`etaMinutes` change:
  only `fromJson`, the two test helpers (`ride_options_carousel_test.dart` passes `etaMinutes: 5`;
  the l10n test uses a nullable helper) — no positional-arg or non-null-dependent callers exist.
- Test fix applied: the English-card case asserted `'4 seats'`-style singular/plural strings for
  cards that don't render them (premium card's seat text is clipped by the fixed-height column);
  replaced with capacity-unknown assertions matching the actual widget layout.

**Session-6 sweep progress (driver_card.dart):**
- `driver_card.dart` migrated to catalog strings: the three remaining English literals
  ('Call driver using masked number', 'Chat with driver', 'min') replaced with new ARB keys
  `driverCallTooltip` / `driverChatTooltip` / `driverEtaMinutesUnit` in en/am/om, compiled via
  `tool/sync_l10n.py` ("Added 3 members", then re-run confirms "already in sync"). All three
  ARBs validated as JSON. Widget imports the §4.3 barrel and resolves via `context.l10n`.
- New widget-level test: `test/features/nidus/presentation/driver_card_l10n_test.dart` — pumps
  DriverCard under the delegates for en/am/om, asserts `find.byTooltip(localized)` for both
  actions, localized unit renders, and former English literals do not leak in am/om.
- Note: tooltip localization also partially advances Phase 4 (semantic labels on call/chat),
  but the honest-avatar-degradation item (Icons.person silhouette → initials + label per
  verify_driver_card rule) is still open for Phase 4.

**Session-7 sweep progress (verify_driver_card.dart — migration finished):**
- Session-6 left the ARB groundwork (24 `verify*` keys in en/am/om, compiled and in sync) but the
  card-state strings were still English literals. This session completed the migration: all five
  `PreSelfieState` renders in `build()` (available/notSent/expired/unavailable/unknown), the whole
  `SelfieComparisonView` (app bar, both panel labels, missing-photo note, expiry footnote, both
  verdict buttons), and the `_ImagePanel` decode-error fallback now resolve via `context.l10n`.
  Grep confirms zero remaining user-facing English literals in the file.
- Honesty contract preserved verbatim during migration: unknown wire value still folds into the
  blame-ours "Verification unavailable" render; missing profile photo still shows the explicit
  note instead of an avatar placeholder (new test pins both).
- New widget-level test: `test/features/nidus/presentation/verify_driver_card_l10n_test.dart` —
  pumps VerifyDriverCard (all states) and SelfieComparisonView under the delegates for en/am/om,
  asserts catalog strings render, parameterized subtitle/app-bar/expiry-note interpolate, former
  English literals do not leak in am/om, and `preSelfieStateFrom` maps garbage → unknown.
  No GetIt registration needed (comparison view rendered directly; tap-to-fetch covered at repo
  level). Expiry-note assertion uses UTC to match CI's default device timezone.

**Session-9 sweep progress (split_fare_sheet.dart — migration finished):**
- Added 27 `split*` keys ×3 locales (title, intro, add-person, parameterized send-invites label,
  client pre-check + fare-cap messages, localized fallback for silent server failures, not-yet
  card title/subtitle with `{fare}`, four summary kv labels, five invitee wire-state labels
  (pending/accepted/paid/declined/expired), both field labels, all four validators, close/remove
  tooltips) in en/am/om ARBs; `tool/sync_l10n.py` compiled them into the generated catalogs and
  re-run confirms sync. Amharic values verified free of CJK/mojibake codepoints before writing.
- All user-facing strings in the sheet now resolve via `context.l10n`; grep shows zero remaining
  English literals (only data-driven `'ETB 60.00'`-style formatted amounts and the verbatim
  unknown-status passthrough). The two icon-only buttons (close, remove-share) gained localized
  tooltips, advancing Phase 4's semantic-label rule on this surface.
- Honesty contract preserved: numbers still come only from the server DTO; no-split-yet 404 still
  renders the calm "not split yet" card, never an error; unknown invitee wire states are surfaced
  verbatim instead of mislabeled; a real server failure message stays PRIMARY and the localized
  `splitSendFailed` copy appears only when the message is empty/absent (refined `??` into an
  explicit null-or-empty check so empty-string payloads can't render a blank banner).
- New widget-level test: `test/features/nidus/presentation/split_fare_sheet_l10n_test.dart` —
  fake `SplitFareRepository` registered in the app's GetIt instance; pumps the sheet for en/am/om
  asserting catalog renders, former-literal leak guards, server-sourced totals under localized
  labels, verbatim unknown status, empty-vs-real failure-message precedence, localized validators,
  and the client-side pre-check firing without a network call.

**Session-10 sweep progress (promo_code_sheet.dart — migration finished):**
- Added 19 `promo*` keys ×3 locales (sheet title, remove/use/retry actions, code-field hint,
  validate/checking button labels, needs-fare hint, your-codes header, load-failure line,
  empty state, three client/server validators, and five parameterized saved-code row fragments:
  percent-off, max-cap, fixed-off, min-fare, until-date) in en/am/om ARBs; `tool/sync_l10n.py`
  compiled them into the committed catalogs and a re-run confirms sync. Placeholder types pinned
  to String (pre-formatted server numbers interpolate as text).
- **Seeding-bug fix**: the first pass wrote Amharic values into app_om.arb (Oromo must be Latin
  script Afaan Oromoo); all 19 om entries were rewritten in proper Afaan Oromoo, and the am
  entries replaced the earlier garbled transliterations with clean Ethiopic copy. The new test
  includes a script-mixup regression guard (`om` strings must not contain U+1200–U+137F).
- All user-facing strings in the sheet now resolve via `context.l10n`; literal scan shows zero
  remaining English UI copy (only the `Icons.local_offer_outlined` identifier survives). Honesty
  contract preserved: every discount/cap/min-fare number comes verbatim from the PromoCodeInfo
  DTO inside localized fragment templates; a real server redeem failure reason stays PRIMARY and
  the localized `promoCodeInvalid` fallback appears only for absent/empty messages (refined the
  old `??` so empty-string payloads can't render a blank errorText).
- New widget-level test: `test/features/nidus/presentation/promo_code_sheet_l10n_test.dart` —
  no-network `_FakeMoneyRepo implements Phase2MoneyRepository` registered in GetIt; pumps the
  sheet for en/am/om asserting catalog rendering, former-literal leak guards, needs-fare hint
  gating, server-sourced row fragments under localized glue, honest retry recovery, primary-vs-
  fallback message precedence, client-side validators firing with zero network calls, success
  path applying the untouched server projection, and Remove clearing via onApplied(null,null).

**Open items after Phase 3:**
- No Dart/Flutter toolchain in this environment — `flutter analyze` / `flutter test` must run in CI
  before merge (catalogs, selector edits, driver_card + verify_driver_card edits, and all three
  new widget tests are compiler-unverified locally).
- F.1 Ethiopic font risk still open (assets/fonts absent) — blocks the *localization sweep* exit
  criterion "font ships in bundle"; carried into Phase 4.
- Full Amharic/Oromo translation quality pass remains for human review (coverage ≠ correctness).
- Remaining sweep files (chat_page, receipt_detail_page, notification_inbox_page,
  ar_navigation_page, pre_selfie_capture_sheet,
  stop_charge_card, place_autocomplete_sheet, location_input pending; ride_type_selector,
  driver_card, verify_driver_card, split_fare_sheet done) plus known literal at
  `ride_tracking_page.dart:1427`.
