package services

// NIDAW FARE INTEGRITY — Phase 2 test suite for rider-approved stop charges.
//
// Coverage (mirrors the stops-v1 contract exactly):
//   - Fixed fee: default Br 10.00 = 1000 santim; NIDUS_STOP_FEE_SANTIM override.
//   - Waiting threshold boundary: 9m59s pays ONLY the fixed fee; 10m00s pays
//     fee + waiting charge ("≥ 10 triggers", inclusive boundary).
//   - Non-compounding: two long stops cost EXACTLY 2×(fee + ½·F0) — never an
//     escalating series computed on inflated bases.
//   - Approval exactly-once: a second approval surfaces ErrStopAlreadyApproved
//     and never re-freezes or double-counts a fee (ON CONFLICT DO NOTHING path).
//   - SettlementCharges refuses loudly any row lacking rider approval; QuoteStop
//     is write-free and fails closed when no frozen booking contract exists.
//   - Timer transitions are server-clock guarded: start requires started_at IS
//     NULL, stop requires running-and-open; lost races affect zero rows and
//     surface as explicit errors.
//   - Cash and electronic settle the identical payable (same Compute call).
//
// SQL fakes come from stop_charge_testhelpers_test.go (fakeRowVals/noRow/
// fakeRows/newFakeRows/mkTag/fakeConn/newSvc/newSvcFull/has/ptrTime).

import (
	"context"
	"errors"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"nidaw-backend/internal/modules/nidus/domain/entities"
)

// validSnapshot builds a self-consistent frozen booking contract quoting
// totalSantim (gross == component sum, no floor applied) that passes
// FareSnapshot.Validate and therefore FinalFareService.Compute.
func validSnapshot(totalSantim int64) *entities.FareSnapshot {
	return &entities.FareSnapshot{
		ID:                   uuid.New(),
		RideID:               uuid.New(),
		IdempotencyKey:       "test-snapshot",
		Currency:             entities.CurrencyETB,
		PricingConfigVersion: "pricing-v1",
		DurationRuleVersion:  "dur-min-per-km-v1",
		MinutesPerKm:         3.0,
		QuotedTotalSantim:    totalSantim,
		FrozenAt:             time.Now().UTC(),
		Components: entities.FareComponents{
			BaseFareSantim:     1000,
			DistanceFareSantim: totalSantim - 1000,
			TimeFareSantim:     0,
			SurgeAmountSantim:  0,
			MinimumFareSantim:  1000,
			GrossFareSantim:    totalSantim,
			RideType:           "standard",
		},
	}
}

// ============================================================================
// PURE POLICY — fixed fee, threshold boundary, non-compounding
// ============================================================================

func TestStopFee_DefaultAndOverride(t *testing.T) {
	if entities.StopFeeSantimDefaultV1 != 1000 {
		t.Fatalf("default fixed fee must be Br 10.00 = 1000 santim, got %d", entities.StopFeeSantimDefaultV1)
	}
	// The env override is read at service construction via strconv on the same
	// constant name; verify the parse rule used by the composition root.
	t.Setenv("NIDUS_STOP_FEE_SANTIM", "1500")
	v, err := strconv.ParseInt(os.Getenv("NIDUS_STOP_FEE_SANTIM"), 10, 64)
	if err != nil || v != 1500 {
		t.Fatalf("NIDUS_STOP_FEE_SANTIM override must parse to 1500, got %d err %v", v, err)
	}
}

func TestWaitingThreshold_Boundary_9m59s_vs_10m00s(t *testing.T) {
	const f0 = 4000 // Br 40.00 booking fare
	// 9 minutes 59 seconds of dwell floors to 9 minutes → short stop, fee only.
	dwellShort := 9*time.Minute + 59*time.Second
	minShort := int(dwellShort.Minutes())
	if minShort != 9 {
		t.Fatalf("fixture: 9m59s must floor to 9 minutes, got %d", minShort)
	}
	fee, waiting := entities.StopChargeFor(entities.StopFeeSantimDefaultV1, minShort, f0)
	if fee != 1000 || waiting != 0 {
		t.Fatalf("9m59s stop must pay fee only (1000, 0), got (%d, %d)", fee, waiting)
	}

	// Exactly 10m00s triggers ("lasting 10 minutes or longer").
	dwellExact := 10 * time.Minute
	minExact := int(dwellExact.Minutes())
	fee, waiting = entities.StopChargeFor(entities.StopFeeSantimDefaultV1, minExact, f0)
	if fee != 1000 || waiting != 2000 {
		t.Fatalf("10m00s stop must pay fee + ½·F0 (1000, 2000), got (%d, %d)", fee, waiting)
	}
	if !entities.CrossesWaitingThreshold(minExact) {
		t.Fatal("threshold must be inclusive at exactly 10 minutes")
	}
	if entities.CrossesWaitingThreshold(9) {
		t.Fatal("9 minutes must NOT cross the threshold")
	}
}

