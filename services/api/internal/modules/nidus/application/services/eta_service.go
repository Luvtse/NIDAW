package services

import (
	"context"
	"math"
	"time"

	"nidaw-backend/internal/shared/database"
)

// ============================================================================
// TYPES
// ============================================================================

// ETAPrediction contains the estimated time of arrival and related metrics
type ETAPrediction struct {
	DistanceKm      float64   `json:"distance_km"`
	DurationMinutes int       `json:"duration_minutes"`
	Confidence      float64   `json:"confidence"` // 0.0 to 1.0
	TrafficFactor   float64   `json:"traffic_factor"`
	WeatherFactor   float64   `json:"weather_factor"`
	TimeOfDayFactor float64   `json:"time_of_day_factor"`
	CalculatedAt    time.Time `json:"calculated_at"`
}

// ============================================================================
// ETA SERVICE
// ============================================================================

// ETAService calculates estimated time of arrival for rides
type ETAService struct {
	db      *database.Postgres
	routing *RoutingClient
}

// NewETAService creates a new ETA service
func NewETAService(db *database.Postgres) *ETAService {
	return &ETAService{db: db, routing: NewRoutingClientFromEnvironment()}
}

// CalculateETA calculates the estimated time of arrival between two points
func (s *ETAService) CalculateETA(
	ctx context.Context,
	originLat, originLng, destLat, destLng float64,
) (*ETAPrediction, error) {
	if originLat < -90 || originLat > 90 || destLat < -90 || destLat > 90 || originLng < -180 || originLng > 180 || destLng < -180 || destLng > 180 || (originLat == destLat && originLng == destLng) {
		return nil, ErrInvalidLocation
	}
	if s.routing != nil {
		route, err := s.routing.Route(ctx, originLat, originLng, destLat, destLng)
		if err != nil {
			return nil, err
		}
		trafficFactor := float64(route.DurationMinutes) / float64(maxInt(1, route.StaticDurationMinutes))
		return &ETAPrediction{
			DistanceKm:      math.Round(route.DistanceKm*100) / 100,
			DurationMinutes: route.DurationMinutes,
			Confidence:      0.85,
			TrafficFactor:   trafficFactor,
			WeatherFactor:   1,
			TimeOfDayFactor: 1,
			CalculatedAt:    time.Now().UTC(),
		}, nil
	}
	// Without a configured route provider, this is a low-confidence geometric estimate.
	straightDistance := haversineDistance(originLat, originLng, destLat, destLng)

	// 2. Apply road distance factor (roads are longer than straight-line)
	// Urban areas: 1.3x, Suburban: 1.4x, Rural: 1.5x
	roadDistance := straightDistance * s.getRoadFactor(originLat, originLng)

	// 3. Get traffic factor based on current time and location
	trafficFactor := 1.0
	weatherFactor := 1.0
	timeOfDayFactor := s.getTimeOfDayFactor(time.Now())

	// 6. Calculate base duration
	// Average urban speed: 30 km/h, adjusted by factors
	baseSpeed := 30.0 // km/h
	adjustedSpeed := baseSpeed / (trafficFactor * weatherFactor * timeOfDayFactor)

	// Ensure minimum speed (traffic jams)
	if adjustedSpeed < 10.0 {
		adjustedSpeed = 10.0
	}

	durationHours := roadDistance / adjustedSpeed
	durationMinutes := int(math.Round(durationHours * 60))

	// Ensure minimum duration
	if durationMinutes < 1 {
		durationMinutes = 1
	}

	// Fallback ETA is intentionally marked low-confidence until route data is configured.
	confidence := 0.35

	return &ETAPrediction{
		DistanceKm:      math.Round(roadDistance*100) / 100,
		DurationMinutes: durationMinutes,
		Confidence:      confidence,
		TrafficFactor:   trafficFactor,
		WeatherFactor:   weatherFactor,
		TimeOfDayFactor: timeOfDayFactor,
		CalculatedAt:    time.Now().UTC(),
	}, nil
}

// ============================================================================
// FACTOR CALCULATIONS
// ============================================================================

// getRoadFactor returns the road distance multiplier based on area type
func (s *ETAService) getRoadFactor(lat, lng float64) float64 {
	// Simplified: in production, use geocoding to determine area type
	// Urban: 1.3, Suburban: 1.4, Rural: 1.5
	return 1.3 // Default to urban
}

// getTimeOfDayFactor applies a coarse fallback factor only when routing is not configured.
func (s *ETAService) getTimeOfDayFactor(t time.Time) float64 {
	hour := t.Hour()

	// Late night/early morning: faster (less traffic)
	if hour >= 0 && hour <= 5 {
		return 0.9
	}

	// Rush hours: slower
	if (hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19) {
		return 1.1
	}

	// Normal hours
	return 1.0
}

func haversineDistance(lat1, lng1, lat2, lng2 float64) float64 {
	const earthRadiusKm = 6371.0

	dLat := degreesToRadians(lat2 - lat1)
	dLng := degreesToRadians(lng2 - lng1)

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(degreesToRadians(lat1))*math.Cos(degreesToRadians(lat2))*
			math.Sin(dLng/2)*math.Sin(dLng/2)

	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadiusKm * c
}

func degreesToRadians(deg float64) float64 {
	return deg * math.Pi / 180
}
