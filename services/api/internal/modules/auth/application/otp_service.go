package application

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

// ============================================================================
// OTP SERVICE — phone-number challenge codes (Auth roadmap Phase 2)
//
// Challenges live exclusively in Redis with TTLs; permanent records (the
// verified timestamp on users) are written by the HTTP layer. Every challenge
// is bound to the normalized phone number, the account type (rider|driver)
// and the intended operation (login|register|recovery|substitute_invite), so
// a code issued for one purpose can never satisfy another. Codes are stored
// only as HMAC-SHA256 digests keyed by OTP_HMAC_SECRET — a Redis dump never
// reveals live codes.
// ============================================================================

// OTPOperation enumerates the server-sanctioned purposes an OTP challenge may
// be bound to. Clients cannot invent values; unknown operations are rejected.
type OTPOperation string

const (
	OTPOpLogin            OTPOperation = "login"
	OTPOpRegister         OTPOperation = "register"
	OTPOpRecovery         OTPOperation = "recovery"
	OTPOpSubstituteInvite OTPOperation = "substitute_invite"
)

func (o OTPOperation) valid() bool {
	switch o {
	case OTPOpLogin, OTPOpRegister, OTPOpRecovery, OTPOpSubstituteInvite:
		return true
	}
	return false
}

// AccountType distinguishes rider vs driver challenges so a rider-purpose
// code cannot authorize a driver login and vice versa.
type AccountType string

const (
	AccountRider  AccountType = "rider"
	AccountDriver AccountType = "driver"
)

func (a AccountType) IsValid() bool { return a == AccountRider || a == AccountDriver }

// OTP errors. Handlers map these to neutral client-facing messages; none of
// them reveal whether a phone number has an account.
var (
	ErrOTPCooldown      = errors.New("otp resend cooldown active")
	ErrOTPTooManyReqs   = errors.New("otp request limit exceeded for this identity")
	ErrOTPTooManyIP     = errors.New("otp request limit exceeded")
	ErrOTPNoChallenge   = errors.New("no active otp challenge")
	ErrOTPExpired       = errors.New("otp challenge expired")
	ErrOTPMaxAttempts   = errors.New("otp attempt limit exceeded")
	ErrOTPInvalidCode   = errors.New("otp code does not match")
	ErrSMSDelivery      = errors.New("sms provider delivery failed")
	ErrOTPInvalidParams = errors.New("invalid otp parameters")
)

// OTPConfig is injected from shared config; zero values fall back to safe
// production defaults.
type OTPConfig struct {
	TTL                time.Duration // challenge lifetime (OTP_TTL_SECONDS)
	ResendCooldown     time.Duration // minimum gap between sends (OTP_RESEND_COOLDOWN_SECONDS)
	MaxAttempts        int           // wrong-code attempts before burn (OTP_MAX_ATTEMPTS)
	MaxRequestsPerHour int           // per phone+op window (OTP_MAX_REQUESTS_PER_HOUR)
	CodeLength         int           // digits (default 6)
	HMACSecret         string        // OTP_HMAC_SECRET, >=32 chars enforced at config level
}

func (c OTPConfig) withDefaults() OTPConfig {
	if c.TTL <= 0 {
		c.TTL = 5 * time.Minute
	}
	if c.ResendCooldown == 0 {
		c.ResendCooldown = 60 * time.Second
	} // explicit negative ResendCooldown disables the resend gate (test/ops override)
	if c.MaxAttempts <= 0 {
		c.MaxAttempts = 5
	}
	if c.MaxRequestsPerHour <= 0 {
		c.MaxRequestsPerHour = 6
	}
	if c.CodeLength <= 0 {
		c.CodeLength = 6
	}
	if c.HMACSecret == "" {
		c.HMACSecret = "insecure-dev-otp-secret-change-me-32b+"
	}
	return c
}

// SMSSender is the narrow port the OTP service needs from the notifications
// integration (an adapter over MultiProviderNotificationService satisfies it).
type SMSSender interface {
	SendOTP(ctx context.Context, to, code string) error
}