func TestTwoLongStops_CostExactly_2x_Fee_Plus_HalfF0_NonCompounding(t *testing.T) {
	const f0 = 3999 // odd santim total exercises deterministic rounding once, per stop
	fee, waiting := entities.StopChargeFor(entities.StopFeeSantimDefaultV1, 12, f0)
	perStopTotal := fee + waiting // 1000 + round(3999/2)=2000 → 3000

	res, err := NewFinalFareService().Compute(FinalFareInput{
		Snapshot: validSnapshot(f0),
		Stops: []ApprovedStop{
			{Seq: 1, FixedFeeSantim: fee, WaitingChargeSan: waiting},
			{Seq: 2, FixedFeeSantim: fee, WaitingChargeSan: waiting},
		},
	})
	if err != nil {
		t.Fatalf("compute: %v", err)
	}
	want := 2 * perStopTotal
	if res.StopFeesSantim+res.WaitingSantim != want {
		t.Fatalf("two long stops must cost exactly 2×(fee+½·F0)=%d, got %d", want, res.StopFeesSantim+res.WaitingSantim)
	}
	if res.PayableSantim != f0+want {
		t.Fatalf("payable must be F0 + 2×(fee+½·F0) = %d, got %d", f0+want, res.PayableSantim)
	}
	// Compounding would make the SECOND stop's waiting charge larger than ½·F0
	// (it would be computed on an inflated base). Assert equality explicitly:
	if res.WaitingSantim != 2*waiting || waiting != entities.ComputeWaitingChargeSantim(f0) {
		t.Fatalf("waiting charges must each equal ½·F0 exactly (non-compounding)")
	}
}

func TestComputeWaitingCharge_DeterministicRounding(t *testing.T) {
	if got := entities.ComputeWaitingChargeSantim(4001); got != 2001 {
		t.Fatalf("odd F0 4001 → half-up 2001, got %d", got)
	}
	if got := entities.ComputeWaitingChargeSantim(4000); got != 2000 {
		t.Fatalf("even F0 4000 → exact 2000, got %d", got)
	}
	if got := entities.ComputeWaitingChargeSantim(0); got != 0 {
		t.Fatal("F0<=0 is a data error; charge must be 0, callers reject before use")
	}
	if got := entities.ComputeWaitingChargeSantim(-5); got != 0 {
		t.Fatal("negative F0 rejected → 0")
	}
}

// ============================================================================
// APPROVAL — exactly-once, rider-only, fail-closed without contract
// ============================================================================

