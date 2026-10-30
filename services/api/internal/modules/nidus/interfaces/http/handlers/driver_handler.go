package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"nidaw-backend/internal/modules/nidus/application/services"
	"nidaw-backend/internal/shared/auth"
	"nidaw-backend/internal/shared/database"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

var ErrNotDriver = errors.New("no driver profile for this account")

type DriverHandler struct {
	matchingEngine *services.MatchingEngine
	cacheService   CacheService
	db             *database.Postgres
}

func NewDriverHandler(
	matchingEngine *services.MatchingEngine,
	cacheService CacheService,
	db ...*database.Postgres,
) *DriverHandler {
	h := &DriverHandler{
		matchingEngine: matchingEngine,
		cacheService:   cacheService,
	}
	if len(db) > 0 {
		h.db = db[0]
	}
	return h
}

// resolveDriverID maps an authenticated user ID to their driver profile ID.
// Both the Go side (availability toggles) and SQL side need this translation
// because drivers are keyed by their own PK while auth tokens carry user IDs.
func (h *DriverHandler) resolveDriverID(ctx context.Context, userID uuid.UUID) (uuid.UUID, error) {
	if h.db == nil || !h.db.IsReady() {
		return uuid.Nil, errors.New("database unavailable")
	}
	var driverID uuid.UUID
	err := h.db.QueryRow(ctx, `SELECT id FROM drivers WHERE user_id = $1`, userID).Scan(&driverID)
	if err != nil {
		return uuid.Nil, ErrNotDriver
	}
	return driverID, nil
}

type DriverResponse struct {
	ID             uuid.UUID `json:"id"`
	FullName       *string   `json:"full_name"`
	Rating         *float64  `json:"rating"`
	VehicleType    *string   `json:"vehicle_type"`
	VehicleModel   *string   `json:"vehicle_model"`
	VehiclePlate   *string   `json:"vehicle_plate"`
	CurrentLat     float64   `json:"current_lat"`
	CurrentLng     float64   `json:"current_lng"`
	Status         string    `json:"status"`
	AcceptanceRate *float64  `json:"acceptance_rate"`
	TotalRides     *int      `json:"total_rides"`
}

type NearbyDriversResponse struct {
	Drivers []DriverResponse `json:"drivers"`
	Total   int              `json:"total"`
}

