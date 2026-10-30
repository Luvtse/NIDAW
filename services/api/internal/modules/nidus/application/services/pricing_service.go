package services

import (
	"context"
	"errors"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"nidaw-backend/internal/modules/nidus/domain/entities"
	"nidaw-backend/internal/shared/database"
)

// ============================================================================
// ERRORS
// ============================================================================

var (
	ErrInvalidLocation = errors.New("invalid pickup or dropoff location")
	ErrPricingFailed   = errors.New("failed to calculate fare")
	// ErrUnsupportedCurrency is the fail-closed guard for the ETB-only
	// invariant: no code path may silently coerce or relabel a non-ETB
	// currency into a quote or snapshot.
	ErrUnsupportedCurrency = errors.New("unsupported currency: NIDAW pricing is ETB-only")
)

// ============================================================================
// TYPES
// ============================================================================

// RideType represents the type of ride
type RideType string

const (
	RideTypeStandard   RideType = "standard"
	RideTypePremium    RideType = "premium"
	RideTypeElectric   RideType = "electric"
	RideTypeShared     RideType = "shared"
	RideTypeWheelchair RideType = "wheelchair"
)

// PricingConfig holds the pricing configuration. Phase 1 (fare integrity):
// every default is expressed in ETB — base fares and minimum fares in integer
// santim, distance/time rates in ETB major units per km / per minute. There
// are no USD fallbacks anywhere in this struct or its constructors; a config
// that fails Validate() cannot produce quotes.
type PricingConfig struct {
	// Base fare (in ETB santim)
	BaseFare map[RideType]int64

	// Per-kilometer rate (ETB major units per km)
	PerKmRate map[RideType]float64

	// Per-minute monetary rate (ETB major units per billable minute).
	// NOT a duration rule: the contractual minutes-per-km lives in
	// ContractualDurationRule (contractual_duration_service.go). The two must
	// never be conflated.
	PerMinuteRate map[RideType]float64

	// Minimum fare (ETB santim)
	MinimumFare map[RideType]int64

	// Maximum surge multiplier
	MaxSurgeMultiplier float64

	// Currency is always ETB; kept as a field so snapshots carry the frozen
	// currency label, but Validate rejects anything other than "ETB".
	DefaultCurrency string

	// Version identifiers frozen into every snapshot so historical rides keep
	// their original rules regardless of later config changes.
	ConfigVersion string

	// DurationRuleVersion names the active minutes-per-km contract rule
	// (see ContractualDurationRule registry).
	DurationRuleVersion string

	// MinutesPerKm mirrors the frozen duration rule's parameter for display
	// and disclosure ("~3 min/km") without re-looking it up everywhere.
	MinutesPerKm float64
}

// knownRideTypes lists every ride type a complete pricing config must cover.
var knownRideTypes = []RideType{
	RideTypeStandard, RideTypePremium, RideTypeElectric, RideTypeShared, RideTypeWheelchair,
}

// Validate enforces the ETB-only invariant and unit sanity:
//   - currency must be exactly "ETB" (USD or any other code is rejected, not
//     coerced);
//   - every ride type needs a positive base fare, minimum fare, per-km rate
//     and per-minute rate;
//   - all rates finite and non-negative; surge cap within [1, 10];
//   - the duration rule version must exist in the frozen registry and carry a
//     positive minutes-per-km value.
func (c *PricingConfig) Validate() error {
	if c == nil {
		return errors.New("pricing config is nil")
	}
	if c.DefaultCurrency != "ETB" {
		return fmt.Errorf("unsupported pricing currency %q: NIDAW is ETB-only", c.DefaultCurrency)
	}
	for _, rt := range knownRideTypes {
		if c.BaseFare[rt] <= 0 {
			return fmt.Errorf("pricing config: base fare (santim) for %s must be positive", rt)
		}
		if c.MinimumFare[rt] <= 0 {
			return fmt.Errorf("pricing config: minimum fare (santim) for %s must be positive", rt)
		}
		if r := c.PerKmRate[rt]; !(r > 0 && !math.IsNaN(r) && !math.IsInf(r, 0)) {
			return fmt.Errorf("pricing config: per-km rate (ETB/km) for %s must be a positive finite number", rt)
		}
		if r := c.PerMinuteRate[rt]; !(r > 0 && !math.IsNaN(r) && !math.IsInf(r, 0)) {
			return fmt.Errorf("pricing config: per-minute rate (ETB/min) for %s must be a positive finite number", rt)
		}
	}
	if c.MaxSurgeMultiplier < 1 || c.MaxSurgeMultiplier > 10 ||
		math.IsNaN(c.MaxSurgeMultiplier) || math.IsInf(c.MaxSurgeMultiplier, 0) {
		return errors.New("pricing config: max surge multiplier must be within [1, 10]")
	}
	rule, err := LookupDurationRule(c.DurationRuleVersion)
	if err != nil {
		return fmt.Errorf("pricing config: %w", err)
	}
	if c.MinutesPerKm <= 0 || math.IsNaN(c.MinutesPerKm) || math.IsInf(c.MinutesPerKm, 0) {
		return errors.New("pricing config: minutes-per-km duration rule must be a positive finite number")
	}
	if c.ConfigVersion == "" {
		return errors.New("pricing config: ConfigVersion is required (snapshots pin it)")
	}
	_ = rule // registry existence check above is the validation
	return nil
}

