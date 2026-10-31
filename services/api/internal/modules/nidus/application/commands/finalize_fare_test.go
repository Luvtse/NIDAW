package commands

// ============================================================================
// NIDAW FARE INTEGRITY — Phase 7 mandatory finalize tests.
//
// Covers the §2.5/§2.6 settlement contract end-to-end at the decision layer:
//   - happy digital path: exact santim payload keys + half-up basis-point
//     commission,
//   - fare invariance against detours / delays / manipulated driver reports,
//   - idempotent replay (completed-status short-circuit returns STORED
//     numbers with AlreadyFinalized=true),
//   - concurrent completion single-winner (guarded UPDATE tag 0 → loser
//     replays or surfaces ErrCompletionStateInvalid),
//   - bus outage ⇒ durable outbox obligation preserved with the deterministic
//     event_id == ride UUID,
//   - cash rides: identical payable, pending_cash_collection=true, no inline
//     publish and NO outbox row until collection confirmation,
//   - discount floor at zero payable,
//   - missing-contract refusal (fail closed, never reprices from actuals).
//
// Honest scope note (per dispatch_test.go's documented policy): these unit
// tests exercise the finalize DECISION logic over faked SQL responses. True
// database-level concurrency serialization (row locks under real isolation)
// remains covered by the NIDUS_TEST_DATABASE_URL-guarded integration suite.
// ============================================================================

import (
	"context"
	"encoding/json"
	"errors"
	"math"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"nidaw-backend/internal/modules/nidus/domain/entities"
)

func fzCmd(w *fzWorld) FinalizeFareCommand {
	return FinalizeFareCommand{
		RideID:       w.rideID,
		DriverUserID: w.driverUser,
	}
}

func mustExec(t *testing.T, h *FinalizeFareHandler, cmd FinalizeFareCommand) *FinalizeFareResult {
	t.Helper()
	res, err := h.Execute(context.Background(), cmd)
	if err != nil {
		t.Fatalf("Execute: unexpected error: %v", err)
	}
	return res
}

// --- happy digital path -------------------------------------------------------

func TestFinalize_HappyDigitalPath(t *testing.T) {
	w := newFzWorld()
	w.wire(string(entities.RideStatusInProgress), 95.00, 0, 0, "wallet")

	res := mustExec(t, w.handler(), fzCmd(w))

	if res.Currency != entities.CurrencyETB {
		t.Fatalf("currency = %q, want ETB", res.Currency)
	}
	// F0 = 9500 santim frozen quote; no stops/discount => payable == gross == F0.
	if res.BookingFareSantim != 9500 || res.GrossFareSantim != 9500 || res.PayableSantim != 9500 {
		t.Fatalf("fare triple = (%d,%d,%d), want all 9500",
			res.BookingFareSantim, res.GrossFareSantim, res.PayableSantim)
	}
	// commission = round_half_up(9500 × 1500bp / 10000) = 1425
	wantCommission := int64(math.Floor(float64(res.GrossFareSantim)*1500.0/10000.0 + 0.5))
	if res.CommissionSantim != wantCommission || wantCommission != 1425 {
		t.Fatalf("commission = %d, want %d", res.CommissionSantim, wantCommission)
	}
	if res.DriverEarningsSantim != res.GrossFareSantim-res.CommissionSantim {
		t.Fatal("driver earnings must equal gross - commission exactly")
	}
	if res.SettlementID != w.rideID {
		t.Fatal("settlement id must be the deterministic ride UUID")
	}
	if res.FareSnapshot != w.snapID {
		t.Fatal("result must reference the frozen snapshot")
	}
	if res.AlreadyFinalized || !res.Published || res.PendingCashCollection {
		t.Fatalf("flags = %+v/%+v/%+v, want false/true/false",
			res.AlreadyFinalized, res.Published, res.PendingCashCollection)
	}

	evts := w.bus.events()
	if len(evts) != 1 {
		t.Fatalf("bus events = %d, want exactly 1", len(evts))
	}
	p := evts[0].Payload
	for key, want := range map[string]int64{
		"booking_fare_santim":    9500,
		"stop_fees_santim":       0,
		"waiting_charges_santim": 0,
		"gross_fare_santim":      9500,
		"discount_santim":        0,
		"payable_fare_santim":    9500,
		"commission_santim":      1425,
		"driver_earnings_santim": 8075,
		"tip_santim":             0,
	} {
		got, ok := p[key]
		if !ok {
			t.Fatalf("payload missing santim key %q", key)
		}
		if got != want {
			t.Fatalf("payload[%q] = %v, want %d", key, got, want)
		}
	}
	if p["currency"] != entities.CurrencyETB {
		t.Fatalf("payload currency = %v", p["currency"])
	}
	if p["pending_cash_collection"] != false {
		t.Fatalf("payload pending_cash_collection = %v, want false", p["pending_cash_collection"])
	}
	if p["charge_amount"] != 95.0 {
		t.Fatalf("payload charge_amount = %v, want 95.0 major birr", p["charge_amount"])
	}
	if p["fare_snapshot_id"] != w.snapID.String() {
		t.Fatalf("payload fare_snapshot_id = %v", p["fare_snapshot_id"])
	}
	// Breakdown lines must survive into the payload for receipts.
	linesRaw, ok := p["final_fare_lines"].(string)
	if !ok {
		t.Fatal("payload missing final_fare_lines")
	}
	var lines []struct {
		Kind         string `json:"kind"`
		AmountSantim int64  `json:"amount_santim"`
	}
	if err := json.Unmarshal([]byte(linesRaw), &lines); err != nil {
		t.Fatalf("decode final_fare_lines: %v", err)
	}
	if len(lines) != 1 || lines[0].Kind != "booking" || lines[0].AmountSantim != 9500 {
		t.Fatalf("breakdown lines = %+v, want single booking line at 9500", lines)
	}

	// Outbox obligation persisted inside the same transaction.
	if !w.conn.hasExec("INSERT INTO ride_completed_events") {
		t.Fatal("digital winner must enqueue the settlement outbox row")
	}
	if w.tx.commitCalls != 1 {
		t.Fatalf("commit calls = %d, want 1", w.tx.commitCalls)
	}
}

