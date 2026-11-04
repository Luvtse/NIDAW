package http

import (
	"net/http"
	"time"

	authapp "nidaw-backend/internal/modules/auth/application"
	legalsvc "nidaw-backend/internal/modules/legal/application/services"
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
	return newRouter(db, authService, logger, otpSender, rdb, otpCfg, nil, nil, nil, 0)
}

// NewRouterWithOnboarding is NewRouter plus the rider-activation wiring
// (Phase 3): the activation service and the legal module's consent service.
// Passing nil leaves the onboarding endpoints answering 503.
func NewRouterWithOnboarding(
	db *database.Postgres,
	authService *auth.Service,
	logger *zap.Logger,
	otpSender authapp.SMSSender,
	rdb *redis.Client,
	otpCfg authapp.OTPConfig,
	activation *authapp.ActivationService,
	consent *legalsvc.ConsentService,
) http.Handler {
	return newRouter(db, authService, logger, otpSender, rdb, otpCfg, activation, consent, nil, 0)
}

// NewRouterWithSessions is NewRouterWithOnboarding plus the durable
// device-session store (Phase 5). A nil store disables session persistence and
// the /auth/sessions endpoints answer 503. idleTTL mirrors SESSION_IDLE_TTL for
// policy reporting; absolute expiry comes from the store configuration.
func NewRouterWithSessions(
	db *database.Postgres,
	authService *auth.Service,
	logger *zap.Logger,
	otpSender authapp.SMSSender,
	rdb *redis.Client,
	otpCfg authapp.OTPConfig,
	activation *authapp.ActivationService,
	consent *legalsvc.ConsentService,
	sessions *auth.SessionStore,
	sessionIdleTTL time.Duration,
) http.Handler {
	return newRouter(db, authService, logger, otpSender, rdb, otpCfg, activation, consent, sessions, sessionIdleTTL)
}

func newRouter(
	db *database.Postgres,
	authService *auth.Service,
	logger *zap.Logger,
	otpSender authapp.SMSSender,
	rdb *redis.Client,
	otpCfg authapp.OTPConfig,
	activation *authapp.ActivationService,
	consent *legalsvc.ConsentService,
	sessions *auth.SessionStore,
	sessionIdleTTL time.Duration,
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
	).WithOnboarding(activation, consent).WithSessions(sessions, sessionIdleTTL)

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

		// Rider onboarding / activation (Phase 3). The consent endpoints get a
		// tighter limiter than the global one because each ticket request
		// consumes an OTP verification attempt.
		onboardingLimiter := middleware.RateLimit(20, time.Minute)
		r.Get("/api/v1/auth/onboarding-status", handler.OnboardingStatusHandler)
		r.With(onboardingLimiter).Post("/api/v1/auth/onboarding/consent-ticket", handler.ConsentTicketHandler)
		r.With(onboardingLimiter).Post("/api/v1/auth/onboarding/complete", handler.CompleteOnboardingHandler)

		// Device sessions (Phase 5): list signed-in devices, revoke one
		// (lost-device flow), or revoke all (logout everywhere).
		r.Get("/api/v1/auth/sessions", handler.ListSessionsHandler)
		r.Delete("/api/v1/auth/sessions/{id}", handler.RevokeSessionHandler)
		r.Post("/api/v1/auth/sessions/revoke-all", handler.RevokeAllSessionsHandler)
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