// DefaultPricingConfig returns the approved ETB pricing configuration
// (Addis Ababa corridor, santim-native). These values replaced the historical
// USD-denominated defaults; they are DISPLAY/DEV conveniences only — the
// production server boots from PricingConfigFromEnvironment and fails closed
// when env values are missing outside development.
func DefaultPricingConfig() *PricingConfig {
	rule, _ := LookupDurationRule(DefaultDurationRuleVersion)
	return &PricingConfig{
		BaseFare: map[RideType]int64{
			RideTypeStandard:   5000,  // Br 50.00
			RideTypePremium:    12000, // Br 120.00
			RideTypeElectric:   7000,  // Br 70.00
			RideTypeShared:     3000,  // Br 30.00
			RideTypeWheelchair: 6000,  // Br 60.00
		},
		PerKmRate: map[RideType]float64{
			RideTypeStandard:   15.00,
			RideTypePremium:    30.00,
			RideTypeElectric:   18.00,
			RideTypeShared:     8.00,
			RideTypeWheelchair: 17.00,
		},
		PerMinuteRate: map[RideType]float64{
			RideTypeStandard:   3.00,
			RideTypePremium:    6.00,
			RideTypeElectric:   3.50,
			RideTypeShared:     1.50,
			RideTypeWheelchair: 3.50,
		},
		MinimumFare: map[RideType]int64{
			RideTypeStandard:   8000,  // Br 80.00
			RideTypePremium:    20000, // Br 200.00
			RideTypeElectric:   12000, // Br 120.00
			RideTypeShared:     5000,  // Br 50.00
			RideTypeWheelchair: 10000, // Br 100.00
		},
		MaxSurgeMultiplier:  3.5,
		DefaultCurrency:     "ETB",
		ConfigVersion:       "etb-v1",
		DurationRuleVersion: rule.Version,
		MinutesPerKm:        rule.MinutesPerKm,
	}
}

