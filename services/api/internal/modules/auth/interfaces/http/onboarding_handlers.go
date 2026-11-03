package http

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	authapp "nidaw-backend/internal/modules/auth/application"
	legalsvc "nidaw-backend/internal/modules/legal/application/services"
	legaldom "nidaw-backend/internal/modules/legal/domain/entities"
	sharedauth "nidaw-backend/internal/shared/auth"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// ============================================================================
// RIDER ONBOARDING / ACTIVATION ENDPOINTS (Auth roadmap Phase 3)
//
// GET  /api/v1/auth/onboarding-status   — activation checklist + gate state
// POST /api/v1/auth/onboarding/consent-ticket — short OTP re-check → ticket
// POST /api/v1/auth/onboarding/complete — accept agreements, activate account
//
// Activation = phone verified + every required legal agreement accepted at its
// current version. Optional profile fields (name details, email, password,
// photo) never gate it: riders can book rides and order food while they are
// empty. The durable record lives in users.onboarding_complete / activated_at;
// consent rows live in the legal module's user_consents table.
//
// Sensitive-operation rule: accepting binding legal agreements requires an
// access token AND a fresh OTP for the account's own phone number, delivered
// to that device only — same pattern as change-password requiring a password.
// A per-request consent ticket binds the OTP proof to exactly one submission.
// ============================================================================

const (
	consentTicketTTL    = 5 * time.Minute
	consentTicketPrefix = "auth:onboarding:consent-ticket:"
	maxAgreementTypes   = 10
)

// WithOnboarding equips the handler with the activation service and the legal
// consent service used to persist agreement acceptances. Either may be nil;
// the endpoints then answer 503 rather than half-working.
func (h *AuthHandler) WithOnboarding(act *authapp.ActivationService, consent *legalsvc.ConsentService) *AuthHandler {
	h.activation = act
	h.consentService = consent
	return h
}

// OnboardingStatusHandler handles GET /api/v1/auth/onboarding-status.
func (h *AuthHandler) OnboardingStatusHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	userID, ok := currentUserID(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	if h.activation == nil {
		writeError(w, http.StatusServiceUnavailable, "ONBOARDING_UNAVAILABLE", "onboarding service is temporarily unavailable")
		return
	}

	status, err := h.activation.Status(ctx, userID)
	if err != nil {
		if errors.Is(err, authapp.ErrActivationUser) {
			writeError(w, http.StatusNotFound, "USER_NOT_FOUND", "user not found")
			return
		}
		h.logger.Error("onboarding status query failed", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "ONBOARDING_STATUS_FAILED", "could not load onboarding status")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(status)
}

// ConsentTicketHandler handles POST /api/v1/auth/onboarding/consent-ticket.
// Body: {"code": "<digits of the OTP just sent via otp/request operation=register>"}.
// The phone is taken from the session row — clients cannot target another
// number — and the code is validated against the rider-register challenge for
// that phone. On success returns a single-use ticket for onboarding/complete.
func (h *AuthHandler) ConsentTicketHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	userID, ok := currentUserID(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	if h.otpService == nil || !h.otpService.Available() {
		writeError(w, http.StatusServiceUnavailable, "OTP_UNAVAILABLE", "phone verification is temporarily unavailable")
		return
	}

	var req struct {
		Code string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "invalid JSON body")
		return
	}
	code := strings.TrimSpace(req.Code)
	if len(code) < 4 || len(code) > 10 || !allDigits(code) {
		writeError(w, http.StatusBadRequest, "INVALID_CODE", "code must be 4-10 digits")
		return
	}

	var phone *string
	err := h.db.QueryRow(ctx, `SELECT phone FROM users WHERE id = $1`, userID).Scan(&phone)
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, http.StatusNotFound, "USER_NOT_FOUND", "user not found")
		return
	}
	if err != nil {
		h.logger.Error("session phone lookup failed", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "CONSENT_TICKET_FAILED", "could not start consent verification")
		return
	}
	if phone == nil || strings.TrimSpace(*phone) == "" {
		// Accounts predating phone-first auth cannot prove possession of a
		// number without one; they recover/add the phone first.
		writeError(w, http.StatusBadRequest, "PHONE_REQUIRED", "verify a phone number before accepting agreements")
		return
	}

	if err := h.otpService.Verify(ctx, *phone, code, authapp.AccountRider, authapp.OTPOpRegister); err != nil {
		h.logger.Info("onboarding consent OTP rejected", zap.String("error", err.Error()))
		switch {
		case errors.Is(err, authapp.ErrOTPNoChallenge), errors.Is(err, authapp.ErrOTPExpired):
			writeError(w, http.StatusUnauthorized, "OTP_EXPIRED", "code is invalid or expired; request a new one")
		case errors.Is(err, authapp.ErrOTPInvalidCode):
			writeError(w, http.StatusUnauthorized, "OTP_INVALID", "incorrect verification code")
		case errors.Is(err, authapp.ErrOTPMaxAttempts):
			writeError(w, http.StatusTooManyRequests, "OTP_LOCKED", "too many failed attempts; request a new code later")
		default:
			writeError(w, http.StatusInternalServerError, "OTP_VERIFY_FAILED", "verification failed")
		}
		return
	}

	// Verification passed: persist the permanent timestamp and mint the ticket.
	if err := h.markPhoneVerified(ctx, userID); err != nil {
		h.logger.Warn("failed to persist phone_verified_at during consent ticket", zap.Error(err))
	}

	ticket, err := h.createConsentTicket(ctx, userID)
	if err != nil {
		h.logger.Error("failed to store consent ticket", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "CONSENT_TICKET_FAILED", "could not issue consent ticket")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"verified":          true,
		"consent_ticket":    ticket,
		"ticket_expires_in": int64(consentTicketTTL.Seconds()),
	})
}