func (h *DriverHandler) GetNearbyDrivers(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// Parse query parameters
	latStr := r.URL.Query().Get("lat")
	lngStr := r.URL.Query().Get("lng")
	radiusStr := r.URL.Query().Get("radius")

	if latStr == "" || lngStr == "" {
		writeError(w, http.StatusBadRequest, "MISSING_PARAMS", "lat and lng are required")
		return
	}

	lat, err := strconv.ParseFloat(latStr, 64)
	if err != nil || lat < -90 || lat > 90 {
		writeError(w, http.StatusBadRequest, "INVALID_LAT", "invalid latitude")
		return
	}

	lng, err := strconv.ParseFloat(lngStr, 64)
	if err != nil || lng < -180 || lng > 180 {
		writeError(w, http.StatusBadRequest, "INVALID_LNG", "invalid longitude")
		return
	}

	radius := 5.0
	if radiusStr != "" {
		if r, err := strconv.ParseFloat(radiusStr, 64); err == nil && r > 0 && r <= 50 {
			radius = r
		}
	}

	// Get nearby drivers from cache
	drivers, err := h.cacheService.GetNearbyDrivers(ctx, lat, lng, radius, "available")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "FETCH_FAILED", "failed to fetch drivers")
		return
	}

	// Convert to response
	response := NearbyDriversResponse{
		Drivers: make([]DriverResponse, 0, len(drivers)),
		Total:   len(drivers),
	}

	for _, driver := range drivers {
		driverID, parseErr := uuid.Parse(driver.DriverID)
		if parseErr != nil || h.db == nil || !h.db.IsReady() {
			continue
		}
		var name, vehicleType, vehicleModel, vehiclePlate pgtype.Text
		var rating, acceptanceRate pgtype.Float8
		var totalRides pgtype.Int4
		err := h.db.QueryRow(ctx, `
			SELECT u.full_name, d.rating, d.vehicle_type, d.vehicle_model,
			       d.vehicle_plate, d.acceptance_rate, d.total_rides
			  FROM drivers d JOIN users u ON u.id = d.user_id
			 WHERE d.id = $1
			   AND d.status = 'available'
			   AND d.last_location_update > NOW() - INTERVAL '90 seconds'
			   AND d.onboarding_status = 'approved'
			   AND d.license_verified AND d.background_check AND d.vehicle_inspected
			   AND EXISTS (SELECT 1 FROM driver_documents x WHERE x.driver_id=d.id AND x.document_type='drivers_license' AND x.status='verified' AND (x.expiry_date IS NULL OR x.expiry_date >= CURRENT_DATE))
			   AND EXISTS (SELECT 1 FROM driver_documents x WHERE x.driver_id=d.id AND x.document_type='background_check' AND x.status='verified' AND (x.expiry_date IS NULL OR x.expiry_date >= CURRENT_DATE))
			   AND EXISTS (SELECT 1 FROM driver_documents x WHERE x.driver_id=d.id AND x.document_type='vehicle_inspection' AND x.status='verified' AND (x.expiry_date IS NULL OR x.expiry_date >= CURRENT_DATE))
			   AND EXISTS (SELECT 1 FROM driver_documents x WHERE x.driver_id=d.id AND x.document_type='vehicle_registration' AND x.status='verified' AND (x.expiry_date IS NULL OR x.expiry_date >= CURRENT_DATE))
			   AND EXISTS (SELECT 1 FROM driver_documents x WHERE x.driver_id=d.id AND x.document_type='insurance' AND x.status='verified' AND (x.expiry_date IS NULL OR x.expiry_date >= CURRENT_DATE))`, driverID).Scan(
			&name, &rating, &vehicleType, &vehicleModel, &vehiclePlate,
			&acceptanceRate, &totalRides,
		)
		if err != nil {
			continue
		}
		response.Drivers = append(response.Drivers, DriverResponse{
			ID: driverID, FullName: textValue(name), Rating: floatValue(rating),
			VehicleType: textValue(vehicleType), VehicleModel: textValue(vehicleModel),
			VehiclePlate: textValue(vehiclePlate), CurrentLat: driver.Latitude,
			CurrentLng: driver.Longitude, Status: driver.Status,
			AcceptanceRate: floatValue(acceptanceRate), TotalRides: intValue(totalRides),
		})
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(response)
}

func (h *DriverHandler) GetMyProfile(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID, ok := auth.GetUserIDFromContext(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	var profile map[string]interface{}
	var id, profileUserID, fullName, email, phone, status string
	var rating, acceptanceRate, completionRate, earnings float64
	var totalRides int
	var vehicleType, vehicleModel, vehiclePlate, vehicleColor *string
	var vehicleYear *int
	var licenseVerified, backgroundCheck, vehicleInspected bool
	err := h.db.QueryRow(ctx, `
		SELECT d.id::text, d.user_id::text, u.full_name, u.email, u.phone,
		       COALESCE(d.rating, 0), COALESCE(d.acceptance_rate, 0), COALESCE(d.completion_rate, 0), COALESCE(d.total_rides, 0),
		       COALESCE(d.total_earnings, 0), d.status, d.vehicle_type, d.vehicle_model,
		       d.vehicle_plate, d.vehicle_color, d.vehicle_year,
		       COALESCE(d.license_verified, FALSE), COALESCE(d.background_check, FALSE), COALESCE(d.vehicle_inspected, FALSE)
		  FROM drivers d JOIN users u ON u.id = d.user_id WHERE d.user_id = $1`, userID).Scan(
		&id, &profileUserID, &fullName, &email, &phone, &rating, &acceptanceRate,
		&completionRate, &totalRides, &earnings, &status, &vehicleType,
		&vehicleModel, &vehiclePlate, &vehicleColor, &vehicleYear,
		&licenseVerified, &backgroundCheck, &vehicleInspected,
	)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_A_DRIVER", "driver profile not found")
		return
	}
	profile = map[string]interface{}{
		"id": id, "user_id": profileUserID, "full_name": fullName, "email": email, "phone": phone,
		"rating": rating, "acceptance_rate": acceptanceRate, "completion_rate": completionRate,
		"total_rides": totalRides, "total_earnings": earnings, "status": status,
		"vehicle_type": vehicleType, "vehicle_model": vehicleModel, "vehicle_plate": vehiclePlate,
		"vehicle_color": vehicleColor, "vehicle_year": vehicleYear,
		"license_verified": licenseVerified, "background_check": backgroundCheck,
		"vehicle_inspected": vehicleInspected,
	}
	writeJSON(w, http.StatusOK, profile)
}