// PricingConfigFromEnvironment builds the authoritative ETB pricing config
// from NIDUS_PRICING_* environment variables. Phase 1 hardening:
//   - the currency argument is IGNORED unless it is "ETB"; any other value
//     (including the legacy "USD") fails closed rather than being accepted —
//     silent coercion of unsupported currencies is forbidden;
//   - amounts are parsed directly as santim integers via
//     NIDUS_PRICING_<TYPE>_BASE_FARE_SANTIM etc., eliminating float parsing
//     on money paths; decimal-major variants remain accepted for rates;
//   - the contractual duration rule is loaded from the frozen registry
//     (NIDUS_DURATION_RULE_VERSION) and validated separately from the
//     monetary per-minute rate.
func PricingConfigFromEnvironment(defaultCurrency string) (*PricingConfig, error) {
	currency := strings.ToUpper(strings.TrimSpace(defaultCurrency))
	if currency == "" {
		currency = "ETB"
	}
	if currency != "ETB" {
		return nil, fmt.Errorf("unsupported pricing currency %q: NIDAW is ETB-only", defaultCurrency)
	}
	config := &PricingConfig{
		BaseFare:           make(map[RideType]int64),
		PerKmRate:          make(map[RideType]float64),
		PerMinuteRate:      make(map[RideType]float64),
		MinimumFare:        make(map[RideType]int64),
		MaxSurgeMultiplier: envFloatOr("NIDUS_MAX_SURGE_MULTIPLIER", 3.5),
		DefaultCurrency:    "ETB",
		ConfigVersion:      envStringOr("NIDUS_PRICING_CONFIG_VERSION", "etb-v1"),
	}
	rule, err := DurationRuleFromEnvironment()
	if err != nil {
		return nil, err
	}
	config.DurationRuleVersion = rule.Version
	config.MinutesPerKm = rule.MinutesPerKm

	for _, rideType := range knownRideTypes {
		prefix := "NIDUS_PRICING_" + strings.ToUpper(string(rideType)) + "_"
		base, err := requiredSantim(prefix + "BASE_FARE_SANTIM", prefix+"BASE_FARE")
		if err != nil {
			return nil, err
		}
		perKm, err := requiredRate(prefix + "PER_KM_RATE")
		if err != nil {
			return nil, err
		}
		perMinute, err := requiredRate(prefix + "PER_MINUTE_RATE")
		if err != nil {
			return nil, err
		}
		minimum, err := requiredSantim(prefix + "MINIMUM_FARE_SANTIM", prefix+"MINIMUM_FARE")
		if err != nil {
			return nil, err
		}
		config.BaseFare[rideType] = base
		config.PerKmRate[rideType] = perKm
		config.PerMinuteRate[rideType] = perMinute
		config.MinimumFare[rideType] = minimum
	}
	if err := config.Validate(); err != nil {
		return nil, err
	}
	return config, nil
}

func envStringOr(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func envFloatOr(key string, def float64) float64 {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return def
	}
	v, err := strconv.ParseFloat(raw, 64)
	if err != nil || math.IsNaN(v) || math.IsInf(v, 0) {
		return def
	}
	return v
}

// requiredSantim reads an integer-minor-unit amount from `key` (preferred,
// e.g. *_BASE_FARE_SANTIM) falling back to the legacy major-unit key (e.g.
// *_BASE_FARE, decimal Birr -> santim with deterministic half-up rounding).
// Both forms must be finite and non-negative; the minor-unit form is exact.
func requiredSantim(key, legacyMajorKey string) (int64, error) {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw != "" {
		amount, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || amount < 0 {
			return 0, errors.New(key + " must be a non-negative integer amount in santim (ETB minor units)")
		}
		return amount, nil
	}
	return requiredMajorAmount(legacyMajorKey)
}

func requiredMajorAmount(key string) (int64, error) {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return 0, errors.New(key + " is required")
	}
	amount, err := strconv.ParseFloat(raw, 64)
	if err != nil || math.IsNaN(amount) || math.IsInf(amount, 0) || amount < 0 || amount > 9.22e14 {
		return 0, errors.New(key + " must be a finite non-negative amount in major currency units (ETB)")
	}
	return int64(math.Round(amount * 100)), nil
}

func requiredRate(key string) (float64, error) {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return 0, errors.New(key + " is required")
	}
	rate, err := strconv.ParseFloat(raw, 64)
	if err != nil || math.IsNaN(rate) || math.IsInf(rate, 0) || rate < 0 {
		return 0, errors.New(key + " must be a finite non-negative rate in ETB major units")
	}
	return rate, nil
}

// RideTypeDisplay carries UI-facing metadata for a ride type. §2.6: the
// estimate carousel renders display name, capacity, and icon key from here —
// never from client-side hardcoded card definitions.
type RideTypeDisplay struct {
	DisplayName string `json:"display_name"`
	Description string `json:"description"`
	Capacity    int    `json:"capacity"`
	IconKey     string `json:"icon_key"`
}

var rideTypeDisplays = map[RideType]RideTypeDisplay{
	RideTypeStandard:   {DisplayName: "Standard", Description: "Affordable everyday rides", Capacity: 4, IconKey: "car"},
	RideTypePremium:    {DisplayName: "Premium", Description: "Top drivers in high-end cars", Capacity: 4, IconKey: "star"},
	RideTypeElectric:   {DisplayName: "Electric", Description: "Zero-emission electric vehicles", Capacity: 4, IconKey: "electric_car"},
	RideTypeShared:     {DisplayName: "Shared", Description: "Split the ride, split the fare", Capacity: 1, IconKey: "groups"},
	RideTypeWheelchair: {DisplayName: "Wheelchair", Description: "Wheelchair-accessible vehicles", Capacity: 6, IconKey: "accessible"},
}

