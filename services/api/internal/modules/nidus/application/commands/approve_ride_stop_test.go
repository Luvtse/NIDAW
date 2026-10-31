// Package commands — NIDAW FARE INTEGRITY (Phase 2) tests.
//
// ApproveRideStopHandler is fully port-driven (RideStopLister,
// FareSnapshotGetter, StopApprovalStore), so these are pure-logic tests with
// tiny in-memory fakes — no Postgres required. Coverage mirrors §2.4:
// sequence bounds, stop-must-exist, contract-required fail-closed,
// exactly-once replay passthrough, and the disclosure echo (fee + conditional
// waiting charge + non-compounding F0 base).
package commands

import (
	"context"
	"errors"
	"testing"
	"time"

	"nidaw-backend/internal/modules/nidus/application/services"
	"nidaw-backend/internal/modules/nidus/domain/entities"

	"github.com/google/uuid"
)

// ============================================================================
// FAKES
// ============================================================================

type fakeStopLister struct {
	stops []entities.RideStop
	err   error
}

func (f fakeStopLister) ListStops(_ context.Context, _ uuid.UUID) ([]entities.RideStop, error) {
	return f.stops, f.err
}

type fakeSnapshotGetter struct {
	snap *entities.FareSnapshot
	err  error
}

func (f fakeSnapshotGetter) GetSnapshotByRideID(_ context.Context, _ uuid.UUID) (*entities.FareSnapshot, error) {
	return f.snap, f.err
}

type fakeApprovalStore struct {
	preview     *services.StopQuotePreview
	quoteErr    error
	charge      *entities.StopCharge
	approveErr  error
	gotRiderID  uuid.UUID
	gotSeq      int
	gotRideID   uuid.UUID
	approveCall int
}

func (f *fakeApprovalStore) QuoteStop(_ context.Context, _ uuid.UUID, _ int) (*services.StopQuotePreview, error) {
	if f.quoteErr != nil {
		return nil, f.quoteErr
	}
	return f.preview, nil
}

func (f *fakeApprovalStore) ApproveStop(_ context.Context, rideID, riderUserID uuid.UUID, seq int) (*entities.StopCharge, error) {
	f.approveCall++
	f.gotRideID, f.gotRiderID, f.gotSeq = rideID, riderUserID, seq
	if f.approveErr != nil {
		return nil, f.approveErr
	}
	return f.charge, nil
}

// validSnapshot builds a snapshot that passes entities validation:
// components sum == gross (no floor applied), ETB currency, positive total.
func validSnapshot(f0 int64) *entities.FareSnapshot {
	now := time.Now().UTC()
	return &entities.FareSnapshot{
		ID:                  uuid.New(),
		IdempotencyKey:      "booking:test-ride",
		PickupLat:           9.03,
		PickupLng:           38.74,
		DropoffLat:          8.99,
		DropoffLng:          38.76,
		ContractDistanceKm:  10,
		ContractDurationMin: 30,
		Components: entities.FareComponents{
			BaseFareSantim:     5000,
			DistanceFareSantim: 30000,
			TimeFareSantim:     15000,
			SurgeAmountSantim:  0,
			MinimumFareSantim:  5000,
			GrossFareSantim:    f0, // equals SumSantim below
			RideType:           "standard",
			DistanceRatePerKm:  30.0,
			TimeRatePerMinute:  5.0,
			SurgeMultiplier:    1.0,
		},
		PricingConfigVersion: "v1",
		DurationRuleVersion:  "tpkm-v1",
		MinutesPerKm:         3.0,
		Currency:             entities.CurrencyETB,
		QuotedTotalSantim:    f0,
		FrozenAt:             now,
	}
}

func defaultPreview(f0 int64) *services.StopQuotePreview {
	return &services.StopQuotePreview{
		Seq:                       1,
		FixedFeeSantim:            2000,
		WaitingChargeIfLongSantim: f0 / 2, // 50% of ORIGINAL booking fare
		WaitingThresholdMinutes:   10,
		PolicyVersion:             "stops-v1",
		Currency:                  entities.CurrencyETB,
	}
}