func (h *DriverHandler) UpdateMyProfile(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID, ok := auth.GetUserIDFromContext(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	var req struct {
		FullName string `json:"full_name"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "invalid JSON body")
		return
	}
	name := strings.TrimSpace(req.FullName)
	if name == "" || len(name) > 160 {
		writeError(w, http.StatusBadRequest, "INVALID_PROFILE", "full_name is required and must be at most 160 characters")
		return
	}
	tag, err := h.db.Exec(ctx, `UPDATE users SET full_name=$2, updated_at=NOW() WHERE id=$1 AND role='driver'`, userID, name)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "PROFILE_UPDATE_FAILED", "could not update profile")
		return
	}
	if tag.RowsAffected() != 1 {
		writeError(w, http.StatusForbidden, "NOT_A_DRIVER", "driver profile not found")
		return
	}
	h.GetMyProfile(w, r)
}

func (h *DriverHandler) UpdateVehicleInfo(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID, ok := auth.GetUserIDFromContext(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	var req struct {
		VehicleType  string `json:"vehicle_type"`
		VehicleModel string `json:"vehicle_model"`
		VehiclePlate string `json:"vehicle_plate"`
		VehicleColor string `json:"vehicle_color"`
		VehicleYear  int    `json:"vehicle_year"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "invalid JSON body")
		return
	}
	vehicleType := strings.ToLower(strings.TrimSpace(req.VehicleType))
	allowed := map[string]bool{"sedan": true, "suv": true, "van": true, "luxury": true, "electric": true, "hybrid": true, "motorcycle": true}
	if !allowed[vehicleType] || strings.TrimSpace(req.VehicleModel) == "" || strings.TrimSpace(req.VehiclePlate) == "" || strings.TrimSpace(req.VehicleColor) == "" || req.VehicleYear < 2000 || req.VehicleYear > time.Now().Year() {
		writeError(w, http.StatusBadRequest, "INVALID_VEHICLE", "provide a supported vehicle type, model, plate, color, and valid year")
		return
	}
	var driverID uuid.UUID
	var oldVehicleType, oldVehiclePlate, oldVehicleModel, oldVehicleColor string
	var oldVehicleYear int
	if err := h.db.QueryRow(ctx, `SELECT id, COALESCE(vehicle_type,''), COALESCE(vehicle_plate,''), COALESCE(vehicle_model,''), COALESCE(vehicle_color,''), COALESCE(vehicle_year,0) FROM drivers WHERE user_id=$1 AND status <> 'on_trip' AND onboarding_status <> 'suspended'`, userID).Scan(&driverID, &oldVehicleType, &oldVehiclePlate, &oldVehicleModel, &oldVehicleColor, &oldVehicleYear); err != nil {
		writeError(w, http.StatusConflict, "VEHICLE_UPDATE_UNAVAILABLE", "vehicle details cannot be changed during a ride or while suspended")
		return
	}
	vehicleChanged := oldVehicleType != "" && (oldVehicleType != vehicleType || !strings.EqualFold(oldVehiclePlate, strings.TrimSpace(req.VehiclePlate)) || oldVehicleModel != strings.TrimSpace(req.VehicleModel) || oldVehicleColor != strings.TrimSpace(req.VehicleColor) || oldVehicleYear != req.VehicleYear)
	err := h.db.WithTx(ctx, func(tx *database.Tx) error {
		if vehicleChanged {
			if _, err := tx.Exec(ctx, `UPDATE driver_documents SET status='expired', verification_notes='Vehicle details changed; resubmission required', updated_at=NOW() WHERE driver_id=$1 AND document_type IN ('vehicle_registration','insurance','vehicle_inspection') AND status IN ('verified','pending')`, driverID); err != nil {
				return err
			}
		}
		_, err := tx.Exec(ctx, `UPDATE drivers SET vehicle_type=$2, vehicle_model=$3, vehicle_plate=$4, vehicle_color=$5, vehicle_year=$6, vehicle_inspected=CASE WHEN $7 THEN FALSE ELSE vehicle_inspected END, onboarding_status=CASE WHEN $7 OR onboarding_status <> 'approved' THEN 'pending' ELSE onboarding_status END, onboarding_reviewed_by=CASE WHEN $7 THEN NULL ELSE onboarding_reviewed_by END, onboarding_reviewed_at=CASE WHEN $7 THEN NULL ELSE onboarding_reviewed_at END, status='offline', updated_at=NOW() WHERE id=$1`, driverID, vehicleType, strings.TrimSpace(req.VehicleModel), strings.TrimSpace(req.VehiclePlate), strings.TrimSpace(req.VehicleColor), req.VehicleYear, vehicleChanged)
		return err
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, "VEHICLE_UPDATE_FAILED", "could not update vehicle information")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated", "onboarding_status": "pending"})
}

func (h *DriverHandler) GetDailyEarnings(w http.ResponseWriter, r *http.Request) {
	start, err := parseReportDate(r.URL.Query().Get("date"), time.Now().UTC().Format("2006-01-02"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_DATE", "date must use YYYY-MM-DD")
		return
	}
	h.writeEarningsReport(w, r, "daily", start, start.AddDate(0, 0, 1))
}

func (h *DriverHandler) GetWeeklyEarnings(w http.ResponseWriter, r *http.Request) {
	start, err := parseReportDate(r.URL.Query().Get("start_date"), "")
	if err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_DATE", "start_date must use YYYY-MM-DD")
		return
	}
	h.writeEarningsReport(w, r, "weekly", start, start.AddDate(0, 0, 7))
}

func (h *DriverHandler) GetMonthlyEarnings(w http.ResponseWriter, r *http.Request) {
	year, yErr := strconv.Atoi(r.URL.Query().Get("year"))
	month, mErr := strconv.Atoi(r.URL.Query().Get("month"))
	if yErr != nil || mErr != nil || year < 2000 || year > time.Now().Year()+1 || month < 1 || month > 12 {
		writeError(w, http.StatusBadRequest, "INVALID_PERIOD", "year and month are required and must be valid")
		return
	}
	start := time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.UTC)
	h.writeEarningsReport(w, r, "monthly", start, start.AddDate(0, 1, 0))
}