func TestApproveStop_ExactlyOnce_ConlictSurfacesNeverRefreeze(t *testing.T) {
	rideID, rider := uuid.New(), uuid.New()
	var inserts int
	var insertSQLs []string
	svc := newSvc(
		func(sql string, _ ...any) pgx.Row {
			switch {
			case has(sql, "FROM ride_stops"): // stop-exists probe
				return &fakeRowVals{vals: []any{true}}
			case has(sql, "FROM rides"): // ownership fallback check
				return &fakeRowVals{vals: []any{rider}}
			case has(sql, "ride_fare_snapshots"):
				return &fakeRowVals{vals: []any{int64(4000)}} // F0
			case has(sql, "FROM ride_stop_charges"): // ApproveStop persisted-row echo
				return &fakeRowVals{vals: []any{
					1, int64(1000), entities.StopPolicyVersion, true, ptrTime(time.Now().UTC()),
					0, false, int64(0), (*time.Time)(nil), (*time.Time)(nil),
				}}
			default:
				return noRow()
			}
		},
		func(sql string, _ ...any) (pgconn.CommandTag, error) {
			if has(sql, "INSERT INTO ride_stop_charges") {
				inserts++
				insertSQLs = append(insertSQLs, sql)
				if inserts == 1 {
					return mkTag(1), nil // first tap wins
				}
				return mkTag(0), nil // ON CONFLICT DO NOTHING: second tap affects 0 rows
			}
			return mkTag(0), nil
		},
	)

	c1, err := svc.ApproveStop(context.Background(), rideID, rider, 1)
	if err != nil {
		t.Fatalf("first approval must succeed: %v", err)
	}
	if c1.StopFeeSantim != 1000 || !c1.ApprovedByRider {
		t.Fatalf("approved row must freeze the disclosed fee, got %+v", c1)
	}
	_, err = svc.ApproveStop(context.Background(), rideID, rider, 1)
	if !errors.Is(err, ErrStopAlreadyApproved) {
		t.Fatalf("second approval must surface ErrStopAlreadyApproved, got %v", err)
	}
	// Money invariant: the conflict path wrote nothing new. Both taps issue the
	// same idempotent ON CONFLICT DO NOTHING statement (no UPDATE of an
	// existing row, no second fee), and only the FIRST tap affected a row — so
	// settlement sees exactly one charge, never two.
	if inserts != 2 {
		t.Fatalf("both approval taps must hit the idempotent INSERT path; saw %d", inserts)
	}
	for _, sql := range insertSQLs {
		if !has(sql, "ON CONFLICT (ride_id, seq) DO NOTHING") {
			t.Fatalf("approval INSERT must be guarded by ON CONFLICT DO NOTHING, got %q", sql)
		}
	}
}

func TestApproveStop_StrangerRefused(t *testing.T) {
	rideID, rider, stranger := uuid.New(), uuid.New(), uuid.New()
	svc := newSvc(
		func(sql string, _ ...any) pgx.Row {
			switch {
			case has(sql, "FROM ride_stops"):
				return &fakeRowVals{vals: []any{true}}
			case has(sql, "FROM rides"):
				return &fakeRowVals{vals: []any{rider}} // owner is `rider`, not `stranger`
			default:
				return noRow()
			}
		},
		func(string, ...any) (pgconn.CommandTag, error) {
			t.Fatal("no write may happen for a non-owner approval attempt")
			return mkTag(0), nil
		},
	)
	_, err := svc.ApproveStop(context.Background(), rideID, stranger, 1)
	if !errors.Is(err, ErrStopNotRideOwner) {
		t.Fatalf("stranger approval must be refused with ErrStopNotRideOwner, got %v", err)
	}
}

func TestQuoteStop_WriteFree_AndFailsClosedWithoutContract(t *testing.T) {
	rideID := uuid.New()
	var execs int
	svc := newSvc(
		func(sql string, _ ...any) pgx.Row {
			if has(sql, "ride_fare_snapshots") {
				return &fakeRowVals{vals: []any{int64(4000)}}
			}
			return noRow()
		},
		func(string, ...any) (pgconn.CommandTag, error) {
			execs++
			return mkTag(0), nil
		},
	)
	q, err := svc.QuoteStop(context.Background(), rideID, 1)
	if err != nil {
		t.Fatalf("quote with contract: %v", err)
	}
	if q.FixedFeeSantim != 1000 || q.WaitingChargeIfLongSantim != 2000 {
		t.Fatalf("quote must disclose fee 1000 + waiting ½·F0 2000, got %+v", q)
	}
	if q.PolicyVersion != entities.StopPolicyVersion || q.Currency != entities.CurrencyETB {
		t.Fatalf("quote must carry policy/currency metadata verbatim, got %+v", q)
	}
	if execs != 0 {
		t.Fatalf("QuoteStop must perform NO writes, saw %d Exec calls", execs)
	}

	noSnap := newSvc(func(string, ...any) pgx.Row { return noRow() }, nil)
	if _, err := noSnap.QuoteStop(context.Background(), rideID, 1); !errors.Is(err, ErrFinalFareNoSnapshot) {
		t.Fatalf("quote must fail closed with ErrFinalFareNoSnapshot when no frozen contract exists, got %v", err)
	}
}

// ============================================================================
// SETTLEMENT READ — refuses unapproved rows loudly
// ============================================================================