// --- fare invariance vs. detour / delay / manipulated reports ------------------

func TestFinalize_ActualMetricsCannotChangePayable(t *testing.T) {
	run := func(t *testing.T, actualKm float64, actualMin int) int64 {
		w := newFzWorld()
		w.wire(string(entities.RideStatusInProgress), 95.00, 0, 0, "wallet")
		res := mustExec(t, w.handler(), FinalizeFareCommand{
			RideID: w.rideID, DriverUserID: w.driverUser,
			ActualDistanceKm: actualKm, ActualDurationMin: actualMin,
		})
		return res.PayableSantim
	}

	baseline := run(t, 0, 0) // metrics omitted entirely
	if v := run(t, 10.0, 30); v != baseline {
		t.Fatalf("honest metrics payable %d != baseline %d", v, baseline)
	}
	if v := run(t, 17.4, 58); v != baseline { // detour + slow driving
		t.Fatalf("detour payable %d != baseline %d — actuals leaked into money math", v, baseline)
	}
	if v := run(t, 999, 100000); v != baseline { // manipulated report
		t.Fatalf("manipulated payable %d != baseline %d", v, baseline)
	}
}

// --- approved additions still flow through --------------------------------------

func TestFinalize_ApprovedStopsAndDiscount(t *testing.T) {
	w := newFzWorld()
	w.stops = []servicesApprovedStopView{
		{Seq: 1, FixedFeeSantim: 1000, WaitingChargeSan: 4750}, // fee + 50%·F0 (non-compounding base)
		{Seq: 2, FixedFeeSantim: 1000, WaitingChargeSan: 0},
	}
	w.wire(string(entities.RideStatusInProgress), 95.00, 10.00, 5.00, "wallet")

	res := mustExec(t, w.handler(), FinalizeFareCommand{
		RideID: w.rideID, DriverUserID: w.driverUser,
		ActualDistanceKm: 20, ActualDurationMin: 90, // ignored by money math
	})

	if res.StopFeesSantim != 2000 || res.WaitingChargesSantim != 4750 {
		t.Fatalf("additions = (%d,%d), want (2000,4750)", res.StopFeesSantim, res.WaitingChargesSantim)
	}
	if res.GrossFareSantim != 9500+2000+4750 {
		t.Fatalf("gross = %d, want %d", res.GrossFareSantim, 9500+2000+4750)
	}
	// Discount P = 1000 santim from the stored ride-level promo snapshot.
	if res.DiscountSantim != 1000 || res.PayableSantim != res.GrossFareSantim-1000 {
		t.Fatalf("discount/payable = (%d,%d), want (1000,%d)",
			res.DiscountSantim, res.PayableSantim, res.GrossFareSantim-1000)
	}
	if res.TipSantim != 500 {
		t.Fatalf("tip = %d santim, want 500 (separately identified)", res.TipSantim)
	}
	// Reconciliation identity: rider debit covers gross-P; driver credited on
	// gross basis (platform funds the discount), tip separate.
	if res.DriverEarningsSantim+res.CommissionSantim != res.GrossFareSantim {
		t.Fatal("commission + driver earnings must equal gross exactly")
	}
}