func parseReportDate(value, fallback string) (time.Time, error) {
	if value == "" {
		value = fallback
	}
	if value == "" {
		return time.Time{}, errors.New("date is required")
	}
	return time.Parse("2006-01-02", value)
}

func (h *DriverHandler) writeEarningsReport(w http.ResponseWriter, r *http.Request, period string, start, end time.Time) {
	ctx := r.Context()
	userID, ok := auth.GetUserIDFromContext(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	var driverID uuid.UUID
	if err := h.db.QueryRow(ctx, `SELECT id FROM drivers WHERE user_id=$1`, userID).Scan(&driverID); err != nil {
		writeError(w, http.StatusForbidden, "NOT_A_DRIVER", "no driver profile for this account")
		return
	}
	var baseFares, tips, averageFare float64
	var tipCount, totalRides, completedRides, cancelledRides int
	err := h.db.QueryRow(ctx, `
		SELECT COALESCE(SUM(amount_cents) FILTER (WHERE type='ride_credit_held'),0)/100.0,
		       COALESCE(SUM(amount_cents) FILTER (WHERE type='tip'),0)/100.0,
		       COUNT(*) FILTER (WHERE type='tip'),
	       (SELECT COUNT(*) FROM rides WHERE driver_id=$2 AND completed_at >= $3 AND completed_at < $4 AND status IN ('completed','paid')),
	       (SELECT COUNT(*) FROM rides WHERE driver_id=$2 AND completed_at >= $3 AND completed_at < $4 AND status IN ('completed','paid')),
	       (SELECT COUNT(*) FROM rides WHERE driver_id=$2 AND updated_at >= $3 AND updated_at < $4 AND status='cancelled'),
	       COALESCE((SELECT AVG(fare_amount) FROM rides WHERE driver_id=$2 AND completed_at >= $3 AND completed_at < $4 AND status IN ('completed','paid') AND currency='ETB'),0)
		  FROM ledger_transactions WHERE user_id=$1 AND currency='ETB' AND created_at >= $3 AND created_at < $4 AND type IN ('ride_credit_held','tip')`, userID, driverID, start, end).Scan(&baseFares, &tips, &tipCount, &totalRides, &completedRides, &cancelledRides, &averageFare)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "EARNINGS_UNAVAILABLE", "ETB earnings are unavailable")
		return
	}
	rows, err := h.db.Query(ctx, `
		WITH ledger_daily AS (
		 SELECT created_at::date AS day,
		        COALESCE(SUM(amount_cents) FILTER (WHERE type='ride_credit_held'),0)/100.0 AS base_fares,
		        COALESCE(SUM(amount_cents) FILTER (WHERE type='tip'),0)/100.0 AS tips
		   FROM ledger_transactions WHERE user_id=$1 AND currency='ETB' AND created_at >= $2 AND created_at < $3 AND type IN ('ride_credit_held','tip') GROUP BY created_at::date
		), ride_daily AS (
		 SELECT completed_at::date AS day, COUNT(*) AS rides
		   FROM rides WHERE driver_id=$4 AND completed_at >= $2 AND completed_at < $3 AND status IN ('completed','paid') GROUP BY completed_at::date
		)
		SELECT to_char(COALESCE(l.day,r.day),'YYYY-MM-DD'), COALESCE(l.base_fares,0), COALESCE(l.tips,0), COALESCE(r.rides,0)
		  FROM ledger_daily l FULL OUTER JOIN ride_daily r ON l.day=r.day ORDER BY COALESCE(l.day,r.day)`, userID, start, end, driverID)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, "EARNINGS_BREAKDOWN_UNAVAILABLE", "daily earnings breakdown is unavailable")
		return
	}
	defer rows.Close()
	breakdown := make([]map[string]any, 0)
	for rows.Next() {
		var day string
		var base, dayTips float64
		var rides int
		if err := rows.Scan(&day, &base, &dayTips, &rides); err != nil {
			writeError(w, http.StatusServiceUnavailable, "EARNINGS_BREAKDOWN_UNAVAILABLE", "daily earnings breakdown is unavailable")
			return
		}
		breakdown = append(breakdown, map[string]any{"date": day, "earnings": base + dayTips, "rides": rides, "tips": dayTips, "online_hours": nil})
	}
	if rows.Err() != nil {
		writeError(w, http.StatusServiceUnavailable, "EARNINGS_BREAKDOWN_UNAVAILABLE", "daily earnings breakdown is unavailable")
		return
	}
	averageTip := float64(0)
	if tipCount > 0 {
		averageTip = tips / float64(tipCount)
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"period": period, "start_date": start.Format("2006-01-02"), "end_date": end.Add(-time.Nanosecond).Format("2006-01-02"),
		"total_earnings": baseFares + tips, "base_fares": baseFares, "tips": tips,
		"bonuses": nil, "deductions": nil, "total_rides": totalRides, "completed_rides": completedRides,
		"cancelled_rides": cancelledRides, "average_fare": averageFare, "average_tip": averageTip,
		"online_hours": nil, "earnings_per_hour": nil, "daily_breakdown": breakdown, "currency": "ETB",
	})
}