// RideTypeDisplayFor returns the display metadata for a ride type. Unknown
// types fall back to a capitalized raw name with honest zero-capacity so the
// UI can render "Not provided" rather than fabricate values.
func RideTypeDisplayFor(t RideType) RideTypeDisplay {
	if d, ok := rideTypeDisplays[t]; ok {
		return d
	}
	return RideTypeDisplay{DisplayName: string(t), Description: "", Capacity: 0, IconKey: "car"}
}

// FareEstimate contains the full fare breakdown. Phase 1 (fare integrity):
// all monetary fields are integer ETB santim (1 ETB = 100 santim) and the
// billable duration is the CONTRACTUAL duration derived from the route
// distance via the versioned minutes-per-km rule — never a live-traffic or
// time-of-day estimate. DistanceKm/DurationMinutes describe the frozen
// contract; EstimatedPickup remains an operational ETA display input only and
// must not be used for pricing.
type FareEstimate struct {
	RideType        RideType  `json:"ride_type"`
	BaseFare        int64     `json:"base_fare_santim"`     // ETB santim
	DistanceFare    int64     `json:"distance_fare_santim"` // ETB santim
	TimeFare        int64     `json:"time_fare_santim"`     // ETB santim
	Subtotal        int64     `json:"subtotal_santim"`      // ETB santim
	SurgeMultiplier float64   `json:"surge_multiplier"`
	SurgeReason     string    `json:"surge_reason"`
	SurgeAmount     int64     `json:"surge_amount_santim"` // ETB santim
	MinimumFare     int64     `json:"minimum_fare_santim"` // applied floor, ETB santim
	TotalFare       int64     `json:"total_fare_santim"`   // ETB santim (post-floor quote)
	Currency        string    `json:"currency"`            // always "ETB"
	DistanceKm      float64   `json:"contract_distance_km"`
	DurationMinutes int       `json:"contract_duration_minutes"`
	// OperationalDurationMinutes is the traffic/provider trip-time estimate
	// shown in the app for ETAs. It NEVER feeds money math — billable time is
	// DurationMinutes (contractual). Zero when running without a routing
	// provider and no heuristic was computed.
	OperationalDurationMinutes int    `json:"operational_duration_minutes"`
	ContractualDurationS       string `json:"contract_duration_display"`
	EstimatedPickup      int       `json:"estimated_pickup_minutes"`
	ConfigVersion        string    `json:"pricing_config_version"`
	DurationRuleVersion  string    `json:"duration_rule_version"`
	MinutesPerKm         float64   `json:"minutes_per_km"`
	CalculatedAt         time.Time `json:"calculated_at"`
}

// SnapshotFromEstimate freezes a FareEstimate produced by this service into
// the immutable booking contract entity (Phase 1). The snapshot carries the
// ORIGINAL endpoints of the priced chain, the contractual distance/duration,
// the component breakdown in santim, and the config/duration-rule versions —
// everything later stages need to honor "the quote IS the price" without ever
// re-deriving money from trip actuals. IdempotencyKey is supplied by the
// caller (typically the ride request id) so re-persistence returns the same
// row unchanged.
func (s *PricingService) SnapshotFromEstimate(
	est *FareEstimate,
	rideID uuid.UUID,
	idempotencyKey string,
	pickupLat, pickupLng float64,
	dropoffLat, dropoffLng float64,
	pickupAddress, dropoffAddress string,
) (*entities.FareSnapshot, error) {
	if est == nil {
		return nil, ErrPricingFailed
	}
	if est.Currency != entities.CurrencyETB {
		return nil, fmt.Errorf("%w: estimate currency %q", ErrUnsupportedCurrency, est.Currency)
	}
	snap := &entities.FareSnapshot{
		ID:                uuid.New(),
		RideID:            rideID,
		IdempotencyKey:    idempotencyKey,
		PickupLat:         pickupLat,
		PickupLng:         pickupLng,
		DropoffLat:        dropoffLat,
		DropoffLng:        dropoffLng,
		PickupAddress:     pickupAddress,
		DropoffAddress:    dropoffAddress,
		ContractDistanceKm: est.DistanceKm,
		ContractDurationMin: est.DurationMinutes,
		Components: entities.FareComponents{
			BaseFareSantim:     est.BaseFare,
			DistanceFareSantim: est.DistanceFare,
			TimeFareSantim:     est.TimeFare,
			SurgeAmountSantim:  est.SurgeAmount,
			MinimumFareSantim:  est.MinimumFare,
			GrossFareSantim:    est.TotalFare,
			RideType:           string(est.RideType),
			DistanceRatePerKm:  s.config.PerKmRate[est.RideType],
			TimeRatePerMinute:  s.config.PerMinuteRate[est.RideType],
			SurgeMultiplier:    est.SurgeMultiplier,
			SurgeReason:        est.SurgeReason,
		},
		PricingConfigVersion: est.ConfigVersion,
		DurationRuleVersion:  est.DurationRuleVersion,
		MinutesPerKm:         est.MinutesPerKm,
		Currency:             est.Currency,
		QuotedTotalSantim:    est.TotalFare,
		FrozenAt:             est.CalculatedAt.UTC(),
	}
	if err := snap.Validate(); err != nil {
		return nil, err
	}
	return snap, nil
}

