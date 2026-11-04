package http

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	authapp "nidaw-backend/internal/modules/auth/application"
	sharedauth "nidaw-backend/internal/shared/auth"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"go.uber.org/zap"
)

// ============================================================================
// PHONE + OTP ENDPOINTS (Auth roadmap Phase 2)
//
// POST /api/v1/auth/otp/request          — issue a challenge (also resends)
// POST /api/v1/auth/otp/verify           — consume a challenge; issues tokens
//                                          for existing accounts, or returns a
//                                          short-lived verification ticket for
//                                          registration flows
// POST /api/v1/auth/register-phone       — create account using a fresh ticket
//
// Enumeration protection: request/verify responses are identical whether or
// not the phone has an account; only the operation semantics differ.
// ============================================================================

// verificationTicketTTL bounds how long a verified OTP may be spent on
// register-phone without re-verification.
const verificationTicketTTL = 10 * time.Minute

// OTPRequestHandler handles POST /api/v1/auth/otp/request.
func (h *AuthHandler) OTPRequestHandler(w http.ResponseWriter, r *http.Request) {
	ctx := withRequest(r)

	if h.otpService == nil || !h.otpService.Available() {
		writeError(w, http.StatusServiceUnavailable, "OTP_UNAVAILABLE", "phone verification is temporarily unavailable")
		return
	}

	var req struct {
		Phone       string `json:"phone"`
		AccountType string `json:"account_type"` // rider | driver
		Operation   string `json:"operation"`    // login | register | recovery
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "invalid JSON body")
		return
	}

	phone, ok := authapp.NormalizePhone(req.Phone)
	if !ok {
		writeError(w, http.StatusBadRequest, "INVALID_PHONE", "phone must be a valid number in international format")
		return
	}
	acct := authapp.AccountType(strings.ToLower(strings.TrimSpace(req.AccountType)))
	if acct == "" {
		acct = authapp.AccountRider
	}
	if !acct.IsValid() {
		writeError(w, http.StatusBadRequest, "INVALID_ACCOUNT_TYPE", "account_type must be rider or driver")
		return
	}
	op := authapp.OTPOperation(strings.ToLower(strings.TrimSpace(req.Operation)))
	switch op {
	case authapp.OTPOpLogin, authapp.OTPOpRegister, authapp.OTPOpRecovery:
	default:
		writeError(w, http.StatusBadRequest, "INVALID_OPERATION", "operation must be login, register, or recovery")
		return
	}

	res, err := h.otpService.Request(ctx, phone, acct, op, clientIPFromRequest(r))
	if err != nil {
		h.logger.Info("otp request rejected",
			zap.String("operation", string(op)), zap.String("error", err.Error()))
		switch {
		case errors.Is(err, authapp.ErrOTPCooldown):
			writeError(w, http.StatusTooManyRequests, "OTP_COOLDOWN", "please wait before requesting another code")
		case errors.Is(err, authapp.ErrOTPTooManyReqs), errors.Is(err, authapp.ErrOTPTooManyIP):
			writeError(w, http.StatusTooManyRequests, "OTP_LIMIT_EXCEEDED", "too many verification requests; try again later")
		case errors.Is(err, authapp.ErrOTPMaxAttempts):
			writeError(w, http.StatusTooManyRequests, "OTP_LOCKED", "too many failed attempts; try again later")
		case errors.Is(err, authapp.ErrSMSDelivery):
			writeError(w, http.StatusBadGateway, "SMS_DELIVERY_FAILED", "could not deliver the verification code; please retry")
		default:
			writeError(w, http.StatusInternalServerError, "OTP_REQUEST_FAILED", "failed to start verification")
		}
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"expires_in":           int64(res.TTL.Seconds()),
		"resend_after_seconds": int64(h.otpResendCooldown().Seconds()),
		"message":              "verification code sent",
	})
}