// CompleteOnboardingHandler handles POST /api/v1/auth/onboarding/complete.
// Body: {"consent_ticket": "...", "agreements": ["terms_of_service", ...]}.
// Agreements must cover every currently-required document type; unknown types
// are rejected. Each acceptance is stored through the legal module's consent
// service (server-side record with policy version, identity, timestamp), then
// activation is recomputed authoritatively. Idempotent: already-accepted
// versions pass through, and a repeat submit of a spent ticket after a
// completed activation still answers 200 with the final status.
func (h *AuthHandler) CompleteOnboardingHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	userID, ok := currentUserID(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	if h.activation == nil || h.consentService == nil {
		writeError(w, http.StatusServiceUnavailable, "ONBOARDING_UNAVAILABLE", "onboarding service is temporarily unavailable")
		return
	}

	var req struct {
		ConsentTicket string   `json:"consent_ticket"`
		Agreements    []string `json:"agreements"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "invalid JSON body")
		return
	}

	ua := truncateHeader(r.UserAgent(), 512)
	clientIP := clientIPFromRequest(r)

	reqTypes, err := h.activation.RequiredAgreementTypes(ctx)
	if err != nil {
		h.logger.Error("required agreement lookup failed", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "ONBOARDING_FAILED", "could not resolve required agreements")
		return
	}

	submitted := make(map[string]bool, len(req.Agreements))
	for _, raw := range req.Agreements {
		t := strings.ToLower(strings.TrimSpace(raw))
		if t == "" {
			continue
		}
		if len(t) > 50 {
			writeError(w, http.StatusBadRequest, "INVALID_AGREEMENT", "agreement type too long")
			return
		}
		submitted[t] = true
	}
	if len(submitted) > maxAgreementTypes {
		writeError(w, http.StatusBadRequest, "INVALID_AGREEMENT", "too many agreement types in one submission")
		return
	}
	allowed := make(map[string]bool, len(reqTypes))
	for _, t := range reqTypes {
		allowed[t] = true
	}
	for t := range submitted {
		if !allowed[t] {
			writeError(w, http.StatusBadRequest, "UNKNOWN_AGREEMENT", "agreement is not part of the required set: "+t)
			return
		}
	}
	var missing []string
	for _, t := range reqTypes {
		if !submitted[t] {
			missing = append(missing, t)
		}
	}

	activated := false
	if len(missing) == 0 {
		// Full set presented: the write path must be authorized by a fresh
		// OTP proof bound to this user (single-use ticket).
		verified, terr := h.consumeConsentTicket(ctx, req.ConsentTicket, userID)
		if terr != nil {
			h.logger.Error("consent ticket store failure", zap.Error(terr))
			writeError(w, http.StatusInternalServerError, "ONBOARDING_FAILED", "could not validate consent proof")
			return
		}
		if !verified {
			spent, serr := h.activationCompleted(ctx, userID)
			if serr != nil {
				h.logger.Error("activation state lookup failed", zap.Error(serr))
				writeError(w, http.StatusInternalServerError, "ONBOARDING_FAILED", "could not verify activation state")
				return
			}
			if spent {
				// Ticket was consumed by the request that already activated
				// this account: honest idempotent success below.
				activated = true
			} else {
				writeError(w, http.StatusUnauthorized, "CONSENT_VERIFICATION_REQUIRED", "phone re-verification required before accepting agreements")
				return
			}
		}

		if !activated {
			for _, t := range reqTypes {
				doc, derr := h.consentService.GetActiveDocument(ctx, t, "en", "GLOBAL")
				if derr != nil {
					if errors.Is(derr, legalsvc.ErrDocumentNotFound) {
						continue // nothing seeded to accept for this type
					}
					h.logger.Error("active document lookup failed", zap.String("type", t), zap.Error(derr))
					writeError(w, http.StatusInternalServerError, "ONBOARDING_FAILED", "could not load agreement versions")
					return
				}
				if err := h.recordConsent(ctx, userID, doc, clientIP, ua); err != nil {
					h.logger.Error("consent recording failed", zap.String("type", t), zap.Error(err))
					writeError(w, http.StatusInternalServerError, "ONBOARDING_FAILED", "could not record agreement acceptance")
					return
				}
			}
		}
	}

	status, err := h.activation.Activate(ctx, userID)
	if err != nil {
		if errors.Is(err, authapp.ErrActivationUser) {
			writeError(w, http.StatusNotFound, "USER_NOT_FOUND", "user not found")
			return
		}
		h.logger.Error("activation recompute failed", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "ONBOARDING_FAILED", "could not complete activation")
		return
	}

	httpStatus := http.StatusOK
	if !status.Complete {
		httpStatus = http.StatusPreconditionFailed
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(httpStatus)
	_ = json.NewEncoder(w).Encode(status)
}

// ============================================================================
// SUPPORT
// ============================================================================

// recordConsent stores one acceptance through the legal module, tolerating
// the two benign pre-existing states: consent already given for this exact
// version, or a withdrawn row that must be flipped back to given.
func (h *AuthHandler) recordConsent(ctx context.Context, userID uuid.UUID, doc *legaldom.LegalDocument, ip, userAgent string) error {
	given := true
	req := &legaldom.GiveConsentRequest{
		DocumentType:  doc.DocumentType,
		ConsentGiven:  given,
		ConsentMethod: "otp_onboarding",
	}
	err := h.consentService.GiveConsent(ctx, userID, req, ip, userAgent, "")
	if err == nil || errors.Is(err, legalsvc.ErrConsentAlreadyGiven) {
		return nil
	}
	if existingErr := h.reviveWithdrawnConsent(ctx, userID, doc); existingErr == nil {
		return nil
	}
	return err
}

// reviveWithdrawnConsent flips a consent row back to given when GiveConsent
// refused because the unique(user_id, document_id) row exists but was
// withdrawn (the insert path would hit the constraint).
func (h *AuthHandler) reviveWithdrawnConsent(ctx context.Context, userID uuid.UUID, doc *legaldom.LegalDocument) error {
	tag, err := h.db.Exec(ctx, `
		UPDATE user_consents
		SET consent_given = true,
		    document_version = $3,
		    consent_method = 'otp_onboarding',
		    consent_timestamp = NOW(),
		    withdrawn_at = NULL,
		    withdrawal_reason = NULL
		WHERE user_id = $1 AND document_id = $2 AND consent_given = false
	`, userID, doc.ID, doc.Version)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("no withdrawn consent row to revive")
	}
	_, _ = h.db.Exec(ctx, `
		INSERT INTO consent_audit_log (id, user_id, document_type, action, old_version, new_version)
		VALUES ($1, $2, $3, 'consent_reinstated', NULL, $4)
	`, uuid.New(), userID, doc.DocumentType, doc.Version)
	return nil
}

// activationCompleted reports whether the durable activation flag is set —
// used to distinguish a genuinely missing consent proof from a repeat submit
// after successful activation (idempotency).
func (h *AuthHandler) activationCompleted(ctx context.Context, userID uuid.UUID) (bool, error) {
	var done bool
	err := h.db.QueryRow(ctx, `SELECT onboarding_complete FROM users WHERE id = $1`, userID).Scan(&done)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, authapp.ErrActivationUser
	}
	return done, err
}

// createConsentTicket mints a random single-use proof binding an OTP pass to
// one user for the onboarding write path. Redis holds only the HMAC-derived
// key with the user ID as value; the raw secret leaves the server once.
func (h *AuthHandler) createConsentTicket(ctx context.Context, userID uuid.UUID) (string, error) {
	rdb := h.consentTicketStore()
	if rdb == nil {
		return "", errors.New("redis unavailable")
	}
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	secret := hex.EncodeToString(raw)
	if err := rdb.Set(ctx, h.consentTicketKey(secret), userID.String(), consentTicketTTL).Err(); err != nil {
		return "", err
	}
	return secret, nil
}

// consumeConsentTicket atomically deletes the ticket and checks it belongs to
// userID. Returns (false, nil) for missing/expired/foreign tickets.
func (h *AuthHandler) consumeConsentTicket(ctx context.Context, ticket string, userID uuid.UUID) (bool, error) {
	ticket = strings.TrimSpace(ticket)
	if ticket == "" {
		return false, nil
	}
	rdb := h.consentTicketStore()
	if rdb == nil {
		return false, errors.New("redis unavailable")
	}
	val, err := rdb.GetDel(ctx, h.consentTicketKey(ticket)).Result()
	if errors.Is(err, redis.Nil) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return val == userID.String(), nil
}

// consentTicketStore returns the shared ephemeral Redis client (the same one
// backing OTP challenges via OTPService.Client()); nil means onboarding write
// paths must fail closed.
func (h *AuthHandler) consentTicketStore() *redis.Client {
	return h.otpService.Client()
}

func (h *AuthHandler) consentTicketKey(secret string) string {
	var secretBytes []byte
	if h.otpService != nil {
		secretBytes = []byte(h.otpService.HMACSecret())
	} else {
		secretBytes = []byte("insecure-dev-otp-secret-change-me-32b+")
	}
	mac := hmac.New(sha256.New, secretBytes)
	mac.Write([]byte(strings.TrimSpace(secret)))
	return consentTicketPrefix + hex.EncodeToString(mac.Sum(nil))
}

func currentUserID(ctx context.Context) (uuid.UUID, bool) {
	return sharedauth.GetUserIDFromContext(ctx)
}

func truncateHeader(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max]
}
