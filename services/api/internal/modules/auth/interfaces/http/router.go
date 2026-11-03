package http

import (
	"net/http"
	"time"

	authapp "nidaw-backend/internal/modules/auth/application"
	"nidaw-backend/internal/shared/auth"
	"nidaw-backend/internal/shared/database"
	"nidaw-backend/internal/shared/middleware"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// ============================================================================
// ROUTER CONSTRUCTOR
// ============================================================================

// NewRouter creates a new auth router with all authentication routes.
// otpSender may be nil (OTP endpoints then answer 503); rdb provides the
// ephemeral store for challenges and verification tickets.
func NewRouter(
	db *database.Postgres,
	authService *auth.Service,
	logger *zap.Logger,
	otpSender authapp.SMSSender,
	rdb *redis.Client,
	otpCfg authapp.OTPConfig,
) http.Handler {
	r := chi.NewRouter()

	// Global middleware
	r.Use(chimiddleware.RequestID)
	r.Use(chimiddleware.RealIP)
	r.Use(middleware.Logger(logger))
	r.Use(middleware.Recoverer(logger))
	r.Use(middleware.Timeout(30 * time.Second))
	r.Use(middleware.RequestIDToContext)
	r.Use(middleware.ContentType("application/json"))
	r.Use(middleware.SecurityHeaders)
	r.Use(middleware.RateLimit(60, time.Minute)) // 60 requests per minute

	// Initialize handler
	handler := NewAuthHandler(db, authService, logger).WithOTP(
		authapp.NewOTPService(rdb, otpSender, otpCfg), rdb, otpCfg,
	)

	// ========================================================================
	// PUBLIC ROUTES (no auth required)
	// ========================================================================
	r.Post("/api/v1/auth/login", handler.Login)
	r.Post("/api/v1/auth/register", handler.Register)
	r.Post("/api/v1/auth/refresh", handler.Refresh)

	// Phone + OTP flow (Phase 2). Tighter per-route limiter: OTP endpoints
	// are the abuse magnet of the auth surface.
	otpLimiter := middleware.RateLimit(10, time.Minute)
	r.With(otpLimiter).Post("/api/v1/auth/otp/request", handler.OTPRequestHandler)
	r.With(otpLimiter).Post("/api/v1/auth/otp/verify", handler.OTPVerifyHandler)
	r.With(otpLimiter).Post("/api/v1/auth/register-phone", handler.RegisterPhoneHandler)

	// ========================================================================
	// PROTECTED ROUTES (auth required)
	// ========================================================================
	r.Group(func(r chi.Router) {
		r.Use(authService.Middleware())

		r.Get("/api/v1/auth/me", handler.GetCurrentUser)
		r.Post("/api/v1/auth/logout", handler.Logout)
		r.Put("/api/v1/auth/profile", handler.UpdateProfile)
		r.Post("/api/v1/auth/change-password", handler.ChangePassword)
	})

	// ========================================================================
	// HEALTH CHECK
	// ========================================================================
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"healthy","service":"auth"}`))
	})

	return r
}
