package http

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"nidaw-backend/internal/shared/auth"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

// ============================================================================
// PHASE 5: DEVICE-SESSION MANAGEMENT ENDPOINTS
// ============================================================================

// requestCtxKey threads the *http.Request into a derived context so helpers
// that only receive ctx (e.g. issueAuthResponse) can still read device hints.
type requestCtxKey struct{}

func withRequest(r *http.Request) context.Context {
	return context.WithValue(r.Context(), requestCtxKey{}, r)
}

func rFromCtx(ctx context.Context) *http.Request {
	if r, ok := ctx.Value(requestCtxKey{}).(*http.Request); ok {
		return r
	}
	return nil
}

// deviceHints extracts the client-declared device name/platform used for the
// "which devices are signed in" listing. The X-Device-Name header is taken
// verbatim (trimmed/capped by the store); platform comes from an explicit
// X-Platform header or is inferred from the User-Agent.
func deviceHints(r *http.Request) (deviceName, platform string) {
	if r == nil {
		return "", ""
	}
	deviceName = strings.TrimSpace(r.Header.Get("X-Device-Name"))
	platform = strings.TrimSpace(r.Header.Get("X-Platform"))
	if platform != "" {
		return deviceName, platform
	}
	ua := strings.ToLower(r.UserAgent())
	switch {
	case strings.Contains(ua, "android"):
		platform = "android"
	case strings.Contains(ua, "iphone"), strings.Contains(ua, "ipad"), strings.Contains(ua, "ios"):
		platform = "ios"
	case strings.Contains(ua, "macintosh"), strings.Contains(ua, "mac os"):
		platform = "macos"
	case strings.Contains(ua, "windows"):
		platform = "windows"
	case strings.Contains(ua, "linux"):
		platform = "linux"
	}
	return deviceName, platform
}

// recordIssuedSession persists the durable session row for a freshly minted
// refresh token (login/register/OTP issuance paths). Best-effort: a storage
// failure logs but never locks the user out of a valid token pair; Redis-side
// rotation state still protects the flow.
func (h *AuthHandler) recordIssuedSession(ctx context.Context, userID uuid.UUID, refreshToken string, r *http.Request) {
	if h.sessions == nil {
		return
	}
	familyID := uuid.New()
	deviceName, platform := deviceHints(r)
	if _, err := h.sessions.CreateSession(ctx, userID, familyID, uuid.Nil,
		refreshToken, deviceName, platform, time.Now().Add(h.sessions.AbsoluteTTL())); err != nil {
		h.logger.Warn("failed to persist device session", zap.Error(err))
	}
}

// ListSessionsHandler handles GET /api/v1/auth/sessions.
// Returns the caller's active device sessions (never tokens or hashes), with
// the row backing the presented refresh token marked is_current when the
// client supplies it via {"refresh_token": ...}-style query parameter.
func (h *AuthHandler) ListSessionsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	userID, ok := auth.GetUserIDFromContext(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	if h.sessions == nil {
		writeError(w, http.StatusServiceUnavailable, "SESSIONS_UNAVAILABLE", "session management is not configured")
		return
	}

	currentHash := ""
	if q := strings.TrimSpace(r.URL.Query().Get("current_refresh_token")); q != "" {
		currentHash = auth.HashRefreshToken(q)
	}

	sessions, err := h.sessions.ListActive(ctx, userID, currentHash)
	if err != nil {
		h.logger.Error("failed to list device sessions", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "SESSIONS_LIST_FAILED", "failed to list sessions")
		return
	}
	if sessions == nil {
		sessions = []auth.DeviceSession{}
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"sessions": sessions,
		"policy": map[string]int64{
			"idle_ttl_seconds":     int64(h.sessionIdleTTL.Seconds()),
			"absolute_ttl_seconds": int64(h.sessions.AbsoluteTTL().Seconds()),
		},
	})
}

// RevokeSessionHandler handles DELETE /api/v1/auth/sessions/{id}.
// Revokes one listed session owned by the caller (lost-device flow). Also
// kills the Redis rotation family for that session's lineage so the revoked
// device cannot refresh until it re-authenticates.
func (h *AuthHandler) RevokeSessionHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	userID, ok := auth.GetUserIDFromContext(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	if h.sessions == nil {
		writeError(w, http.StatusServiceUnavailable, "SESSIONS_UNAVAILABLE", "session management is not configured")
		return
	}

	sessionID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_SESSION_ID", "session id must be a UUID")
		return
	}

	if err := h.sessions.RevokeByID(ctx, userID, sessionID, "user_revoked"); err != nil {
		if errors.Is(err, auth.ErrSessionNotFound) {
			// Idempotent: already revoked/purged.
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(map[string]string{"status": "revoked"})
			return
		}
		h.logger.Error("failed to revoke device session", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "SESSION_REVOKE_FAILED", "failed to revoke session")
		return
	}

	// Denylist future refreshes for this user in Redis as well; the durable row
	// is revoked, and the ephemeral JTI state mirrors it.
	if store := h.authService.TokenStore(); store != nil {
		_ = store.RevokeUserFamily(ctx, userID.String(), h.sessionIdleTTL)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "revoked"})
}

// RevokeAllSessionsHandler handles POST /api/v1/auth/sessions/revoke-all.
// Logout-everywhere: revokes every durable session for the caller and wipes
// the Redis rotation family, forcing re-authentication on all devices.
func (h *AuthHandler) RevokeAllSessionsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	userID, ok := auth.GetUserIDFromContext(ctx)
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "missing user context")
		return
	}
	if h.sessions == nil {
		writeError(w, http.StatusServiceUnavailable, "SESSIONS_UNAVAILABLE", "session management is not configured")
		return
	}

	revoked, err := h.sessions.RevokeAllForUser(ctx, userID, "logout_everywhere")
	if err != nil {
		h.logger.Error("failed to revoke all device sessions", zap.Error(err))
		writeError(w, http.StatusInternalServerError, "SESSION_REVOKE_FAILED", "failed to revoke sessions")
		return
	}
	if store := h.authService.TokenStore(); store != nil {
		_ = store.RevokeUserFamily(ctx, userID.String(), h.sessionIdleTTL)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":         "revoked",
		"sessions_count": revoked,
	})
}