// SurgeInfo contains information about current surge pricing
type SurgeInfo struct {
	Multiplier    float64 `json:"multiplier"`
	Reason        string  `json:"reason"`
	DemandLevel   string  `json:"demand_level"` // low, moderate, high, extreme
	ActiveDrivers int     `json:"active_drivers"`
	PendingRides  int     `json:"pending_rides"`
}

// ============================================================================
// PRICING SERVICE
// ============================================================================

// PricingService calculates ride fares with dynamic pricing
type PricingService struct {
	db      *database.Postgres
	config  *PricingConfig
	routing *RoutingClient
}

// NewPricingService creates a new pricing service
func NewPricingService(db *database.Postgres, config *PricingConfig) *PricingService {
	if config == nil {
		config = DefaultPricingConfig()
	}
	return &PricingService{
		db:      db,
		config:  config,
		routing: NewRoutingClientFromEnvironment(),
	}
}

// CalculateFare calculates the fare for a ride. It is the single-leg entry
// point kept byte-compatible for every pre-§3.5 caller; multi-waypoint trips
// go through CalculateFareWithStops, which degenerates to this exact math when
// stops is empty (regression guarantee).
func (s *PricingService) CalculateFare(
	ctx context.Context,
	pickupLat, pickupLng, dropoffLat, dropoffLng float64,
	rideType RideType,
) (*FareEstimate, error) {
	return s.CalculateFareWithStops(
		ctx,
		pickupLat, pickupLng,
		[]Waypoint{{Lat: dropoffLat, Lng: dropoffLng}}, // final element = dropoff
		rideType,
	)
}

// Waypoint is one coordinate in an ordered trip chain passed to
// CalculateFareWithStops. The chain is [stop1..stopN, dropoff]: intermediate
// stops first, destination last.
type Waypoint struct {
	Lat float64
	Lng float64
}