func approvedCharge(seq int, fee int64) *entities.StopCharge {
	at := time.Now().UTC()
	return &entities.StopCharge{
		Seq:                 seq,
		StopFeeSantim:       fee,
		StopPolicyVer:       "stops-v1",
		ApprovedByRider:     true,
		ApprovedAt:          &at,
		WaitingEligible:     true,
		WaitingChargeSantim: 0, // dwell not measured yet at approval time
	}
}

func newTestHandler(stops []entities.RideStop, snap *entities.FareSnapshot, store *fakeApprovalStore) *ApproveRideStopHandler {
	return NewApproveRideStopHandler(
		fakeStopLister{stops: stops},
		fakeSnapshotGetter{snap: snap},
		store,
	)
}

// ============================================================================
// TESTS
// ============================================================================

func TestApproveRideStop_SeqBounds(t *testing.T) {
	rideID := uuid.New()
	rider := uuid.New()
	h := newTestHandler([]entities.RideStop{{Seq: 1}}, validSnapshot(50000), &fakeApprovalStore{})

	for _, seq := range []int{0, -1, entities.MaxRideStops + 1, 4} {
		_, err := h.Execute(context.Background(), ApproveRideStopCommand{RideID: rideID, RiderUserID: rider, Seq: seq})
		if !errors.Is(err, entities.ErrStopSeqOutOfRange) {
			t.Errorf("seq %d: want ErrStopSeqOutOfRange, got %v", seq, err)
		}
	}
}

func TestApproveRideStop_StopNotOnRide(t *testing.T) {
	rideID := uuid.New()
	h := newTestHandler(
		[]entities.RideStop{{Seq: 1}, {Seq: 3}}, // seq 2 was never added
		validSnapshot(50000),
		&fakeApprovalStore{},
	)
	_, err := h.Execute(context.Background(), ApproveRideStopCommand{
		RideID: rideID, RiderUserID: uuid.New(), Seq: 2,
	})
	if !errors.Is(err, entities.ErrStopSeqOutOfRange) {
		t.Fatalf("want ErrStopSeqOutOfRange for absent waypoint, got %v", err)
	}
}

func TestApproveRideStop_ListerErrorPropagates(t *testing.T) {
	boom := errors.New("db down")
	h := newTestHandler(nil, validSnapshot(50000), &fakeApprovalStore{})
	h.stops = fakeStopLister{err: boom}
	_, err := h.Execute(context.Background(), ApproveRideStopCommand{
		RideID: uuid.New(), RiderUserID: uuid.New(), Seq: 1,
	})
	if !errors.Is(err, boom) {
		t.Fatalf("want wrapped lister error, got %v", err)
	}
}

func TestApproveRideStop_NilSnapshotFailsClosed(t *testing.T) {
	h := newTestHandler([]entities.RideStop{{Seq: 1}}, nil, &fakeApprovalStore{})
	_, err := h.Execute(context.Background(), ApproveRideStopCommand{
		RideID: uuid.New(), RiderUserID: uuid.New(), Seq: 1,
	})
	if !errors.Is(err, ErrApproveStopNoContract) {
		t.Fatalf("nil contract: want ErrApproveStopNoContract, got %v", err)
	}
}

func TestApproveRideStop_InvalidSnapshotFailsClosed(t *testing.T) {
	snap := validSnapshot(50000)
	snap.Currency = "USD" // ETB-only invariant must reject this before any write
	h := newTestHandler([]entities.RideStop{{Seq: 1}}, snap, &fakeApprovalStore{})
	_, err := h.Execute(context.Background(), ApproveRideStopCommand{
		RideID: uuid.New(), RiderUserID: uuid.New(), Seq: 1,
	})
	if !errors.Is(err, ErrApproveStopNoContract) {
		t.Fatalf("invalid contract: want ErrApproveStopNoContract, got %v", err)
	}
}

func TestApproveRideStop_SnapshotReadErrorMapsToNoContract(t *testing.T) {
	h := newTestHandler([]entities.RideStop{{Seq: 1}}, nil, &fakeApprovalStore{})
	h.snapshots = fakeSnapshotGetter{err: errors.New("read failed")}
	_, err := h.Execute(context.Background(), ApproveRideStopCommand{
		RideID: uuid.New(), RiderUserID: uuid.New(), Seq: 1,
	})
	if !errors.Is(err, ErrApproveStopNoContract) {
		t.Fatalf("want stable no-contract code on read failure, got %v", err)
	}
}