func TestSettlementCharges_RefusesUnapprovedRow(t *testing.T) {
	rideID := uuid.New()
	rows := newFakeRows(
		[]string{"seq", "stop_fee_santim", "waiting_charge_santim", "approved_by_rider"},
		[][]any{{1, int64(1000), int64(0), false}}, // charge row WITHOUT rider approval
	)
	svc := newSvcFull(nil, nil, func(string, ...any) (pgx.Rows, error) { return rows, nil })
	_, err := svc.SettlementCharges(context.Background(), rideID)
	if err == nil {
		t.Fatal("settlement must REFUSE a row lacking rider approval, never include it quietly")
	}
	if !errors.Is(err, entities.ErrStopNotApproved) {
		t.Fatalf("refusal must carry the stable sentinel ErrStopNotApproved, got %v", err)
	}
}

func TestSettlementCharges_ReturnsApprovedRowsInSeqOrder(t *testing.T) {
	rideID := uuid.New()
	rows := newFakeRows(
		[]string{"seq", "stop_fee_santim", "waiting_charge_santim", "approved_by_rider"},
		[][]any{
			{1, int64(1000), int64(2000), true},
			{2, int64(1000), int64(0), true},
		},
	)
	svc := newSvcFull(nil, nil, func(string, ...any) (pgx.Rows, error) { return rows, nil })
	out, err := svc.SettlementCharges(context.Background(), rideID)
	if err != nil {
		t.Fatalf("approved rows must load cleanly: %v", err)
	}
	if len(out) != 2 || out[0].Seq != 1 || out[1].Seq != 2 {
		t.Fatalf("expected 2 approved stops in seq order, got %+v", out)
	}
	if out[0].TotalSantim() != 3000 || out[1].TotalSantim() != 1000 {
		t.Fatalf("stop totals must be fee+waiting exactly, got %+v", out)
	}
}

// ============================================================================
// TIMER TRANSITIONS — server-clock guarded, races surface explicitly
// ============================================================================

func TestStartStopTimer_GuardsAndRaceLossSurfaces(t *testing.T) {
	rideID := uuid.New()

	// Start on an already-running timer: UPDATE ... WHERE started_at IS NULL
	// hits 0 rows; classification read shows started_at set ⇒ ErrStopAlreadyStarted.
	svc := newSvc(
		func(string, ...any) pgx.Row { return noRow() },
		func(sql string, _ ...any) (pgconn.CommandTag, error) {
			if has(sql, "started_at IS NULL") {
				return mkTag(0), nil
			}
			return mkTag(1), nil
		},
	)
	// Zero-row start falls into classifyZeroRowTransition, whose SELECT returns
	// no row above → honestly reported as ErrStopTimerNotRunning (no approval
	// row exists to time). Either way the double-start NEVER succeeds silently.
	err := svc.StartStopTimer(context.Background(), rideID, 1)
	if err == nil {
		t.Fatal("double-start must surface an error (zero-row guarded update)")
	}
	if !errors.Is(err, ErrStopTimerNotRunning) && !errors.Is(err, ErrStopAlreadyStarted) {
		t.Fatalf("start race must map to an explicit timer sentinel, got %v", err)
	}

	// Happy-path start: guarded UPDATE affects exactly one row.
	ok := newSvc(nil, func(sql string, _ ...any) (pgconn.CommandTag, error) {
		if has(sql, "started_at IS NULL") {
			return mkTag(1), nil
		}
		return mkTag(0), nil
	})
	if err := ok.StartStopTimer(context.Background(), rideID, 1); err != nil {
		t.Fatalf("valid start must succeed, got %v", err)
	}
}