// CalculateFareWithStops prices a multi-leg trip (§3.5 Stopovers). Semantics:
//   - The base fare is charged ONCE for the whole trip, not per leg — a stop
//     adds distance/time, never a second flag-drop.
//   - Distance and duration are summed over each consecutive pair of the chain
//     [pickup, stops..., dropoff], each leg getting the same 1.3 road factor
//     and duration estimate as the single-leg path.
//   - Surge is computed from the pickup zone only (demand where the rider
//     boards), consistent with the single-leg behavior.
//   - Minimum fare applies to the trip total, exactly as before.
//
// With zero stops the arithmetic is identical to the historical two-point
// calculation, so existing fares do not move when this lands.
func (s *PricingService) CalculateFareWithStops(
	ctx context.Context,
	pickupLat, pickupLng float64,
	stops []Waypoint,
	rideType RideType,
) (*FareEstimate, error) {
	// A waypoint chain must contain at least the dropoff.
	if len(stops) == 0 {
		return nil, ErrInvalidLocation
	}

	// Validate coordinates across the full chain: every point in range, and
	// consecutive points distinct (a zero-length leg means the rider dropped a
	// pin on top of the previous one — reject rather than silently price it).
	chain := make([][2]float64, 0, len(stops)+1)
	chain = append(chain, [2]float64{pickupLat, pickupLng})
	for _, w := range stops {
		chain = append(chain, [2]float64{w.Lat, w.Lng})
	}
	if err := s.validateChain(chain); err != nil {
		return nil, err
	}

	// Sum distance over legs. Duration for PRICING is contractual (derived
	// from the total route distance via the versioned minutes-per-km rule at
	// the end of this function), so leg durations are not summed here; the
	// provider's reported duration is captured only as an operational display
	// signal (never money).
	var totalDistanceKm float64
	operationalDurationMinutes := 0
	for i := 0; i < len(chain)-1; i++ {
		if s.routing != nil {
			leg, err := s.routing.Route(ctx, chain[i][0], chain[i][1], chain[i+1][0], chain[i+1][1])
			if err != nil {
				return nil, fmt.Errorf("%w: %v", ErrPricingFailed, err)
			}
			totalDistanceKm += leg.DistanceKm
			operationalDurationMinutes += leg.DurationMinutes
			continue
		}
		legKm := haversineDistance(chain[i][0], chain[i][1], chain[i+1][0], chain[i+1][1])
		roadLegKm := legKm * 1.3 // road factor
		totalDistanceKm += roadLegKm
		operationalDurationMinutes += s.estimateDuration(roadLegKm)
	}

	// Contractual billable duration: Tc = ceil(Dc * MinutesPerKm), floored at
	// one minute — computed ONCE from the approved route distance and frozen
	// into the estimate/snapshot. Traffic conditions and driver behaviour can
	// never change it after booking confirmation.
	durationMinutes, durationRule, err := ContractualDurationForRideType(totalDistanceKm, s.config.DurationRuleVersion, rideType)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrPricingFailed, err)
	}

	// Get base fare (charged once per trip).
	baseFare, ok := s.config.BaseFare[rideType]
	if !ok {
		baseFare = s.config.BaseFare[RideTypeStandard]
	}

	perKmRate := s.config.PerKmRate[rideType]
	if perKmRate == 0 {
		perKmRate = s.config.PerKmRate[RideTypeStandard]
	}
	distanceFare := int64(math.Round(totalDistanceKm * perKmRate * 100)) // ETB -> santim

	perMinuteRate := s.config.PerMinuteRate[rideType]
	if perMinuteRate == 0 {
		perMinuteRate = s.config.PerMinuteRate[RideTypeStandard]
	}
	timeFare := int64(math.Round(float64(durationMinutes) * perMinuteRate * 100))

	subtotal := baseFare + distanceFare + timeFare

	surgeInfo, err := s.getSurgeInfo(ctx, pickupLat, pickupLng, rideType)
	if err != nil {
		// If surge calculation fails, use 1.0 (no surge)
		surgeInfo = &SurgeInfo{Multiplier: 1.0, Reason: "default"}
	}

	surgeAmount := int64(math.Round(float64(subtotal) * (surgeInfo.Multiplier - 1.0)))
	totalFare := subtotal + surgeAmount

	minimumFare := s.config.MinimumFare[rideType]
	if minimumFare == 0 {
		minimumFare = s.config.MinimumFare[RideTypeStandard]
	}
	if totalFare < minimumFare {
		totalFare = minimumFare
	}

	return &FareEstimate{
		RideType:             rideType,
		BaseFare:             baseFare,
		DistanceFare:         distanceFare,
		TimeFare:             timeFare,
		Subtotal:             subtotal,
		SurgeMultiplier:      surgeInfo.Multiplier,
		SurgeReason:          surgeInfo.Reason,
		SurgeAmount:          surgeAmount,
		MinimumFare:          minimumFare,
		TotalFare:            totalFare,
		Currency:             s.config.DefaultCurrency,
		DistanceKm:           math.Round(totalDistanceKm*100) / 100,
		DurationMinutes:      durationMinutes,
		OperationalDurationMinutes: operationalDurationMinutes,
		ContractualDurationS: FormatDurationMinutes(durationMinutes),
		EstimatedPickup:      s.estimatePickupTime(ctx, pickupLat, pickupLng),
		ConfigVersion:        s.config.ConfigVersion,
		DurationRuleVersion:  durationRule.Version,
		MinutesPerKm:         durationRule.MinutesPerKm,
		CalculatedAt:         time.Now(),
	}, nil
}