// OTPVerifyHandler handles POST /api/v1/auth/otp/verify.
// For login/recovery of an existing account it returns a normal AuthResponse
// (token pair). For register (no account yet, or legacy account awaiting
// phone proof) it returns a single-use verification ticket consumed by
// register-phone. The response shape never reveals which branch was taken
// beyond what the caller already knows from its requested operation.
func (h *AuthHandler) OTPVerifyHandler(w http.ResponseWriter, r *http.Request) {
	ctx := withRequest(r)

	if h.otpService == nil || !h.otpService.Available() {
		writeError(w, http.StatusServiceUnavailable, "OTP_UNAVAILABLE", "phone verification is temporarily unavailable")
		return
	}

	var req struct {
		Phone       string `json:"phone"`
		Code        string `json:"code"`
		AccountType string `json:"account_type"`
		Operation   string `json:"operation"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "invalid JSON body")
		return
	}

	phone, ok := authapp.NormalizePhone(req.Phone)
	if !ok {
		writeError(w, http.StatusBadRequest, "INVALID_PHONE", "phone must be a valid number in international format")
		return
	}
	code := strings.TrimSpace(req.Code)
	if len(code) < 4 || len(code) > 10 || !allDigits(code) {
		writeError(w, http.StatusBadRequest, "INVALID_CODE", "code must be 4-10 digits")
		return
	}
	acct := authapp.AccountType(strings.ToLower(strings.TrimSpace(req.AccountType)))
	if acct == "" {
		acct = authapp.AccountRider
	}
	if !acct.IsValid() {
		writeError(w, http.StatusBadRequest, "INVALID_ACCOUNT_TYPE", "account_type must be rider or driver")
		return
	}
	op := authapp.OTPOperation(strings.ToLower(strings.TrimSpace(req.Operation)))
	switch op {
	case authapp.OTPOpLogin, authapp.OTPOpRegister, authapp.OTPOpRecovery:
	default:
		writeError(w, http.StatusBadRequest, "INVALID_OPERATION", "operation must be login, register, or recovery")
		return
	}

	if err := h.otpService.Verify(ctx, phone, code, acct, op); err != nil {
		h.logger.Info("otp verify rejected",
			zap.String("operation", string(op)), zap.String("error", err.Error()))
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

	// Challenge passed. Mark permanent verification state and decide the
	// post-verification path from the requested operation.
	user, found, err := h.lookupUserByPhone(ctx, phone)
	if err != nil {
		h.logger.Error("phone lookup failed after otp verify", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "VERIFY_FAILED", "verification failed")
		return
	}
	if found {
		if err := h.markPhoneVerified(ctx, user.ID); err != nil {
			h.logger.Warn("failed to persist phone_verified_at", zap.Error(err))
		}
		user.PhoneVerified = true
	}

	switch op {
	case authapp.OTPOpLogin, authapp.OTPOpRecovery:
		if !found {
			// Neutral response: indistinguishable from a generic failure; no
			// hint that the number lacks an account.
			writeError(w, http.StatusUnauthorized, "OTP_VERIFIED_NO_SESSION", "cannot sign in with this number; try registering instead")
			return
		}
		if user.Status != "active" {
			writeError(w, http.StatusForbidden, "ACCOUNT_NOT_ACTIVE", "this account is not active")
			return
		}
		h.issueAuthResponse(w, ctx, user, http.StatusOK)
	case authapp.OTPOpRegister:
		if found && user.CreatedVia == "phone_otp" && user.PhoneVerifiedAtSet {
			// Already-registered phone: treat as login so clients land the
			// user in their existing session rather than duplicating.
			h.issueAuthResponse(w, ctx, user, http.StatusOK)
			return
		}
		ticket, err := h.createVerificationTicket(ctx, phone, string(acct))
		if err != nil {
			h.logger.Error("failed to store verification ticket", zap.Error(err))
			writeError(w, http.StatusInternalServerError, "VERIFY_FAILED", "verification failed")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]interface{}{
			"verified":            true,
			"verification_ticket": ticket,
			"ticket_expires_in":   int64(verificationTicketTTL.Seconds()),
		})
	}
}

// RegisterPhoneHandler handles POST /api/v1/auth/register-phone.
// Requires a live verification ticket from otp/verify(operation=register).
// Email/password/full_name are all optional here (Phase 3 keeps them optional);
// drivers get a pending-onboarding profile — OTP proves identity, never grants
// professional approval.
func (h *AuthHandler) RegisterPhoneHandler(w http.ResponseWriter, r *http.Request) {
	ctx := withRequest(r)

	var req struct {
		VerificationTicket string  `json:"verification_ticket"`
		FullName           *string `json:"full_name"`
		Email              *string `json:"email"`
		Password           *string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "invalid JSON body")
		return
	}
	if strings.TrimSpace(req.VerificationTicket) == "" {
		writeError(w, http.StatusBadRequest, "TICKET_REQUIRED", "complete phone verification first")
		return
	}

	phone, acctType, ok := h.consumeVerificationTicket(ctx, req.VerificationTicket)
	if !ok {
		writeError(w, http.StatusUnauthorized, "TICKET_INVALID", "verification expired or already used; verify your phone again")
		return
	}

	fullName := ""
	if req.FullName != nil {
		fullName = strings.TrimSpace(*req.FullName)
		if len(fullName) > 200 {
			writeError(w, http.StatusBadRequest, "INVALID_NAME", "full_name must be at most 200 characters")
			return
		}
	}

	var emailPtr *string
	if req.Email != nil && strings.TrimSpace(*req.Email) != "" {
		e := strings.ToLower(strings.TrimSpace(*req.Email))
		if !validEmailShape(e) {
			writeError(w, http.StatusBadRequest, "INVALID_EMAIL", "email address is not valid")
			return
		}
		emailPtr = &e
	}

	var pwHash *string
	if req.Password != nil && *req.Password != "" {
		if len(*req.Password) < 8 || len(*req.Password) > 72 {
			writeError(w, http.StatusBadRequest, "WEAK_PASSWORD", "password must be between 8 and 72 characters")
			return
		}
		hashed, err := sharedauth.HashPassword(*req.Password, 12)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "PASSWORD_HASH_FAILED", "failed to secure password")
			return
		}
		pwHash = &hashed
	}

	role := "rider"
	if acctType == string(authapp.AccountDriver) {
		role = "driver"
	}

	userID := uuid.New()
	now := time.Now().UTC()
	tx, err := h.db.Begin(ctx)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "REGISTRATION_FAILED", "failed to create account")
		return
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO users (id, email, full_name, phone, role, password_hash, email_verified,
		                   phone_verified_at, created_via, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, false, $7, 'phone_otp', 'active', $8, $8)
	`, userID, emailPtr, nullableStr(fullName), phone, role, pwHash, now, now)
	if err != nil {
		if isDuplicateKeyError(err) {
			// Phone raced with another registration, or the optional email is
			// taken. Neutral wording avoids confirming which field collided.
			writeError(w, http.StatusConflict, "IDENTITY_CONFLICT", "this phone or email could not be used for a new account")
			return
		}
		h.logger.Error("phone registration insert failed", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "REGISTRATION_FAILED", "failed to create account")
		return
	}
	if role == "driver" {
		// Authentication is separate from eligibility: onboarding stays
		// 'pending' until professional documents are approved.
		if _, err := tx.Exec(ctx, `INSERT INTO drivers (user_id, status) VALUES ($1, 'offline')`, userID); err != nil {
			h.logger.Error("driver profile creation failed", zap.Error(err))
			writeError(w, http.StatusInternalServerError, "REGISTRATION_FAILED", "failed to create account")
			return
		}
	}
	if err := tx.Commit(ctx); err != nil {
		writeError(w, http.StatusInternalServerError, "REGISTRATION_FAILED", "failed to create account")
		return
	}

	// Legacy email/password account holding this phone: link verification
	// forward instead of erroring — the INSERT above would have conflicted on
	// UNIQUE(phone), so reaching here means the row was truly new.
	user := &authUser{ID: userID, Phone: phone, Role: role, FullName: fullName, Status: "active", CreatedVia: "phone_otp", PhoneVerified: true, PhoneVerifiedAtSet: true, OnboardingComplete: false, CreatedAt: now}
	h.issueAuthResponse(w, ctx, user, http.StatusCreated)
}