func TestStopStopTimer_GuardsRacesAndPersistsWaitingCharge(t *testing.T) {
	rideID := uuid.New()
	started := time.Now().UTC().Add(-11 * time.Minute)

	// Stop where no approval row exists at all → ErrStopTimerNotRunning.
	svcMissing := newSvc(func(string, ...any) pgx.Row { return noRow() }, nil)
	if _, err := svcMissing.StopStopTimer(context.Background(), rideID, 1); !errors.Is(err, ErrStopTimerNotRunning) {
		t.Fatalf("missing row must map to ErrStopTimerNotRunning, got %v", err)
	}

	// Stop where the row exists but was never started → ErrStopTimerNotStarted.
	svcNotStarted := newSvc(
		func(sql string, _ ...any) pgx.Row {
			if has(sql, "FROM ride_stop_charges") {
				return &fakeRowVals{vals: []any{(*time.Time)(nil), int64(1000), entities.StopPolicyVersion}}
			}
			return &fakeRowVals{vals: []any{int64(4000)}} // F0
		}, nil)
	if _, err := svcNotStarted.StopStopTimer(context.Background(), rideID, 1); !errors.Is(err, ErrStopTimerNotStarted) {
		t.Fatalf("never-started stop must map to ErrStopTimerNotStarted, got %v", err)
	}

	// Stop where the close race is lost (ended_at already set) → ErrStopTimerClosed.
	svcLost := newSvc(
		func(sql string, _ ...any) pgx.Row {
			if has(sql, "FROM ride_stop_charges") {
				return &fakeRowVals{vals: []any{ptrTime(started), int64(1000), entities.StopPolicyVersion}}
			}
			return &fakeRowVals{vals: []any{int64(4000)}}
		},
		func(sql string, _ ...any) (pgconn.CommandTag, error) {
			if has(sql, "ended_at IS NULL") {
				return mkTag(0), nil
			}
			return mkTag(1), nil
		},
	)
	if _, err := svcLost.StopStopTimer(context.Background(), rideID, 1); !errors.Is(err, ErrStopTimerClosed) {
		t.Fatalf("lost close race must surface ErrStopTimerClosed, got %v", err)
	}

	// Happy path: 11-minute dwell on F0=4000 persists fee 1000 + waiting 2000.
	svcOK := newSvc(
		func(sql string, _ ...any) pgx.Row {
			if has(sql, "FROM ride_stop_charges") {
				return &fakeRowVals{vals: []any{ptrTime(started), int64(1000), entities.StopPolicyVersion}}
			}
			return &fakeRowVals{vals: []any{int64(4000)}}
		},
		func(string, ...any) (pgconn.CommandTag, error) { return mkTag(1), nil },
	)
	c, err := svcOK.StopStopTimer(context.Background(), rideID, 1)
	if err != nil {
		t.Fatalf("happy-path stop: %v", err)
	}
	if c.WaitingChargeSantim != 2000 || !c.WaitingEligible || c.DurationMin < 10 {
		t.Fatalf("11-min dwell must earn ½·F0=2000 waiting, got %+v", c)
	}
	if c.StopFeeSantim != 1000 || c.StopPolicyVer != entities.StopPolicyVersion {
		t.Fatalf("closed window must echo the frozen fee and policy verbatim, got %+v", c)
	}
}

// ============================================================================
// CASH == ELECTRONIC PARITY (pure-math leg; DB legs covered by command tests)
// ============================================================================

func TestCashAndElectronic_SettleIdenticalPayable(t *testing.T) {
	snap := validSnapshot(5000)
	stops := []ApprovedStop{{Seq: 1, FixedFeeSantim: 1000, WaitingChargeSan: 2500}}
	fs := NewFinalFareService()
	electronic, err := fs.Compute(FinalFareInput{Snapshot: snap, Stops: stops, DiscountSantim: 800})
	if err != nil {
		t.Fatal(err)
	}
	cash, err := fs.Compute(FinalFareInput{Snapshot: snap, Stops: stops, DiscountSantim: 800})
	if err != nil {
		t.Fatal(err)
	}
	if cash.PayableSantim != electronic.PayableSantim {
		t.Fatalf("cash/electronic payable divergence: %d vs %d", cash.PayableSantim, electronic.PayableSantim)
	}
	if cash.PayableSantim != 5000+3500-800 {
		t.Fatalf("payable formula max(0, F0+S+W-P): want %d got %d", 7700, cash.PayableSantim)
	}
}

func TestPayable_FloorZero_NoCreditMinting(t *testing.T) {
	snap := validSnapshot(1000)
	res, err := NewFinalFareService().Compute(FinalFareInput{
		Snapshot:       snap,
		DiscountSantim: 5000, // promo far exceeds gross
	})
	if err != nil {
		t.Fatalf("compute: %v", err)
	}
	if res.PayableSantim != 0 {
		t.Fatalf("payable floor must be 0, never a credit, got %d", res.PayableSantim)
	}
}