// --- discount floor at zero -----------------------------------------------------

func TestFinalize_DiscountFloorsAtZero(t *testing.T) {
	w := newFzWorld()
	w.wire(string(entities.RideStatusInProgress), 95.00, 200.00, 0, "wallet") // 20000 santim > gross

	res := mustExec(t, w.handler(), FinalizeFareCommand{RideID: w.rideID, DriverUserID: w.driverUser})

	if res.PayableSantim != 0 {
		t.Fatalf("payable = %d, want floor 0", res.PayableSantim)
	}
	if res.DiscountSantim != res.GrossFareSantim {
		t.Fatalf("applied discount = %d, want gross %d (never negative payable)",
			res.DiscountSantim, res.GrossFareSantim)
	}
}

// --- idempotent replay ------------------------------------------------------------

func TestFinalize_ReplayReturnsStoredNumbers(t *testing.T) {
	w := newFzWorld()
	w.wire(string(entities.RideStatusCompleted), 95.00, 0, 0, "wallet")

	res := mustExec(t, w.handler(), FinalizeFareCommand{
		RideID: w.rideID, DriverUserID: w.driverUser,
		ActualDistanceKm: 33, ActualDurationMin: 120, // even a wild replay stays invariant
	})

	if !res.AlreadyFinalized {
		t.Fatal("replay must report AlreadyFinalized=true")
	}
	if res.BookingFareSantim != 9500 || res.GrossFareSantim != 9500 || res.PayableSantim != 9500 {
		t.Fatalf("replayed numbers drifted: %+v", res)
	}
	if res.CommissionSantim != 1425 || res.DriverEarningsSantim != 8075 {
		t.Fatalf("replayed split = (%d,%d), want (1425,8075)", res.CommissionSantim, res.DriverEarningsSantim)
	}
	if len(w.bus.events()) != 0 {
		t.Fatal("replay must NEVER republish the settlement event")
	}
	if w.conn.hasExec("UPDATE rides SET status = 'completed'") {
		t.Fatal("replay must not touch terminal state again")
	}
}

func TestFinalize_ReplayDetectsDrift(t *testing.T) {
	// A completed ride whose fare_amount was edited after finalization must
	// fail loudly instead of silently endorsing the drift.
	w := newFzWorld()
	w.wire(string(entities.RideStatusCompleted), 120.00, 0, 0, "wallet")

	_, err := w.handler().Execute(context.Background(), fzCmd(w))
	if !errors.Is(err, ErrFinalizeAlreadySettled) {
		t.Fatalf("err = %v, want ErrFinalizeAlreadySettled wrapping the drift report", err)
	}
}

// --- concurrent completion single-winner ------------------------------------------

