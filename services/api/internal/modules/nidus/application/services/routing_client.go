package services

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

var ErrRoutingUnavailable = errors.New("traffic-aware routing is unavailable")

type RouteResult struct {
	DistanceKm            float64
	DurationMinutes       int
	StaticDurationMinutes int
}

type RoutingClient struct {
	apiKey string
	client *http.Client
}

func NewRoutingClient(apiKey string) *RoutingClient {
	apiKey = strings.TrimSpace(apiKey)
	if apiKey == "" {
		return nil
	}
	return &RoutingClient{apiKey: apiKey, client: &http.Client{Timeout: 5 * time.Second}}
}

func NewRoutingClientFromEnvironment() *RoutingClient {
	return NewRoutingClient(os.Getenv("GOOGLE_MAPS_ROUTES_API_KEY"))
}

func (c *RoutingClient) Route(ctx context.Context, originLat, originLng, destLat, destLng float64) (RouteResult, error) {
	if c == nil || c.apiKey == "" {
		return RouteResult{}, ErrRoutingUnavailable
	}
	requestBody := map[string]any{
		"origin":                   map[string]any{"location": map[string]any{"latLng": map[string]float64{"latitude": originLat, "longitude": originLng}}},
		"destination":              map[string]any{"location": map[string]any{"latLng": map[string]float64{"latitude": destLat, "longitude": destLng}}},
		"travelMode":               "DRIVE",
		"routingPreference":        "TRAFFIC_AWARE",
		"computeAlternativeRoutes": false,
		"units":                    "METRIC",
	}
	body, err := json.Marshal(requestBody)
	if err != nil {
		return RouteResult{}, fmt.Errorf("encode route request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://routes.googleapis.com/directions/v2:computeRoutes", bytes.NewReader(body))
	if err != nil {
		return RouteResult{}, fmt.Errorf("create route request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Goog-Api-Key", c.apiKey)
	req.Header.Set("X-Goog-FieldMask", "routes.distanceMeters,routes.duration,routes.staticDuration")
	resp, err := c.client.Do(req)
	if err != nil {
		return RouteResult{}, fmt.Errorf("request route: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return RouteResult{}, fmt.Errorf("route provider returned HTTP %d", resp.StatusCode)
	}
	var payload struct {
		Routes []struct {
			DistanceMeters float64 `json:"distanceMeters"`
			Duration       string  `json:"duration"`
			StaticDuration string  `json:"staticDuration"`
		} `json:"routes"`
	}
	decoder := json.NewDecoder(io.LimitReader(resp.Body, 1<<20))
	if err := decoder.Decode(&payload); err != nil {
		return RouteResult{}, fmt.Errorf("decode route response: %w", err)
	}
	if len(payload.Routes) == 0 || payload.Routes[0].DistanceMeters <= 0 {
		return RouteResult{}, ErrRoutingUnavailable
	}
	duration, err := parseGoogleDuration(payload.Routes[0].Duration)
	if err != nil {
		return RouteResult{}, err
	}
	staticDuration, err := parseGoogleDuration(payload.Routes[0].StaticDuration)
	if err != nil {
		staticDuration = duration
	}
	return RouteResult{DistanceKm: payload.Routes[0].DistanceMeters / 1000, DurationMinutes: maxInt(1, int((duration+59)/60)), StaticDurationMinutes: maxInt(1, int((staticDuration+59)/60))}, nil
}

func parseGoogleDuration(value string) (int64, error) {
	value = strings.TrimSuffix(strings.TrimSpace(value), "s")
	if value == "" {
		return 0, ErrRoutingUnavailable
	}
	seconds, err := strconv.ParseFloat(value, 64)
	if err != nil || seconds < 0 {
		return 0, ErrRoutingUnavailable
	}
	return int64(seconds + 0.5), nil
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