// GetFareEstimates returns fare estimates for all ride types. Phase 1: the
// per-type list is derived from pricing config keys (single source of truth)
// and a type whose quote fails to compute is surfaced as an error rather than
// silently skipped — hiding a priceable option misleads the rider, and hiding
// an unpriceable one while still dispatching it would break "the quote is the
// price".
func (s *PricingService) GetFareEstimates(
	ctx context.Context,
	pickupLat, pickupLng, dropoffLat, dropoffLng float64,
) ([]*FareEstimate, error) {
	estimates := make([]*FareEstimate, 0, len(knownRideTypes))
	for _, rideType := range knownRideTypes {
		estimate, err := s.CalculateFare(ctx, pickupLat, pickupLng, dropoffLat, dropoffLng, rideType)
		if err != nil {
			return nil, err
		}
		estimates = append(estimates, estimate)
	}

	return estimates, nil
}

// getSurgeInfo calculates the current surge multiplier
func (s *PricingService) getSurgeInfo(
	ctx context.Context,
	lat, lng float64,
	rideType RideType,
) (*SurgeInfo, error) {
	// Get demand/supply ratio for the area
	radius := 2.0 // 2km radius for surge calculation

	// Count active drivers in the area
	activeDrivers, err := s.countActiveDrivers(ctx, lat, lng, radius)
	if err != nil {
		return nil, err
	}

	// Count pending ride requests in the area
	pendingRides, err := s.countPendingRides(ctx, lat, lng, radius)
	if err != nil {
		return nil, err
	}

	// Calculate demand/supply ratio
	var ratio float64
	if activeDrivers == 0 {
		ratio = 5.0 // Max surge if no drivers
	} else {
		ratio = float64(pendingRides) / float64(activeDrivers)
	}

	// Apply time-of-day multiplier
	timeMultiplier := s.getTimeOfDayMultiplier(time.Now())
	ratio *= timeMultiplier

	// Calculate surge multiplier
	multiplier := s.calculateSurgeMultiplier(ratio)

	// Determine demand level
	demandLevel := s.getDemandLevel(ratio)

	// Build reason string
	reason := s.buildSurgeReason(demandLevel, activeDrivers, pendingRides)

	return &SurgeInfo{
		Multiplier:    multiplier,
		Reason:        reason,
		DemandLevel:   demandLevel,
		ActiveDrivers: activeDrivers,
		PendingRides:  pendingRides,
	}, nil
}

// countActiveDrivers counts available drivers in the area
func (s *PricingService) countActiveDrivers(ctx context.Context, lat, lng, radiusKm float64) (int, error) {
	query := `
		SELECT COUNT(*)
		FROM drivers
		WHERE status = 'available'
		AND ST_DWithin(
			ST_MakePoint(current_lng, current_lat)::geography,
			ST_MakePoint($1, $2)::geography,
			$3
		)
	`

	radiusMeters := radiusKm * 1000
	var count int
	err := s.db.QueryRow(ctx, query, lng, lat, radiusMeters).Scan(&count)
	if err != nil {
		return 0, err
	}
	return count, nil
}

// countPendingRides counts pending ride requests in the area
func (s *PricingService) countPendingRides(ctx context.Context, lat, lng, radiusKm float64) (int, error) {
	query := `
		SELECT COUNT(*)
		FROM rides
		WHERE status IN ('requested', 'searching')
		AND requested_at > NOW() - INTERVAL '10 minutes'
		AND ST_DWithin(
			ST_MakePoint(pickup_lng, pickup_lat)::geography,
			ST_MakePoint($1, $2)::geography,
			$3
		)
	`

	radiusMeters := radiusKm * 1000
	var count int
	err := s.db.QueryRow(ctx, query, lng, lat, radiusMeters).Scan(&count)
	if err != nil {
		return 0, err
	}
	return count, nil
}

// calculateSurgeMultiplier converts demand ratio to surge multiplier
func (s *PricingService) calculateSurgeMultiplier(ratio float64) float64 {
	// Linear surge: 1.0 at ratio=1.0, increases with demand
	// Formula: multiplier = 1.0 + (ratio - 1.0) * 0.5
	// Capped at max surge

	if ratio <= 1.0 {
		return 1.0
	}

	multiplier := 1.0 + (ratio-1.0)*0.5

	// Cap at maximum
	if multiplier > s.config.MaxSurgeMultiplier {
		multiplier = s.config.MaxSurgeMultiplier
	}

	// Round to 2 decimal places
	return math.Round(multiplier*100) / 100
}