func TestFinalize_LoserReplaysWinnerResult(t *testing.T) {
	w := newFzWorld()
	inProgress := &fzOneRow{vals: w.rideVals(string(entities.RideStatusInProgress), 95.00, 0, 0, "wallet")}
	completed := &fzOneRow{vals: w.rideVals(string(entities.RideStatusCompleted), 95.00, 0, 0, "wallet")}

	w.conn.add("FROM drivers WHERE user_id", &fzOneRow{vals: []any{w.driverProfile}})
	w.conn.add("SELECT user_id FROM drivers WHERE id", &fzOneRow{vals: []any{w.driverUser}})
	w.conn.addSeq("FROM rides WHERE id", inProgress, completed) // first read active, re-read after losing sees winner's commit
	w.wireSnapshot()
	w.wireStops()

	w.tx.terminalRows = 0 // this attempt loses the guarded UPDATE race

	res := mustExec(t, w.handler(), FinalizeFareCommand{
		RideID: w.rideID, DriverUserID: w.driverUser,
		ActualDistanceKm: 40, ActualDurationMin: 99, // loser metrics irrelevant
	})

	// The loser surfaced the WINNER's stored result (same numbers to santim).
	if !res.AlreadyFinalized {
		t.Fatal("loser path must return the winner's finalized result")
	}
	if res.PayableSantim != 9500 || res.GrossFareSantim != 9500 {
		t.Fatalf("loser replay = (%d,%d), want (9500,9500)", res.GrossFareSantim, res.PayableSantim)
	}
	if len(w.bus.events()) != 0 {
		t.Fatal("loser must NOT publish a second settlement event")
	}
	if w.conn.hasExec("INSERT INTO ride_completed_events") {
		t.Fatal("loser must NOT enqueue a second outbox row")
	}
}

func TestFinalize_LoserSeesNonTerminalStateFailsClosed(t *testing.T) {
	w := newFzWorld()
	inProgress := &fzOneRow{vals: w.rideVals(string(entities.RideStatusInProgress), 95.00, 0, 0, "wallet")}

	w.conn.add("FROM drivers WHERE user_id", &fzOneRow{vals: []any{w.driverProfile}})
	w.conn.add("SELECT user_id FROM drivers WHERE id", &fzOneRow{vals: []any{w.driverUser}})
	// Race guard affected 0 rows yet the ride is STILL in_progress: some other
	// write path moved it. Honesty requires ErrCompletionStateInvalid rather
	// than pretending a finalized result exists.
	w.conn.addFn("FROM rides WHERE id", func(...any) pgx.Row { return inProgress })
	w.wireSnapshot()
	w.wireStops()
	w.tx.terminalRows = 0

	_, err := w.handler().Execute(context.Background(), FinalizeFareCommand{
		RideID: w.rideID, DriverUserID: w.driverUser,
	})
	if !errors.Is(err, ErrCompletionStateInvalid) {
		t.Fatalf("err = %v, want ErrCompletionStateInvalid", err)
	}
	if len(w.bus.events()) != 0 {
		t.Fatal("failed persist path must not leave extra publishes beyond the pre-tx fast path")
	}
}

// --- bus outage preserves obligation ------------------------------------------------

func TestFinalize_BusDownOutboxPreserved(t *testing.T) {
	w := newFzWorld()
	w.wire(string(entities.RideStatusInProgress), 95.00, 0, 0, "wallet")
	w.bus.err = errors.New("kafka unavailable")

	res := mustExec(t, w.handler(), fzCmd(w))

	if res.Published {
		t.Fatal("Published must be false when the bus is down")
	}
	if !w.conn.hasExec("INSERT INTO ride_completed_events") {
		t.Fatal("outbox obligation must be persisted even with the bus down")
	}
	args, ok := w.conn.execArgsFor("INSERT INTO ride_completed_events")
	if !ok {
		t.Fatal("outbox exec not recorded")
	}
	// Deterministic event key: event_id == ride UUID — retries can never mint
	// a second settlement obligation.
	if evID, _ := args[0].(uuid.UUID); evID != w.rideID {
		t.Fatalf("outbox event_id = %v, want ride UUID %v", args[0], w.rideID)
	}
	if w.tx.rollbackCalls != 0 || w.tx.commitCalls != 1 {
		t.Fatalf("tx commit=%d rollback=%d, want 1/0", w.tx.commitCalls, w.tx.rollbackCalls)
	}
	// Fare itself unchanged by the transport failure.
	if res.PayableSantim != 9500 {
		t.Fatalf("payable = %d, want 9500 despite bus outage", res.PayableSantim)
	}
}

// --- persistence failure rolls back ---------------------------------------------------

func TestFinalize_PersistFailureRollsBack(t *testing.T) {
	w := newFzWorld()
	w.wire(string(entities.RideStatusInProgress), 95.00, 0, 0, "wallet")
	w.tx.failTerminal = true

	if _, err := w.handler().Execute(context.Background(), fzCmd(w)); err == nil {
		t.Fatal("expected error when terminal update fails")
	}
	if w.tx.rollbackCalls != 1 || w.tx.commitCalls != 0 {
		t.Fatalf("tx commit=%d rollback=%d, want 0/1", w.tx.commitCalls, w.tx.rollbackCalls)
	}
}