// OTPService issues and verifies phone-bound OTP challenges in Redis.
type OTPService struct {
	rdb    *redis.Client
	sender SMSSender
	cfg    OTPConfig
}

// NewOTPService builds the service. A nil redis client or sender makes every
// request fail explicitly (Available() == false) rather than silently
// accepting any code.
func NewOTPService(rdb *redis.Client, sender SMSSender, cfg OTPConfig) *OTPService {
	return &OTPService{rdb: rdb, sender: sender, cfg: cfg.withDefaults()}
}

// Available reports whether the service can process challenges at all.
func (s *OTPService) Available() bool { return s != nil && s.rdb != nil && s.sender != nil }

// Client returns the raw Redis client so sibling flows in this module (e.g.
// onboarding consent tickets) share one ephemeral store without opening a
// second connection pool.
func (s *OTPService) Client() *redis.Client {
	if s == nil {
		return nil
	}
	return s.rdb
}

// HMACSecret returns the configured challenge-digest secret, used by the
// HTTP layer to derive ticket keys without duplicating configuration wiring.
func (s *OTPService) HMACSecret() string {
	if s == nil {
		return ""
	}
	return s.cfg.HMACSecret
}

// key derivation ---------------------------------------------------------------
// All keys embed the triple (phone, account_type, operation) so challenges are
// cryptographically scoped to their intended use.

func otpKey(phone string, acct AccountType, op OTPOperation) string {
	return fmt.Sprintf("auth:otp:%s:%s:%s", op, acct, phone)
}
func otpAttemptsKey(key string) string { return key + ":attempts" }
func otpCooldownKey(key string) string { return key + ":cooldown" }
func otpHourKey(key string) string     { return key + ":hour" }
func otpBurnKey(key string) string     { return key + ":burned" }
func otpIPKey(ip string, op OTPOperation) string {
	return fmt.Sprintf("auth:otp:ip:%s:%s", ip, op)
}

// NormalizePhone canonicalizes E.164-ish input: strips spaces/dashes/parens
// and legacy trunk-prefix artifacts (+25109... → +2519...), and enforces
// length limits. Returns ("", false) for anything unusable so the handler can
// emit a validation error without touching Redis.
func NormalizePhone(raw string) (string, bool) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", false
	}
	var b strings.Builder
	for _, r := range trimmed {
		switch r {
		case ' ', '-', '(', ')', '.':
			continue
		default:
			b.WriteRune(r)
		}
	}
	p := b.String()
	if strings.HasPrefix(p, "+") {
		rest := p[1:]
		if !allDigits(rest) {
			return "", false
		}
		// Legacy trunk artifact: "+CC0NXX..." (e.g. +2510911...) — a single
		// zero between the country code and the subscriber number. Strip at
		// most one zero, but only when the remainder still forms a plausible
		// subscriber number (>=8 digits); otherwise keep the original digits.
		digits := rest
		if len(digits) >= 9 && digits[0] == '0' && len(digits)-1 >= 8 {
			digits = digits[1:]
		}
		if len(digits) < 8 || len(digits) > 15 {
			return "", false
		}
		return "+" + digits, true
	}
	// International format without the '+' sign (e.g. "251911223344").
	// Bare national formats are rejected as ambiguous without a country code.
	if allDigits(p) && len(p) >= 10 && len(p) <= 16 && (p[0] == '1' || p[0] == '2') {
		return "+" + p, true
	}
	return "", false
}

func allDigits(s string) bool {
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return len(s) > 0
}

// generateCode returns a cryptographically random digit string of CodeLength.
func (s *OTPService) generateCode() (string, error) {
	max := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(s.cfg.CodeLength)), nil)
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%0*d", s.cfg.CodeLength, n.Int64()), nil
}