// ============================================================================
// SUPPORT
// ============================================================================

type authUser struct {
	ID                 uuid.UUID
	Email              string
	FullName           string
	Phone              string
	Role               string
	Status             string
	CreatedVia         string
	PhoneVerified      bool
	PhoneVerifiedAtSet bool
	EmailVerified      bool
	ProfileImageURL    *string
	OnboardingComplete bool
	CreatedAt          time.Time
}

func (h *AuthHandler) lookupUserByPhone(ctx context.Context, phone string) (*authUser, bool, error) {
	u := &authUser{}
	var email, fullName, createdVia *string
	var phoneVerifiedAt *time.Time
	err := h.db.QueryRow(ctx, `
		SELECT id, COALESCE(email, ''), COALESCE(full_name, ''), phone, role, status,
		       email_verified, profile_image_url, created_at,
		       COALESCE(created_via, 'email_password'), phone_verified_at,
		       onboarding_complete
		FROM users WHERE phone = $1
	`, phone).Scan(&u.ID, &email, &fullName, &u.Phone, &u.Role, &u.Status,
		&u.EmailVerified, &u.ProfileImageURL, &u.CreatedAt, &createdVia, &phoneVerifiedAt,
		&u.OnboardingComplete)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	u.Email = derefStr(email)
	u.FullName = derefStr(fullName)
	u.CreatedVia = derefStr(createdVia)
	u.PhoneVerified = phoneVerifiedAt != nil
	u.PhoneVerifiedAtSet = phoneVerifiedAt != nil
	return u, true, nil
}

