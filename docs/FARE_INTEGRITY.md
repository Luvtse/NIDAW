# NIDAW FARE INTEGRITY — Nidus Ride Pricing Contract

Authoritative record of how ride fares are quoted, frozen, amended and
settled. All money is integer **santim** (1 ETB = 100 santim); display layers
format, they never compute.

## Phase 1 — Frozen booking contract (live)

- At booking confirmation the platform writes an immutable
  `ride_fare_snapshots` row: original endpoints, contract distance/duration,
  versioned pricing rules, surge, minimum-fare floor and the rider-accepted
  `quoted_total_santim` (F0).
- Completion NEVER reprices from actual trip metrics. Actual distance/duration
  are recorded operations-only; the payable always derives from the frozen
  snapshot via `FinalFareService.Compute`.
- Destination changes create APPROVED AMENDMENTS (a new snapshot revision),
  never an edit of frozen numbers.

## Phase 2 — Rider-approved stop charges (`stops-v1`) (live)

Policy constants (`nidus/domain/entities/stop_charge.go`):

| Rule | Value | Notes |
| --- | --- | --- |
| Fixed fee per approved stop | Br 10.00 = **1000 santim** | Override via `NIDUS_STOP_FEE_SANTIM`; out-of-range values fail closed to the default |
| Waiting threshold | dwell **≥ 10 minutes** triggers | Inclusive boundary; dwell floors to whole minutes (rider-favorable: 9m59s pays fee only) |
| Waiting charge | exact rational **½ × F0** | Computed ONLY from the ORIGINAL frozen booking fare — non-compounding by construction; deterministic half-up rounding in santim |
| Policy version tag | `stops-v1` | Persisted on every charge row; unknown versions refuse settlement |

### Money rules (enforced in code AND SQL, not convention)

1. **Rider-only approval.** A stop fee becomes payable only after the
   authenticated rider explicitly approves it (`POST
   /nidus/rides/{rideID}/stops/{seq}/approve`, JWT subject checked against
   `rides.user_id`). The request body deliberately carries **no amount field**
   — a client cannot negotiate fees. Drivers have NO approve surface at all.
2. **Exactly-once per stop.** Approval INSERTs are guarded by
   `ON CONFLICT (ride_id, seq) DO NOTHING`; a second tap surfaces
   `ErrStopAlreadyApproved` (HTTP 409) and never re-freezes or double-counts a
   fee.
3. **Server-clock timer audit rules.** Stop-window events are stamped by the
   server inside guarded UPDATEs: start requires `started_at IS NULL`; stop
   requires `started_at NOT NULL AND ended_at IS NULL`. Lost races affect zero
   rows and surface as explicit errors (409) — drivers cannot fabricate or
   backdate a stop window, and the dwell used for money math is unique.
4. **Waiting charge computed at STOP time and PERSISTED**, from
   `ride_fare_snapshots.quoted_total_santim`. Receipt and ledger read stored
   numbers instead of recomputing from clocks.
5. **Settlement refuses loudly** any `ride_stop_charges` row lacking rider
   approval (`ErrStopNotApproved`) — an unapproved charge is a data-integrity
   incident, never a quiet line item.
6. **Fail-closed wiring.** `CompleteRideHandler` and
   `ConfirmCashCollectionHandler` both consume approved stops through the same
   `FinalFareService.Compute(snapshot, approvedStops, promoSantim)` call. If
   approved charges exist but the StopCharger port is unwired, completion
   REFUSES rather than under-settling.
7. **Cash == electronic parity.** Cash rides settle the identical payable
   formula `max(0, F0 + S + W − P)`; the payable floor is zero so an over-large
   promo can never mint a credit.
8. **QuoteStop is write-free disclosure** (`GET .../stops/{seq}/quote`) that
   fails closed (409 `NO_BOOKING_CONTRACT`) when no frozen contract exists.

### Persistence

- Migration `028_nidus_stop_charges.sql`: `ride_stop_charges` with BIGINT
  santim columns (`CHECK ≥ 0`), `UNIQUE(ride_id, seq)` idempotency,
  server-defaulted timestamps, additive/backward-safe (+ `028_down.sql`).

### HTTP surface (authenticated `/nidus/rides`, gated on stopovers feature)

| Route | Actor | Notes |
| --- | --- | --- |
| `GET  /{rideID}/stops/{seq}/quote` | rider/driver (participants) | Disclosure only, zero writes |
| `POST /{rideID}/stops/{seq}/approve` | **rider only** | Freezes disclosed fee; exactly-once |
| `POST /{rideID}/stops/{seq}/timer/start` | ride participants | Guarded server-clock stamp |
| `POST /{rideID}/stops/{seq}/timer/stop` | ride participants | Finalizes dwell + persists waiting charge |

Sentinel → status mapping: not-owner/not-approved → 403, already-approved →
409, timer-not-running/not-started/already-started/closed → 409,
seq-out-of-range → 422, no-contract → 409, ride-not-found → 404, service
unwired → honest 503 (`STOP_CHARGES_UNAVAILABLE`), never a fake accept.

`GET /nidus/rides/{rideID}` embeds each stop's `charge` projection (nil = "no
fee approved", never zero-filled) so both apps render the authoritative state
without extra polling; live sync reuses the existing ride-update WebSocket
channel.

### Test coverage

`stop_charge_service_test.go` locks: default/override fee, 9m59s vs 10m00s
boundary, two long stops cost exactly 2×(fee + ½·F0), approval exactly-once
with conflict sentinel, stranger-refused approval, write-free quote + fail
closed without contract, settlement refusal of unapproved rows, guarded timer
transitions and race surfacing, cash/electronic parity, payable floor.