func TestApproveRideStop_ReplayPassthrough(t *testing.T) {
	store := &fakeApprovalStore{
		preview:    defaultPreview(50000),
		approveErr: entities.ErrStopAlreadyApproved,
	}
	h := newTestHandler([]entities.RideStop{{Seq: 1}}, validSnapshot(50000), store)

	_, err := h.Execute(context.Background(), ApproveRideStopCommand{
		RideID: uuid.New(), RiderUserID: uuid.New(), Seq: 1,
	})
	if !errors.Is(err, entities.ErrStopAlreadyApproved) {
		t.Fatalf("replayed approval must surface ErrStopAlreadyApproved unchanged, got %v", err)
	}
	if store.approveCall != 1 {
		t.Fatalf("store called %d times, want exactly 1 (no double-minting)", store.approveCall)
	}
}

func TestApproveRideStop_OwnershipErrorPassthrough(t *testing.T) {
	store := &fakeApprovalStore{
		preview:    defaultPreview(50000),
		approveErr: services.ErrStopNotRideOwner,
	}
	h := newTestHandler([]entities.RideStop{{Seq: 1}}, validSnapshot(50000), store)
	_, err := h.Execute(context.Background(), ApproveRideStopCommand{
		RideID: uuid.New(), RiderUserID: uuid.New(), Seq: 1,
	})
	if !errors.Is(err, services.ErrStopNotRideOwner) {
		t.Fatalf("non-owner must get ownership error, got %v", err)
	}
}

func TestApproveRideStop_SuccessEchoesDisclosure(t *testing.T) {
	const f0 = int64(50000) // original booking fare, ETB santim
	rideID := uuid.New()
	rider := uuid.New()

	store := &fakeApprovalStore{
		preview: defaultPreview(f0),
		charge:  approvedCharge(2, 2000),
	}
	h := newTestHandler([]entities.RideStop{{Seq: 1}, {Seq: 2}}, validSnapshot(f0), store)

	res, err := h.Execute(context.Background(), ApproveRideStopCommand{
		RideID: rideID, RiderUserID: rider, Seq: 2,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Identity + persisted state echoed exactly.
	if res.RideID != rideID || res.Seq != 2 || !res.ApprovedByRider {
		t.Errorf("echo mismatch: %+v", res)
	}
	if res.StopFeeSantim != 2000 || res.PolicyVersion != "stops-v1" {
		t.Errorf("fee/policy mismatch: %+v", res)
	}
	if res.Currency != entities.CurrencyETB {
		t.Errorf("currency must be ETB, got %s", res.Currency)
	}

	// Disclosure: waiting charge is 50% of the ORIGINAL booking fare F0 —
	// non-compounding by construction (never F0+other stop fees).
	if res.WaitingChargeIfLongSantim != f0/2 {
		t.Errorf("waiting charge %d, want F0/2=%d (non-compounding)", res.WaitingChargeIfLongSantim, f0/2)
	}
	if res.OriginalBookingFareSantim != f0 {
		t.Errorf("F0 echo %d, want %d", res.OriginalBookingFareSantim, f0)
	}
	if res.WaitingThresholdMinutes != 10 {
		t.Errorf("threshold %d, want 10 minutes", res.WaitingThresholdMinutes)
	}

	// Trusted identity forwarded untouched to the sole writer.
	if store.gotRideID != rideID || store.gotRiderID != rider || store.gotSeq != 2 {
		t.Errorf("store received (%v,%v,%d), want (%v,%v,2)",
			store.gotRideID, store.gotRiderID, store.gotSeq, rideID, rider)
	}
}

func TestApproveRideStop_MissingCollaboratorsFailLoud(t *testing.T) {
	h := &ApproveRideStopHandler{} // zero value — production wiring forbids this
	_, err := h.Execute(context.Background(), ApproveRideStopCommand{
		RideID: uuid.New(), RiderUserID: uuid.New(), Seq: 1,
	})
	if err == nil {
		t.Fatal("unconfigured handler must refuse rather than half-work")
	}
}
