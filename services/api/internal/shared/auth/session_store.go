package auth

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
)

// ============================================================================
// PHASE 5: PERSISTENT DEVICE SESSIONS (PostgreSQL, permanent record)
//
// Every issued refresh token gets one row in auth_device_sessions keyed by its
// SHA-256 hash. Rotation inserts a child row (same family_id, rotated_from =
// parent). Reuse of a consumed/revoked row triggers whole-family revocation.
// Idle expiry is enforced from last_used_at against the configured idle TTL;
// absolute expiry is stored per row (issued_at + refresh TTL). Redis keeps
// only the ephemeral JTI denylist — this table is the durable truth for
// "which devices are signed in" and powers list/revoke/revoke-all/logout-everywhere.
// ============================================================================

// SessionStoreConfig carries the server-side session policy.
type SessionStoreConfig struct {
	IdleTTL     time.Duration // sessions unused longer than this are expired
	AbsoluteTTL time.Duration // hard cap = REFRESH_TOKEN_TTL
}

// DeviceSession is the read model returned to clients (never contains the
// token or its hash).
type DeviceSession struct {
	ID         uuid.UUID `json:"id"`
	FamilyID   uuid.UUID `json:"family_id"`
	DeviceName string    `json:"device_name"`
	Platform   string    `json:"platform"`
	CreatedAt  time.Time `json:"created_at"`
	LastUsedAt time.Time `json:"last_used_at"`
	ExpiresAt  time.Time `json:"expires_at"`
	Current    bool      `json:"is_current"`
}

// ErrSessionNotFound is returned when a session row does not exist (e.g. it
// was already purged) — callers treat revoke-on-missing as idempotent success.
var ErrSessionNotFound = errors.New("device session not found")

