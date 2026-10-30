package services

import (
	"context"
	"errors"
	"fmt"
	"math"
	"sort"

	"github.com/google/uuid"
	"nidaw-backend/internal/modules/logix/domain/entities"
)

// LoadMatchEventWriter is an application port for durable publication intent.
// Implementations must persist the event before returning successfully.
type LoadMatchEventWriter interface {
	RecordLoadMatched(ctx context.Context, load *entities.Load, carrierID uuid.UUID, score float64) error
}

// CarrierRepository isolates persistence and schema assumptions from the
// load-matching application policy. Its PostgreSQL implementation remains
// gated on authoritative schema evidence (see the architecture contract).
type CarrierRepository interface {
	FindCandidateCarriers(ctx context.Context, load *entities.Load) ([]entities.Carrier, error)
	GetCarrierByID(ctx context.Context, carrierID uuid.UUID) (*entities.Carrier, error)
}

type LoadMatcher struct {
	carriers    CarrierRepository
	eventWriter LoadMatchEventWriter
}

func NewLoadMatcher(carriers CarrierRepository, eventWriter LoadMatchEventWriter) *LoadMatcher {
	return &LoadMatcher{carriers: carriers, eventWriter: eventWriter}
}

type CarrierScore struct {
	CarrierID      uuid.UUID
	Score          float64
	OnTimeRate     float64
	Rating         float64
	PriceMatch     float64
	RouteMatch     float64
	EquipmentMatch bool
}

func (m *LoadMatcher) FindBestCarrier(ctx context.Context, load *entities.Load) (*entities.Carrier, error) {
	if load == nil || load.ID == uuid.Nil {
		return nil, errors.New("valid load is required")
	}
	// 1. Get candidate carriers
	if m == nil || m.carriers == nil {
		return nil, errors.New("load-match carrier repository is not configured")
	}
	carriers, err := m.carriers.FindCandidateCarriers(ctx, load)
	if err != nil {
		return nil, err
	}

	if len(carriers) == 0 {
		return nil, ErrNoCarriersAvailable
	}

	// 2. Score each carrier
	scores := make([]CarrierScore, 0, len(carriers))
	for _, carrier := range carriers {
		score := m.scoreCarrier(carrier, load)
		scores = append(scores, score)
	}

	// 3. Sort by score
	sort.Slice(scores, func(i, j int) bool {
		if scores[i].Score == scores[j].Score {
			// Stable tie-break avoids a different carrier being selected across
			// runs when the business score is identical.
			return scores[i].CarrierID.String() < scores[j].CarrierID.String()
		}
		return scores[i].Score > scores[j].Score
	})

	// 4. Get best carrier
	bestCarrierID := scores[0].CarrierID
	bestCarrier, err := m.carriers.GetCarrierByID(ctx, bestCarrierID)
	if err != nil {
		return nil, err
	}

	// 5. Persist a versioned event to the outbox. A successful match is not
	// reported to callers as complete if its durable publication intent fails.
	if m.eventWriter == nil {
		return nil, errors.New("load-match event writer is not configured")
	}
	if err := m.eventWriter.RecordLoadMatched(ctx, load, bestCarrierID, scores[0].Score); err != nil {
		return nil, fmt.Errorf("record load-matched event: %w", err)
	}

	return bestCarrier, nil
}

func (m *LoadMatcher) scoreCarrier(carrier entities.Carrier, load *entities.Load) CarrierScore {
	// Multi-factor scoring:
	// - On-time performance: 35%
	// - Rating: 25%
	// - Price competitiveness: 20%
	// - Route specialization: 15%
	// - Equipment match: 5%

	onTimeScore := carrier.OnTimeRate * 100 // 0-100
	ratingScore := carrier.Rating * 20      // 0-100

	// Price match: how close is carrier's typical rate to load rate
	// (simplified - would use historical data in production)
	priceMatch := 80.0 // Default good match

	// Route match: does carrier specialize in this lane?
	routeMatch := m.calculateRouteMatch(carrier, load)

	// Equipment match
	equipmentMatch := m.hasEquipment(carrier, load.EquipmentType)
	equipmentScore := 0.0
	if equipmentMatch {
		equipmentScore = 100
	}

	totalScore := (onTimeScore * 0.35) + (ratingScore * 0.25) + (priceMatch * 0.20) + (routeMatch * 0.15) + (equipmentScore * 0.05)

	return CarrierScore{
		CarrierID:      carrier.ID,
		Score:          totalScore,
		OnTimeRate:     carrier.OnTimeRate,
		Rating:         carrier.Rating,
		PriceMatch:     priceMatch,
		RouteMatch:     routeMatch,
		EquipmentMatch: equipmentMatch,
	}
}

func (m *LoadMatcher) calculateRouteMatch(carrier entities.Carrier, load *entities.Load) float64 {
	// Check if carrier operates frequently on this route
	// In production, would query historical shipment data
	origin := load.Origin.Country
	dest := load.Destination.Country

	for _, area := range carrier.ServiceAreas {
		if area == origin || area == dest {
			return 85.0 // Good match
		}
	}
	return 50.0 // Neutral
}

func (m *LoadMatcher) hasEquipment(carrier entities.Carrier, equipmentType string) bool {
	for _, eq := range carrier.EquipmentTypes {
		if eq == equipmentType {
			return true
		}
	}
	return false
}

// Haversine distance for route optimization
func haversine(lat1, lng1, lat2, lng2 float64) float64 {
	const R = 6371
	dLat := (lat2 - lat1) * math.Pi / 180
	dLng := (lng2 - lng1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dLng/2)*math.Sin(dLng/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
	return R * c
}