// --- cash rides --------------------------------------------------------------------

func TestFinalize_CashSamePayableNoInlineSettlement(t *testing.T) {
	w := newFzWorld()
	w.wire(string(entities.RideStatusInProgress), 95.00, 0, 0, "cash")

	res := mustExec(t, w.handler(), fzCmd(w))

	if !res.PendingCashCollection {
		t.Fatal("cash finalization must mark pending_cash_collection")
	}
	if res.PayableSantim != 9500 || res.GrossFareSantim != 9500 {
		t.Fatalf("cash payable = %d, want the SAME 9500 as electronic", res.PayableSantim)
	}
	if len(w.bus.events()) != 0 {
		t.Fatal("cash rides must NOT emit settlement before collection confirmation")
	}
	if w.conn.hasExec("INSERT INTO ride_completed_events") {
		t.Fatal("cash rides must NOT enqueue settlement before collection confirmation")
	}
	if res.Published {
		t.Fatal("Published must be false for cash")
	}
}

// --- missing contract refuses to settle ----------------------------------------------

func TestFinalize_MissingContractRefused(t *testing.T) {
	w := newFzWorld()
	w.wireDriversAndRide(string(entities.RideStatusInProgress))
	w.wireStops()
	// Deliberately do NOT install the snapshot rule: GetSnapshotByRideID hits
	// the unexpected-query error path, which Execute maps to ErrFareCalcFailed.

	_, err := w.handler().Execute(context.Background(), fzCmd(w))
	if !errors.Is(err, ErrFareCalcFailed) {
		t.Fatalf("err = %v, want ErrFareCalcFailed wrapping snapshot-not-found", err)
	}
	if len(w.bus.events()) != 0 {
		t.Fatal("refusal must not publish anything")
	}
	if w.conn.hasExec("UPDATE rides SET status = 'completed'") {
		t.Fatal("refusal must not mutate terminal state")
	}
}

func TestFinalize_StrayApprovedChargesFailClosed(t *testing.T) {
	// Handler built WITHOUT the stop port but the ride has an approved stop
	// charge: under-settling is worse than refusing, so Execute must fail.
	w := newFzWorld()
	w.strayCharges = 2
	w.wire(string(entities.RideStatusInProgress), 95.00, 0, 0, "wallet")

	_, err := w.handlerNoStopPort().Execute(context.Background(), fzCmd(w))
	if !errors.Is(err, ErrFareCalcFailed) {
		t.Fatalf("err = %v, want ErrFareCalcFailed (stray approved charges)", err)
	}
}

func TestFinalize_UnauthorizedCallerRejected(t *testing.T) {
	w := newFzWorld()
	w.wire(string(entities.RideStatusInProgress), 95.00, 0, 0, "wallet")

	// Override the driver lookup: the authenticated subject maps to a
	// DIFFERENT driver profile than the one assigned to the ride.
	w.conn.add("FROM drivers WHERE user_id",
		&fzOneRow{vals: []any{uuid.MustParse("88888888-8888-8888-8888-888888888888")}})

	cmd := FinalizeFareCommand{RideID: w.rideID, DriverUserID: w.driverUser}
	if _, err := w.handler().Execute(context.Background(), cmd); !errors.Is(err, ErrForbidden) {
		t.Fatalf("err = %v, want ErrForbidden", err)
	}
	if len(w.bus.events()) != 0 {
		t.Fatal("unauthorized caller must trigger no settlement traffic")
	}
}

func TestFinalize_NegativePromoOverrideRejected(t *testing.T) {
	w := newFzWorld()
	w.wire(string(entities.RideStatusInProgress), 95.00, 0, 0, "wallet")

	_, err := w.handler().Execute(context.Background(), FinalizeFareCommand{
		RideID: w.rideID, DriverUserID: w.driverUser, PromoDiscountSantim: -1,
	})
	if !errors.Is(err, ErrCompletionNegativeAddition) {
		t.Fatalf("err = %v, want ErrCompletionNegativeAddition", err)
	}
}
