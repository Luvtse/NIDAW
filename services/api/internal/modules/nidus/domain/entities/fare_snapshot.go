// Package entities — NIDAW FARE INTEGRITY (Phase 1): the immutable booking
// pricing snapshot.
//
// A FareSnapshot is the authoritative fare agreement between rider and driver,
// frozen by the server at ride-request time from the ORIGINAL pickup/dropoff
// coordinates and the versioned pricing rules in force at that moment. It is
// the contract: actual GPS distance, elapsed time, driver-reported metrics or
// route deviations may be recorded for operations/safety/analytics but must
// NEVER overwrite ContractDistanceKm or ContractDurationMin, and must never
// silently increase the payable fare.
//
// Monetary invariant: every *_santim field below is an integer ETB minor unit
// (1 ETB = 100 santim). The snapshot currency is always "ETB"; anything else
// is a data-integrity violation surfaced as ErrFareSnapshotCurrency rather
// than coerced. Major-unit (decimal Birr) views of these amounts are derived
// at display boundaries only, never persisted back into the snapshot.
package entities

import (
	"errors"
	"time"

	"github.com/google/uuid"
)

// ============================================================================
// FARE SNAPSHOT ERRORS
// ============================================================================

var (
	// ErrFareSnapshotNil means a code path reached settlement without ever
	// freezing a booking contract. This is a programming/data error, never a
	// user-facing condition; the lifecycle layer refuses to complete such a
	// ride rather than inventing a price.
	ErrFareSnapshotNil = errors.New("fare snapshot is missing")

	// ErrFareSnapshotCurrency guards the ETB-only invariant on the snapshot.
	// A snapshot carrying any currency other than ETB is rejected loudly —
	// silent relabeling of historical USD rows is explicitly forbidden.
	ErrFareSnapshotCurrency = errors.New("fare snapshot currency must be ETB")

	// ErrFareSnapshotMismatch means the snapshot's components do not reconcile
	// with its own quoted total (base+distance+time+surge+min-uplift != total).
	// Only possible from a corrupted persistence round-trip; refuse to settle.
	ErrFareSnapshotMismatch = errors.New("fare snapshot components do not reconcile with quoted total")
)

// CurrencyETB is the single supported runtime currency across NIDAW money
// paths. Display labels, payment intents, ledger entries and receipts all
// resolve to this constant; there is no second supported currency.
const CurrencyETB = "ETB"

// SantimPerBirr is the fixed ETB minor-unit scale used by every monetary
// conversion boundary (quote -> entity float columns, events, receipts).
const SantimPerBirr = 100

// ============================================================================
// FARE COMPONENTS (integer santim)
// ============================================================================

// FareComponents is the itemized breakdown carried inside a snapshot. All
// fields are integer santim. BaseFareSantim already includes any minimum-fare
// uplift folded in at quote time, so:
//
//	GrossFareSantim == max(Base + Distance + Time + Surge, MinimumFare)
//
// holds by construction and TotalPayableSantim equals GrossFareSantim minus
// nothing (discounts are applied downstream at settlement, never rewritten
// into the frozen gross).
type FareComponents struct {
	BaseFareSantim     int64   `json:"base_fare_santim" db:"base_fare_santim"`
	DistanceFareSantim int64   `json:"distance_fare_santim" db:"distance_fare_santim"`
	TimeFareSantim     int64   `json:"time_fare_santim" db:"time_fare_santim"`
	SurgeAmountSantim  int64   `json:"surge_amount_santim" db:"surge_amount_santim"`
	MinimumFareSantim  int64   `json:"minimum_fare_santim" db:"minimum_fare_santim"`
	GrossFareSantim    int64   `json:"gross_fare_santim" db:"gross_fare_santim"`
	RideType           string  `json:"ride_type" db:"ride_type"`
	DistanceRatePerKm  float64 `json:"distance_rate_per_km_birr" db:"distance_rate_per_km"`
	TimeRatePerMinute  float64 `json:"time_rate_per_minute_birr" db:"time_rate_per_minute"`
	SurgeMultiplier    float64 `json:"surge_multiplier" db:"surge_multiplier"`
	SurgeReason        string  `json:"surge_reason,omitempty" db:"surge_reason"`
}

// SumSantim returns base+distance+time+surge before the minimum-fare floor —
// the value compared against MinimumFareSantim when reconciling a snapshot.
func (c FareComponents) SumSantim() int64 {
	return c.BaseFareSantim + c.DistanceFareSantim + c.TimeFareSantim + c.SurgeAmountSantim
}