// hashCode digests a code with the OTP secret; verification compares digests
// in constant time so raw codes never persist server-side.
func (s *OTPService) hashCode(code string) string {
	mac := hmac.New(sha256.New, []byte(s.cfg.HMACSecret))
	mac.Write([]byte(code))
	return hex.EncodeToString(mac.Sum(nil))
}

// RequestResult communicates outcome without leaking identity existence.
type RequestResult struct {
	SentAt time.Time
	TTL    time.Duration
}

// reserveQuota atomically consumes one unit of an hourly counter, setting the
// TTL only when the key is freshly created. It returns the post-increment
// count; callers roll back with Decr when the limit would be exceeded so
// rejected requests never consume quota.
func (s *OTPService) reserveQuota(ctx context.Context, key string) (int64, error) {
	const script = `local c = redis.call('INCR', KEYS[1]) if c == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end return c`
	return s.rdb.Eval(ctx, script, []string{key}, int(time.Hour.Seconds())).Int64()
}

// errCooldownActive is the internal signal from startCooldown that the
// resend window for this identity is still open.
var errCooldownActive = errors.New("otp cooldown gate held")

// startCooldown atomically takes the resend gate for a challenge key using
// SET NX PX with millisecond precision. It returns errCooldownActive when an
// earlier send happened less than ResendCooldown ago. Because the gate's TTL
// equals exactly the cooldown duration, "gate present" and "cooldown active"
// are the same condition — no clock-skew or remaining-TTL heuristics needed.
func (s *OTPService) startCooldown(ctx context.Context, key string) error {
	const script = `if tonumber(ARGV[2]) <= 0 then return 'OK' end return redis.call('SET', KEYS[1], ARGV[1], 'NX', 'PX', ARGV[2])`
	res, err := s.rdb.Eval(ctx, script, []string{otpCooldownKey(key)},
		time.Now().UTC().Format(time.RFC3339Nano),
		s.cfg.ResendCooldown.Milliseconds()).Result()
	if errors.Is(err, redis.Nil) {
		// SET NX returned no reply because the gate is still held.
		return errCooldownActive
	}
	if err != nil {
		return err
	}
	if res == nil {
		return errCooldownActive
	}
	return nil
}

// Request issues (or resends) a challenge for phone+account+operation.
// Enforcement order: availability → parameter validity → burn state →
// cooldown → hourly quota (per identity and per source IP) → generation →
// store → SMS send. On SMS failure the challenge, cooldown, and any consumed
// quota are rolled back so provider hiccups neither burn quota nor leave
// dangling codes.
func (s *OTPService) Request(ctx context.Context, phone string, acct AccountType, op OTPOperation, sourceIP string) (*RequestResult, error) {
	if !s.Available() {
		return nil, ErrSMSDelivery
	}
	if !acct.IsValid() || !op.valid() {
		return nil, ErrOTPInvalidParams
	}
	key := otpKey(phone, acct, op)

	// Burned identities must wait out the window before re-requesting.
	if exists, _ := s.rdb.Exists(ctx, otpBurnKey(key)).Result(); exists > 0 {
		return nil, ErrOTPMaxAttempts
	}
	// Cooldown between sends (prevents SMS bombing of one identity). The
	// gate stores the send timestamp and lives exactly ResendCooldown
	// seconds, set atomically via SET NX PX in Lua so concurrent requests
	// cannot both pass. A successful Verify deletes it, so a consumed
	// challenge never delays requesting the next one.
	if err := s.startCooldown(ctx, key); err != nil {
		if errors.Is(err, errCooldownActive) {
			return nil, ErrOTPCooldown
		}
		return nil, err
	}
	// Per-identity hourly quota.
	hourKey := otpHourKey(key)
	count, err := s.reserveQuota(ctx, hourKey)
	if err != nil {
		return nil, err
	}
	if count > int64(s.cfg.MaxRequestsPerHour) {
		_ = s.rdb.Decr(ctx, hourKey).Err()
		return nil, ErrOTPTooManyReqs
	}
	// Per-IP quota across identities (abuse pump-brake).
	ipKey := otpIPKey(sourceIP, op)
	ipCount, err := s.reserveQuota(ctx, ipKey)
	if err != nil {
		_ = s.rdb.Decr(ctx, hourKey).Err()
		return nil, err
	}
	if ipCount > int64(s.cfg.MaxRequestsPerHour*10) {
		_ = s.rdb.Decr(ctx, hourKey).Err()
		_ = s.rdb.Decr(ctx, ipKey).Err()
		return nil, ErrOTPTooManyIP
	}

	code, err := s.generateCode()
	if err != nil {
		return nil, err
	}
	ttl := s.cfg.TTL
	if err := s.rdb.Set(ctx, key, s.hashCode(code), ttl).Err(); err != nil {
		return nil, err
	}
	// Reset attempt counter for the fresh challenge. The cooldown gate was
	// already taken atomically by startCooldown above (SET NX PX, exactly
	// ResendCooldown seconds); Verify deletes it on success so a consumed
	// challenge never delays requesting the next one.
	_ = s.rdb.Del(ctx, otpAttemptsKey(key)).Err()

	if err := s.sender.SendOTP(ctx, phone, code); err != nil {
		_ = s.rdb.Del(ctx, key, otpCooldownKey(key)).Err()
		_ = s.rdb.Decr(ctx, hourKey).Err()
		_ = s.rdb.Decr(ctx, ipKey).Err()
		return nil, ErrSMSDelivery
	}
	return &RequestResult{SentAt: time.Now().UTC(), TTL: ttl}, nil
}