// getDemandLevel returns a human-readable demand level
func (s *PricingService) getDemandLevel(ratio float64) string {
	switch {
	case ratio < 0.8:
		return "low"
	case ratio < 1.2:
		return "moderate"
	case ratio < 2.0:
		return "high"
	default:
		return "extreme"
	}
}

// getTimeOfDayMultiplier applies time-based pricing adjustments
func (s *PricingService) getTimeOfDayMultiplier(t time.Time) float64 {
	hour := t.Hour()
	weekday := t.Weekday()

	// Rush hour multipliers
	switch {
	case hour >= 7 && hour <= 9: // Morning rush
		return 1.3
	case hour >= 17 && hour <= 19: // Evening rush
		return 1.4
	case hour >= 22 || hour <= 5: // Late night / early morning
		return 1.2
	case weekday == time.Friday || weekday == time.Saturday: // Weekend evenings
		if hour >= 20 || hour <= 2 {
			return 1.25
		}
	}

	return 1.0
}

// buildSurgeReason creates a human-readable reason for surge pricing
func (s *PricingService) buildSurgeReason(demandLevel string, drivers, rides int) string {
	switch demandLevel {
	case "low":
		return "Low demand in your area"
	case "moderate":
		return "Moderate demand in your area"
	case "high":
		return "High demand - more riders than drivers nearby"
	case "extreme":
		return "Very high demand - limited driver availability"
	default:
		return "Standard pricing"
	}
}

// estimatePickupTime estimates how long until a driver arrives
func (s *PricingService) estimatePickupTime(ctx context.Context, lat, lng float64) int {
	// Find nearest available driver
	query := `
		SELECT ST_Distance(
			ST_MakePoint(current_lng, current_lat)::geography,
			ST_MakePoint($1, $2)::geography
		) / 1000.0 as distance_km
		FROM drivers
		WHERE status = 'available'
		ORDER BY ST_MakePoint(current_lng, current_lat)::geography <-> ST_MakePoint($1, $2)::geography
		LIMIT 1
	`

	var distanceKm float64
	err := s.db.QueryRow(ctx, query, lng, lat).Scan(&distanceKm)
	if err != nil {
		return 5 // Default 5 minutes
	}

	// Assume average speed of 25 km/h in urban areas
	etaMinutes := int(math.Round((distanceKm / 25.0) * 60))
	if etaMinutes < 1 {
		etaMinutes = 1
	}
	if etaMinutes > 30 {
		etaMinutes = 30
	}

	return etaMinutes
}

// estimateDuration estimates trip duration in minutes
func (s *PricingService) estimateDuration(distanceKm float64) int {
	// Assume average speed of 30 km/h in urban areas
	// Apply time-of-day adjustment
	now := time.Now()
	avgSpeed := 30.0

	// Reduce speed during rush hours
	hour := now.Hour()
	if (hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19) {
		avgSpeed = 20.0
	}

	durationMinutes := (distanceKm / avgSpeed) * 60
	result := int(math.Round(durationMinutes))
	if result < 1 {
		result = 1
	}
	return result
}

// validateCoordinates validates latitude and longitude
func (s *PricingService) validateCoordinates(pickupLat, pickupLng, dropoffLat, dropoffLng float64) error {
	if pickupLat < -90 || pickupLat > 90 || pickupLng < -180 || pickupLng > 180 {
		return ErrInvalidLocation
	}
	if dropoffLat < -90 || dropoffLat > 90 || dropoffLng < -180 || dropoffLng > 180 {
		return ErrInvalidLocation
	}

	// Check that pickup and dropoff are not the same point
	if pickupLat == dropoffLat && pickupLng == dropoffLng {
		return ErrInvalidLocation
	}

	return nil
}

// validateChain checks every point of an ordered waypoint chain
// [pickup, stops..., dropoff]: each coordinate must be in range, and no two
// consecutive points may coincide (a zero-length leg is a data error, not a
// free ride). The single-leg validateCoordinates above is the len-2 special
// case of this function.
func (s *PricingService) validateChain(chain [][2]float64) error {
	for _, p := range chain {
		if p[0] < -90 || p[0] > 90 || p[1] < -180 || p[1] > 180 {
			return ErrInvalidLocation
		}
	}
	for i := 0; i < len(chain)-1; i++ {
		if chain[i] == chain[i+1] {
			return ErrInvalidLocation
		}
	}
	return nil
}