func (h *DriverHandler) GetStats(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	userID, ok := auth.GetUserIDFromContext(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	var driverID uuid.UUID
	if err := h.db.QueryRow(ctx, `SELECT id FROM drivers WHERE user_id = $1`, userID).Scan(&driverID); err != nil {
		writeError(w, http.StatusForbidden, "NOT_A_DRIVER", "no driver profile for this account")
		return
	}
	var todayEarnings, weeklyEarnings, monthlyEarnings, tips, averageFare float64
	if err := h.db.QueryRow(ctx, `
		SELECT
		 COALESCE(SUM(amount_cents) FILTER (WHERE type IN ('ride_credit_held','tip') AND created_at::date = CURRENT_DATE), 0) / 100.0,
		 COALESCE(SUM(amount_cents) FILTER (WHERE type IN ('ride_credit_held','tip') AND created_at >= date_trunc('week', NOW())), 0) / 100.0,
		 COALESCE(SUM(amount_cents) FILTER (WHERE type IN ('ride_credit_held','tip') AND created_at >= date_trunc('month', NOW())), 0) / 100.0,
		 COALESCE(SUM(amount_cents) FILTER (WHERE type = 'tip'), 0) / 100.0
		 FROM ledger_transactions WHERE user_id = $1 AND currency = 'ETB'`, userID).Scan(
		&todayEarnings, &weeklyEarnings, &monthlyEarnings, &tips,
	); err != nil {
		writeError(w, http.StatusServiceUnavailable, "EARNINGS_UNAVAILABLE", "driver ledger statistics are unavailable")
		return
	}
	var todayRides, weeklyRides, monthlyRides, cancellations int
	if err := h.db.QueryRow(ctx, `
		SELECT
		 COUNT(*) FILTER (WHERE status IN ('completed','paid') AND completed_at::date = CURRENT_DATE),
		 COUNT(*) FILTER (WHERE status IN ('completed','paid') AND completed_at >= date_trunc('week', NOW())),
		 COUNT(*) FILTER (WHERE status IN ('completed','paid') AND completed_at >= date_trunc('month', NOW())),
		 COUNT(*) FILTER (WHERE status = 'cancelled'),
		 COALESCE(AVG(fare_amount) FILTER (WHERE status IN ('completed','paid') AND currency = 'ETB'), 0)
		 FROM rides WHERE driver_id = $1`, driverID).Scan(
		&todayRides, &weeklyRides, &monthlyRides, &cancellations, &averageFare,
	); err != nil {
		writeError(w, http.StatusServiceUnavailable, "RIDE_STATS_UNAVAILABLE", "driver ride statistics are unavailable")
		return
	}
	var averageRating, acceptanceRate, completionRate float64
	if err := h.db.QueryRow(ctx, `
		SELECT COALESCE(rating, 0), COALESCE(acceptance_rate, 0), COALESCE(completion_rate, 0)
		  FROM drivers WHERE id = $1`, driverID).Scan(&averageRating, &acceptanceRate, &completionRate); err != nil {
		writeError(w, http.StatusServiceUnavailable, "DRIVER_STATS_UNAVAILABLE", "driver profile statistics are unavailable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"today_earnings": todayEarnings, "today_rides": todayRides,
		"weekly_earnings": weeklyEarnings, "weekly_rides": weeklyRides,
		"monthly_earnings": monthlyEarnings, "monthly_rides": monthlyRides,
		"average_rating": averageRating, "acceptance_rate": acceptanceRate,
		"completion_rate": completionRate, "online_hours": nil,
		"average_fare": averageFare, "tips": tips, "cancellations": cancellations,
		"last_updated": time.Now().UTC(),
	})
}

func stringValue(v string) *string           { return &v }
func floatValueFromFloat(v float64) *float64 { return &v }
func intValueFromInt(v int) *int             { return &v }
func textValue(v pgtype.Text) *string {
	if !v.Valid {
		return nil
	}
	return &v.String
}
func floatValue(v pgtype.Float8) *float64 {
	if !v.Valid {
		return nil
	}
	return &v.Float64
}
func intValue(v pgtype.Int4) *int {
	if !v.Valid {
		return nil
	}
	n := int(v.Int32)
	return &n
}

func (h *DriverHandler) GetDriver(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	driverIDStr := chi.URLParam(r, "driverID")
	driverID, err := uuid.Parse(driverIDStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_ID", "invalid driver ID")
		return
	}

	// Get driver from cache or DB
	driver, err := h.matchingEngine.GetDriverByID(ctx, driverID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "driver not found")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(DriverResponse{
		ID: driver.ID, FullName: stringValue(driver.FullName), Rating: floatValueFromFloat(driver.Rating),
		VehicleType: stringValue(string(driver.VehicleType)), VehicleModel: stringValue(driver.VehicleModel),
		VehiclePlate: stringValue(driver.VehiclePlate), CurrentLat: driver.CurrentLat,
		CurrentLng: driver.CurrentLng, Status: string(driver.Status),
		AcceptanceRate: floatValueFromFloat(driver.AcceptanceRate), TotalRides: intValueFromInt(driver.TotalRides),
	})
}

// GoOnline handles POST /api/v1/nidus/drivers/online.
// Flips the driver profile to 'available' so the matching engine starts
// offering rides, and seeds the location cache with the reported position.
// A driver mid-trip ('on_trip') is never knocked offline by a stray toggle:
// the UPDATE is conditioned on non-active statuses only.
func (h *DriverHandler) GoOnline(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	userID, ok := auth.GetUserIDFromContext(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}

	// Body is optional: drivers may toggle online without a fresh fix.
	var req struct {
		Lat *float64 `json:"lat"`
		Lng *float64 `json:"lng"`
	}
	if r.ContentLength > 0 {
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "invalid JSON body")
			return
		}
	}

	driverID, err := h.resolveDriverID(ctx, userID)
	if err != nil {
		writeError(w, http.StatusForbidden, "NOT_A_DRIVER", "no driver profile for this account")
		return
	}

	var verified bool
	var vehicleType *string
	if err := h.db.QueryRow(ctx, `
		SELECT onboarding_status='approved' AND COALESCE(license_verified, FALSE) AND COALESCE(background_check, FALSE) AND COALESCE(vehicle_inspected, FALSE)
		       AND EXISTS (SELECT 1 FROM driver_documents x WHERE x.driver_id=drivers.id AND x.document_type='drivers_license' AND x.status='verified' AND (x.expiry_date IS NULL OR x.expiry_date >= CURRENT_DATE))
		       AND EXISTS (SELECT 1 FROM driver_documents x WHERE x.driver_id=drivers.id AND x.document_type='background_check' AND x.status='verified' AND (x.expiry_date IS NULL OR x.expiry_date >= CURRENT_DATE))
		       AND EXISTS (SELECT 1 FROM driver_documents x WHERE x.driver_id=drivers.id AND x.document_type='vehicle_inspection' AND x.status='verified' AND (x.expiry_date IS NULL OR x.expiry_date >= CURRENT_DATE))
		       AND EXISTS (SELECT 1 FROM driver_documents x WHERE x.driver_id=drivers.id AND x.document_type='vehicle_registration' AND x.status='verified' AND (x.expiry_date IS NULL OR x.expiry_date >= CURRENT_DATE))
		       AND EXISTS (SELECT 1 FROM driver_documents x WHERE x.driver_id=drivers.id AND x.document_type='insurance' AND x.status='verified' AND (x.expiry_date IS NULL OR x.expiry_date >= CURRENT_DATE)), vehicle_type
		  FROM drivers WHERE id = $1`, driverID).Scan(&verified, &vehicleType); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to verify driver eligibility")
		return
	}
	if !verified {
		writeError(w, http.StatusForbidden, "DRIVER_NOT_VERIFIED", "driver verification must be completed before going online")
		return
	}
	if vehicleType == nil || *vehicleType == "" {
		writeError(w, http.StatusForbidden, "VEHICLE_NOT_CONFIGURED", "a verified vehicle type is required before going online")
		return
	}

	tag, err := h.db.Exec(ctx, `
		UPDATE drivers
		   SET status = 'available', updated_at = NOW()
		 WHERE id = $1 AND status IN ('offline', 'available', 'busy')`,
		driverID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update availability")
		return
	}
	if tag.RowsAffected() == 0 {
		// Driver is on_trip/inactive/suspended — report current effective state.
		h.writeStatus(w, ctx, driverID, http.StatusConflict, "DRIVER_NOT_TOGGLEABLE")
		return
	}

	// Seed the fleet cache so the auto-matcher can score this driver now.
	if req.Lat != nil && req.Lng != nil &&
		*req.Lat >= -90 && *req.Lat <= 90 && *req.Lng >= -180 && *req.Lng <= 180 {
		_, _ = h.db.Exec(ctx, `UPDATE drivers SET current_lat = $1, current_lng = $2, last_location_update = NOW() WHERE id = $3`, *req.Lat, *req.Lng, driverID)
		_ = h.cacheService.UpdateDriverLocation(ctx, &DriverLocation{
			DriverID:  driverID.String(),
			Latitude:  *req.Lat,
			Longitude: *req.Lng,
			Timestamp: time.Now().Unix(),
			Status:    "available",
		})
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "available"})
}