// ============================================================================
// SNAPSHOT
// ============================================================================

// FareSnapshot is the immutable pricing contract created when the rider
// confirms a booking and read by every later stage (dispatch, driver app,
// completion, receipt, ledger, payment provider). Treat it as read-only after
// creation: corrections happen through NEW approved additions (stops), never
// by mutating frozen fields.
//
// Versioning: PricingConfigVersion and DurationRuleVersion pin the exact rule
// set that produced the numbers, so a later config change can never re-derive
// a different amount for an old ride. IdempotencyKey makes re-persistence
// safe: creating the same key twice must return the original row unchanged.
type FareSnapshot struct {
	ID            uuid.UUID `json:"id" db:"id"`
	RideID        uuid.UUID `json:"ride_id" db:"ride_id"`
	IdempotencyKey string   `json:"idempotency_key" db:"idempotency_key"`

	// Original endpoints — the contract geometry. Later destination changes
	// produce APPROVED AMENDMENTS (a new snapshot revision), never an edit of
	// these coordinates.
	PickupLat       float64 `json:"pickup_lat" db:"pickup_lat"`
	PickupLng       float64 `json:"pickup_lng" db:"pickup_lng"`
	DropoffLat      float64 `json:"dropoff_lat" db:"dropoff_lat"`
	DropoffLng      float64 `json:"dropoff_lng" db:"dropoff_lng"`
	PickupAddress   string  `json:"pickup_address,omitempty" db:"pickup_address"`
	DropoffAddress  string  `json:"dropoff_address,omitempty" db:"dropoff_address"`

	// Contractual trip shape (frozen): authoritative route distance over the
	// ORIGINAL endpoints and the agreed billable duration derived from the
	// versioned minutes-per-kilometre rule. Actual metrics live on the ride
	// row and are for operations only.
	ContractDistanceKm   float64 `json:"contract_distance_km" db:"contract_distance_km"`
	ContractDurationMin  int     `json:"contract_duration_minutes" db:"contract_duration_min"`

	// Frozen pricing rules and the resulting breakdown (all money in santim).
	Components          FareComponents `json:"components" db:"components"`
	PricingConfigVersion   string `json:"pricing_config_version" db:"pricing_config_version"`
	DurationRuleVersion    string `json:"duration_rule_version" db:"duration_rule_version"`
	MinutesPerKm               float64 `json:"minutes_per_km" db:"minutes_per_km"`
	Currency                     string `json:"currency" db:"currency"`

	// QuotedTotalSantim is what the rider saw and accepted: the gross fare
	// after surge and the minimum-fare floor, BEFORE promotions/stops/tips.
	QuotedTotalSantim int64 `json:"quoted_total_santim" db:"quoted_total_santim"`

	FrozenAt time.Time `json:"frozen_at" db:"frozen_at"`
}

// Validate enforces the snapshot's invariants: ETB currency, positive quoted
// total, and component reconciliation (sum before floor equals the gross when
// no uplift occurred; otherwise the gross equals the minimum fare exactly).
func (s *FareSnapshot) Validate() error {
	if s == nil {
		return ErrFareSnapshotNil
	}
	if s.Currency != CurrencyETB {
		return ErrFareSnapshotCurrency
	}
	if s.QuotedTotalSantim <= 0 {
		return ErrFareSnapshotMismatch
	}
	sum := s.Components.SumSantim()
	switch {
	case s.Components.GrossFareSantim < sum:
		// Gross below the raw component sum: someone lowered a frozen number.
		return ErrFareSnapshotMismatch
	case sum >= s.Components.MinimumFareSantim && s.Components.GrossFareSantim != sum:
		// No floor applied yet gross differs from the sum.
		return ErrFareSnapshotMismatch
	case sum < s.Components.MinimumFareSantim && s.Components.GrossFareSantim != s.Components.MinimumFareSantim:
		// Floor applied but gross is neither the sum nor the minimum.
		return ErrFareSnapshotMismatch
	}
	return nil
}

// QuotedTotalBirr derives the major-unit view of the frozen quote for legacy
// NUMERIC(10,2) display columns. Deterministic half-up rounding to santim is
// guaranteed by construction (the source is already integer santim).
func (s *FareSnapshot) QuotedTotalBirr() float64 {
	return float64(s.QuotedTotalSantim) / float64(SantimPerBirr)
}