// SessionDB is the subset of the shared Postgres pool used here; keeping it
// as an interface lets handlers/tests pass a fake.
type SessionDB interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (rows pgx.Rows, err error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// SessionStore persists device sessions in PostgreSQL. A nil store disables
// persistence (rotation degrades to Redis-only), matching TokenStore's
// nil-tolerant convention so environments without the migration can boot.
type SessionStore struct {
	db     SessionDB
	config SessionStoreConfig
}

// NewSessionStore wraps the shared database pool with the session policy.
func NewSessionStore(db SessionDB, cfg SessionStoreConfig) *SessionStore {
	if cfg.AbsoluteTTL <= 0 {
		cfg.AbsoluteTTL = 7 * 24 * time.Hour
	}
	if cfg.IdleTTL <= 0 {
		cfg.IdleTTL = 30 * 24 * time.Hour
	}
	return &SessionStore{db: db, config: cfg}
}

// HashRefreshToken computes the server-side lookup key for a refresh token.
func HashRefreshToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// AbsoluteTTL exposes the configured absolute session lifetime so handlers
// mint tokens and rows with the same horizon.
func (s *SessionStore) AbsoluteTTL() time.Duration {
	if s == nil {
		return 0
	}
	return s.config.AbsoluteTTL
}

// CreateSession records a freshly issued refresh token as the head of a new
// family (rotatedFrom == uuid.Nil) or as a rotation child of an existing row.
func (s *SessionStore) CreateSession(
	ctx context.Context,
	userID, familyID, rotatedFrom uuid.UUID,
	refreshToken, deviceName, platform string,
	expiresAt time.Time,
) (uuid.UUID, error) {
	if s == nil || s.db == nil {
		return uuid.Nil, nil
	}
	var id uuid.UUID
	var fromArg any
	if rotatedFrom != uuid.Nil {
		fromArg = rotatedFrom
	}
	err := s.db.QueryRow(ctx, `
		INSERT INTO auth_device_sessions (
			user_id, family_id, refresh_token_hash, rotated_from,
			device_name, platform, expires_at
		) VALUES ($1, $2, $3, $4, NULLIF($5, ''), NULLIF($6, ''), $7)
		RETURNING id`,
		userID, familyID, HashRefreshToken(refreshToken), fromArg,
		truncate(deviceName, 120), truncate(platform, 40), expiresAt,
	).Scan(&id)
	if err != nil {
		return uuid.Nil, err
	}
	return id, nil
}

// ConsumeResult describes the outcome of presenting a refresh token.
type ConsumeResult struct {
	SessionID uuid.UUID
	FamilyID  uuid.UUID
	// RotateFrom is the row id to use as rotated_from on the next issuance.
	RotateFrom uuid.UUID
	Reuse      bool // token was revoked/expired/idle-stale => suspected theft
}

// ConsumeRefresh validates a presented refresh token against the durable
// record: marks the row revoked('rotated'), returns the family lineage, and
// flags reuse when the hash matches a row that is no longer active.
func (s *SessionStore) ConsumeRefresh(ctx context.Context, refreshToken string) (*ConsumeResult, error) {
	if s == nil || s.db == nil {
		return nil, nil
	}
	hash := HashRefreshToken(refreshToken)

	var res ConsumeResult
	var revokedAt pgtype.Timestamptz
	var lastUsed, expiresAt time.Time
	err := s.db.QueryRow(ctx, `
		SELECT id, user_id, family_id, rotated_from, revoked_at, last_used_at, expires_at
		FROM auth_device_sessions
		WHERE refresh_token_hash = $1`,
		hash,
	).Scan(&res.SessionID, new(uuid.UUID), &res.FamilyID, new(pgtype.UUID), &revokedAt, &lastUsed, &expiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		// Unknown hash: pre-Phase-5 sessions were never recorded. Allow the
		// JWT itself (already validated upstream) and adopt it into a new
		// family keyed by the session-less flow.
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	if revokedAt.Valid || expiresAt.Before(time.Now()) || s.idleExpired(lastUsed) {
		res.Reuse = true
		return &res, nil
	}

	tag, err := s.db.Exec(ctx, `
		UPDATE auth_device_sessions
		SET revoked_at = now(), revoke_reason = 'rotated'
		WHERE id = $1 AND revoked_at IS NULL`,
		res.SessionID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		// Lost a rotation race; treat as reuse so the family is killed safely.
		res.Reuse = true
		return &res, nil
	}
	res.RotateFrom = res.SessionID
	return &res, nil
}

func (s *SessionStore) idleExpired(lastUsed time.Time) bool {
	return time.Since(lastUsed) > s.config.IdleTTL
}

// Touch updates last_used_at for the session whose hash matches the current
// access-token-bearing session (best-effort; called from middleware-free paths
// such as /auth/me so idle expiry reflects real activity).
func (s *SessionStore) TouchByRefreshHash(ctx context.Context, refreshToken string) error {
	if s == nil || s.db == nil {
		return nil
	}
	_, err := s.db.Exec(ctx, `
		UPDATE auth_device_sessions SET last_used_at = now()
		WHERE refresh_token_hash = $1 AND revoked_at IS NULL`,
		HashRefreshToken(refreshToken))
	return err
}

// ListActive returns non-revoked, non-expired sessions for a user, newest
// first. currentHash marks which row backs the caller's present session.
func (s *SessionStore) ListActive(ctx context.Context, userID uuid.UUID, currentHash string) ([]DeviceSession, error) {
	if s == nil || s.db == nil {
		return nil, nil
	}
	rows, err := s.db.Query(ctx, `
		SELECT id, family_id, COALESCE(device_name, ''), COALESCE(platform, ''),
		       created_at, last_used_at, expires_at
		FROM auth_device_sessions
		WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > now()
		ORDER BY created_at DESC`,
		userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []DeviceSession
	for rows.Next() {
		var d DeviceSession
		if err := rows.Scan(&d.ID, &d.FamilyID, &d.DeviceName, &d.Platform,
			&d.CreatedAt, &d.LastUsedAt, &d.ExpiresAt); err != nil {
			return nil, err
		}
		d.Current = currentHash != "" && d.matches(currentHash)
		out = append(out, d)
	}
	return out, rows.Err()
}

// RevokesAllForUser marks every active session revoked with the given reason.
func (s *SessionStore) RevokeAllForUser(ctx context.Context, userID uuid.UUID, reason string) (int64, error) {
	if s == nil || s.db == nil {
		return 0, nil
	}
	tag, err := s.db.Exec(ctx, `
		UPDATE auth_device_sessions
		SET revoked_at = now(), revoke_reason = $3
		WHERE user_id = $1 AND revoked_at IS NULL`,
		userID, reason)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// RevokeFamily marks every active row in a family revoked (used on reuse).
func (s *SessionStore) RevokeFamily(ctx context.Context, familyID uuid.UUID, reason string) (int64, error) {
	if s == nil || s.db == nil {
		return 0, nil
	}
	tag, err := s.db.Exec(ctx, `
		UPDATE auth_device_sessions
		SET revoked_at = now(), revoke_reason = $2
		WHERE family_id = $1 AND revoked_at IS NULL`,
		familyID, reason)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// RevokeByID revokes one listed session owned by userID (lost-device /
// sign-out-from-device flow). Returns ErrSessionNotFound when the row is
// missing or belongs to another user.
func (s *SessionStore) RevokeByID(ctx context.Context, userID, sessionID uuid.UUID, reason string) error {
	if s == nil || s.db == nil {
		return nil
	}
	tag, err := s.db.Exec(ctx, `
		UPDATE auth_device_sessions
		SET revoked_at = now(), revoke_reason = $3
		WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL`,
		sessionID, userID, reason)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrSessionNotFound
	}
	return nil
}

// helpers -------------------------------------------------------------------

func truncate(v string, max int) string {
	v = strings.TrimSpace(strings.ReplaceAll(strings.ReplaceAll(v, "\n", " "), "\r", ""))
	if len(v) <= max {
		return v
	}
	return v[:max]
}

func subtleEqual(a, b string) bool {
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}