// GoOffline handles POST /api/v1/nidus/drivers/offline.
// Refuses while the driver holds an active ride (matched/en-route/in_progress)
// to prevent orphaning a rider mid-service; otherwise flips to 'offline'.
func (h *DriverHandler) GoOffline(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	userID, ok := auth.GetUserIDFromContext(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}

	driverID, err := h.resolveDriverID(ctx, userID)
	if err != nil {
		writeError(w, http.StatusForbidden, "NOT_A_DRIVER", "no driver profile for this account")
		return
	}

	var active bool
	if err := h.db.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM rides
			 WHERE driver_id = $1
			   AND status IN ('matched', 'accepted', 'driver_en_route', 'in_progress')
		)`, driverID).Scan(&active); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to check active rides")
		return
	}
	if active {
		writeError(w, http.StatusConflict, "RIDE_IN_PROGRESS", "complete or cancel your active ride before going offline")
		return
	}

	if _, err := h.db.Exec(ctx,
		`UPDATE drivers SET status = 'offline', updated_at = NOW() WHERE id = $1`,
		driverID); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to update availability")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "offline"})
}

// writeStatus reports the driver's current DB status; used when a toggle was
// rejected by the conditional UPDATE guard.
func (h *DriverHandler) writeStatus(w http.ResponseWriter, ctx context.Context, driverID uuid.UUID, status int, code string) {
	var cur string
	_ = h.db.QueryRow(ctx, `SELECT status FROM drivers WHERE id = $1`, driverID).Scan(&cur)
	writeError(w, status, code, "availability unchanged; current status: "+cur)
}

func (h *DriverHandler) UpdateLocation(w http.ResponseWriter, r *http.Request) {
	writeError(w, http.StatusGone, "LOCATION_ROUTE_RETIRED", "use the Nidus location update endpoint")
}