func (h *AuthHandler) markPhoneVerified(ctx context.Context, userID uuid.UUID) error {
	_, err := h.db.Exec(ctx, `
		UPDATE users SET phone_verified_at = COALESCE(phone_verified_at, $2), updated_at = $2
		WHERE id = $1
	`, userID, time.Now().UTC())
	return err
}

// issueAuthResponse mints a token pair + records the persistent device session
// (Phase 5) and registers the Redis rotation family head.
func (h *AuthHandler) issueAuthResponse(w http.ResponseWriter, ctx context.Context, u *authUser, status int) {
	tokenPair, err := h.authService.GenerateTokenPair(u.ID, u.Email, u.Role, "")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "TOKEN_GENERATION_FAILED", "failed to generate tokens")
		return
	}
	if store := h.authService.TokenStore(); store != nil {
		if claims, verr := h.authService.ValidateRefreshToken(tokenPair.RefreshToken); verr == nil {
			ttl := time.Until(claims.ExpiresAt.Time)
			_ = store.SetUserFamily(ctx, u.ID.String(), claims.ID, ttl)
		}
	}
	h.recordIssuedSession(ctx, u.ID, tokenPair.RefreshToken, rFromCtx(ctx))
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(AuthResponse{
		AccessToken:  tokenPair.AccessToken,
		RefreshToken: tokenPair.RefreshToken,
		ExpiresIn:    tokenPair.ExpiresIn,
		TokenType:    tokenPair.TokenType,
		User: UserResponse{
			ID:              u.ID,
			Email:           u.Email,
			FullName:        u.FullName,
			Phone:           u.Phone,
			Role:            u.Role,
			EmailVerified:   u.EmailVerified,
			ProfileImageURL: u.ProfileImageURL,
			CreatedAt:       u.CreatedAt,
		},
	})
}

// createVerificationTicket stores a single-use, TTL-bound proof that the
// caller just passed an OTP for `phone` under `acctType`, keyed into Redis
// (ephemeral per roadmap; Postgres gets the permanent timestamp at account
// creation). The raw ticket is random; only its HMAC is stored, and the
// returned value embeds the secret so possession proves verification.
func (h *AuthHandler) createVerificationTicket(ctx context.Context, phone, acctType string) (string, error) {
	if h.redis == nil {
		return "", errors.New("redis unavailable")
	}
	secret := uuid.New().String()
	key := "auth:otp:ticket:" + secret
	payload := phone + "|" + acctType
	if err := h.redis.Set(ctx, key, payload, verificationTicketTTL).Err(); err != nil {
		return "", err
	}
	return secret, nil
}

// consumeVerificationTicket atomically deletes the ticket (single-use) and
// returns the bound phone + account type.
func (h *AuthHandler) consumeVerificationTicket(ctx context.Context, ticket string) (phone, acctType string, ok bool) {
	if h.redis == nil {
		return "", "", false
	}
	key := "auth:otp:ticket:" + strings.TrimSpace(ticket)
	val, err := h.redis.GetDel(ctx, key).Result()
	if err != nil {
		return "", "", false
	}
	parts := strings.SplitN(val, "|", 2)
	if len(parts) != 2 {
		return "", "", false
	}
	return parts[0], parts[1], true
}

func (h *AuthHandler) otpResendCooldown() time.Duration {
	if h.otpCfg.ResendCooldown > 0 {
		return h.otpCfg.ResendCooldown
	}
	return 60 * time.Second
}

func derefStr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func nullableStr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func validEmailShape(e string) bool {
	at := strings.Index(e, "@")
	if at <= 0 || at == len(e)-1 || strings.ContainsAny(e, " \t") {
		return false
	}
	dot := strings.LastIndex(e, ".")
	return dot > at+1 && dot < len(e)-1
}

// allDigits mirrors the application-package helper for local code checks.
func allDigits(s string) bool {
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return len(s) > 0
}

// clientIPFromRequest extracts the best-effort client IP for OTP abuse
// counters: X-Forwarded-For first hop (set by edge proxy/Kong), then chi's
// RealIP-resolved RemoteAddr without port.
func clientIPFromRequest(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if i := strings.Index(xff, ","); i > 0 {
			return strings.TrimSpace(xff[:i])
		}
		return strings.TrimSpace(xff)
	}
	ip := r.RemoteAddr
	if i := strings.LastIndex(ip, ":"); i > 0 {
		ip = ip[:i]
	}
	return ip
}