// Verify consumes a challenge on success (single-use). Failure modes are
// distinguished so handlers can apply consistent lockout semantics. Replays
// of a consumed code hit ErrOTPNoChallenge because the digest is deleted
// atomically with the success return.
func (s *OTPService) Verify(ctx context.Context, phone, code string, acct AccountType, op OTPOperation) error {
	if !s.Available() {
		return ErrSMSDelivery
	}
	if !acct.IsValid() || !op.valid() {
		return ErrOTPInvalidParams
	}
	key := otpKey(phone, acct, op)

	if exists, _ := s.rdb.Exists(ctx, otpBurnKey(key)).Result(); exists > 0 {
		return ErrOTPMaxAttempts
	}
	stored, err := s.rdb.Get(ctx, key).Result()
	if err == redis.Nil {
		return ErrOTPNoChallenge
	}
	if err != nil {
		return err
	}

	attempts, err := s.rdb.Incr(ctx, otpAttemptsKey(key)).Result()
	if err != nil {
		return err
	}
	if attempts == 1 {
		// Attempt counter should not outlive the challenge itself.
		if ttl, terr := s.rdb.TTL(ctx, key).Result(); terr == nil && ttl > 0 {
			_ = s.rdb.Expire(ctx, otpAttemptsKey(key), ttl).Err()
		}
	}
	if int(attempts) > s.cfg.MaxAttempts {
		// Burn the identity window: drop the challenge and forbid further
		// attempts until the hourly quota resets.
		burnTTL := 15 * time.Minute
		if remaining, rerr := s.rdb.TTL(ctx, otpHourKey(key)).Result(); rerr == nil && remaining > 0 {
			burnTTL = remaining
		}
		_ = s.rdb.Del(ctx, key).Err()
		_ = s.rdb.Set(ctx, otpBurnKey(key), "1", burnTTL).Err()
		return ErrOTPMaxAttempts
	}

	given := s.hashCode(strings.TrimSpace(code))
	if subtle.ConstantTimeCompare([]byte(given), []byte(stored)) != 1 {
		return ErrOTPInvalidCode
	}

	// Success: single-use consumption (delete challenge + counters) before
	// returning.
	pipe := s.rdb.TxPipeline()
	pipe.Del(ctx, key)
	pipe.Del(ctx, otpAttemptsKey(key))
	pipe.Del(ctx, otpCooldownKey(key))
	if _, err := pipe.Exec(ctx); err != nil {
		return err
	}
	return nil
}
