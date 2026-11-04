package auth

// ============================================================================
// TEST-ONLY fakes + unit tests for the durable device-session store:
// issuance, rotation consume, reuse detection (revoked/expired/race), and
// family/user revocation — all without a live Postgres.
// ============================================================================

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"nidaw-backend/internal/shared/database"
)

// --- pgx fakes ---------------------------------------------------------------

type ssRowVals struct{ vals []any }

func (r *ssRowVals) Scan(dest ...any) error { return ssScan(r.vals, dest) }
func (r *ssRowVals) Err() error             { return nil }

type ssErrRow struct{ err error }

func (e *ssErrRow) Scan(...any) error { return e.err }
func (e *ssErrRow) Err() error        { return e.err }

func ssScan(vals []any, dest []any) error {
	for i, d := range dest {
		if i >= len(vals) {
			return fmt.Errorf("ssRow: scan target %d of %d missing", i, len(dest))
		}
		switch p := d.(type) {
		case *uuid.UUID:
			*p = vals[i].(uuid.UUID)
		case *string:
			*p = vals[i].(string)
		case *bool:
			*p = vals[i].(bool)
		case *time.Time:
			*p = vals[i].(time.Time)
		case *pgtype.Timestamptz:
			v, _ := vals[i].(*time.Time)
			if v == nil {
				p.Valid = false
			} else {
				p.Valid = true
				p.Time = *v
			}
		case *pgtype.UUID:
			p.Valid = false
		default:
			return fmt.Errorf("ssRow: unsupported scan target %T", d)
		}
	}
	return nil
}

type ssConn struct {
	queryRowFn func(sql string, args ...any) pgx.Row
	execFn     func(sql string, args ...any) (pgconn.CommandTag, error)
}

func (c *ssConn) QueryRow(_ context.Context, sql string, args ...any) pgx.Row {
	if c.queryRowFn != nil {
		return c.queryRowFn(sql, args...)
	}
	return &ssErrRow{err: fmt.Errorf("ssConn: unexpected QueryRow %q", sql)}
}
func (c *ssConn) Query(_ context.Context, sql string, args ...any) (pgx.Rows, error) {
	return nil, fmt.Errorf("ssConn: unexpected Query %q", sql)
}
func (c *ssConn) Exec(_ context.Context, sql string, args ...any) (pgconn.CommandTag, error) {
	if c.execFn != nil {
		return c.execFn(sql, args...)
	}
	return pgconn.NewCommandTag("UPDATE 1"), nil
}

func ssStore(queryRow func(sql string, args ...any) pgx.Row, exec func(sql string, args ...any) (pgconn.CommandTag, error)) *SessionStore {
	fc := &ssConn{queryRowFn: queryRow, execFn: exec}
	return NewSessionStore(database.NewPostgresWithDriver(fc), SessionStoreConfig{
		IdleTTL:     30 * 24 * time.Hour,
		AbsoluteTTL: 7 * 24 * time.Hour,
	})
}

func ssHas(sql, sub string) bool {
	return strings.Contains(strings.ToLower(sql), strings.ToLower(sub))
}

// --- tests -------------------------------------------------------------------

func TestHashRefreshToken_StableSHA256(t *testing.T) {
	h1 := HashRefreshToken("secret-token")
	h2 := HashRefreshToken("secret-token")
	if h1 != h2 || len(h1) != 64 {
		t.Fatalf("hash unstable or wrong length: %q", h1)
	}
	if h1 == HashRefreshToken("other-token") {
		t.Fatal("different tokens collided")
	}
}

func TestCreateSession_InsertsHashedRow(t *testing.T) {
	var gotSQL string
	var gotArgs []any
	id := uuid.New()
	s := ssStore(func(sql string, args ...any) pgx.Row {
		gotSQL, gotArgs = sql, args
		return &ssRowVals{vals: []any{id}}
	}, nil)

	out, err := s.CreateSession(context.Background(), uuid.New(), uuid.New(), uuid.Nil,
		"refresh-me", "Pixel 9", "android", time.Now().Add(time.Hour))
	if err != nil {
		t.Fatalf("CreateSession: %v", err)
	}
	if out != id {
		t.Fatalf("returned id %v want %v", out, id)
	}
	if !ssHas(gotSQL, "INSERT INTO auth_device_sessions") {
		t.Fatalf("unexpected SQL: %s", gotSQL)
	}
	// args[2] is the stored hash — must never be the raw token.
	if gotArgs[2].(string) != HashRefreshToken("refresh-me") {
		t.Fatal("expected hashed refresh token to be stored")
	}
	if strings.Contains(gotSQL, "refresh-me") {
		t.Fatal("raw token leaked into SQL")
	}
}

func TestConsumeRefresh_ActiveRotatesParent(t *testing.T) {
	userID, famID, sessID := uuid.New(), uuid.New(), uuid.New()
	now := time.Now()
	var execSQL string
	s := ssStore(func(sql string, args ...any) pgx.Row {
		if !ssHas(sql, "FROM auth_device_sessions") {
			return &ssErrRow{err: fmt.Errorf("unexpected query %q", sql)}
		}
		want := HashRefreshToken("live-token")
		if args[0].(string) != want {
			t.Fatalf("lookup by hash mismatch")
		}
		return &ssRowVals{vals: []any{sessID, userID, famID, (*time.Time)(nil), (*time.Time)(nil), now, now.Add(24 * time.Hour)}}
	}, func(sql string, args ...any) (pgconn.CommandTag, error) {
		execSQL = sql
		return pgconn.NewCommandTag("UPDATE 1"), nil
	})

	res, err := s.ConsumeRefresh(context.Background(), "live-token")
	if err != nil {
		t.Fatalf("ConsumeRefresh: %v", err)
	}
	if res == nil || res.Reuse {
		t.Fatalf("expected active consume, got %+v", res)
	}
	if res.SessionID != sessID || res.FamilyID != famID || res.RotateFrom != sessID {
		t.Fatalf("wrong lineage: %+v", res)
	}
	if !ssHas(execSQL, "revoke_reason = 'rotated'") {
		t.Fatalf("parent row was not marked rotated: %s", execSQL)
	}
}

func TestConsumeRefresh_UnknownHashAdopts(t *testing.T) {
	s := ssStore(func(sql string, args ...any) pgx.Row {
		return &ssErrRow{err: pgx.ErrNoRows}
	}, nil)
	res, err := s.ConsumeRefresh(context.Background(), "legacy-token")
	if err != nil || res != nil {
		t.Fatalf("unknown hash should adopt silently, got (%+v, %v)", res, err)
	}
}

func TestConsumeRefresh_RevokedRowIsReuse(t *testing.T) {
	revoked := time.Now().Add(-time.Minute)
	userID, famID := uuid.New(), uuid.New()
	s := ssStore(func(sql string, args ...any) pgx.Row {
		return &ssRowVals{vals: []any{uuid.New(), userID, famID, (*time.Time)(nil), &revoked, time.Now(), time.Now().Add(24 * time.Hour)}}
	}, nil)
	res, err := s.ConsumeRefresh(context.Background(), "stolen-token")
	if err != nil {
		t.Fatalf("ConsumeRefresh: %v", err)
	}
	if res == nil || !res.Reuse {
		t.Fatalf("revoked row must flag reuse, got %+v", res)
	}
}

func TestConsumeRefresh_ExpiredRowIsReuse(t *testing.T) {
	userID, famID := uuid.New(), uuid.New()
	s := ssStore(func(sql string, args ...any) pgx.Row {
		return &ssRowVals{vals: []any{uuid.New(), userID, famID, (*time.Time)(nil), (*time.Time)(nil), time.Now(), time.Now().Add(-time.Second)}}
	}, nil)
	res, err := s.ConsumeRefresh(context.Background(), "expired-token")
	if err != nil {
		t.Fatalf("ConsumeRefresh: %v", err)
	}
	if res == nil || !res.Reuse {
		t.Fatalf("expired row must flag reuse, got %+v", res)
	}
}

func TestConsumeRefresh_IdleStaleIsReuse(t *testing.T) {
	userID, famID := uuid.New(), uuid.New()
	stale := time.Now().Add(-40 * 24 * time.Hour) // beyond 30-day idle TTL
	s := ssStore(func(sql string, args ...any) pgx.Row {
		return &ssRowVals{vals: []any{uuid.New(), userID, famID, (*time.Time)(nil), (*time.Time)(nil), stale, time.Now().Add(24 * time.Hour)}}
	}, nil)
	res, err := s.ConsumeRefresh(context.Background(), "idle-token")
	if err != nil {
		t.Fatalf("ConsumeRefresh: %v", err)
	}
	if res == nil || !res.Reuse {
		t.Fatalf("idle-stale row must flag reuse, got %+v", res)
	}
}

func TestConsumeRefresh_RotationRaceIsReuse(t *testing.T) {
	userID, famID := uuid.New(), uuid.New()
	now := time.Now()
	s := ssStore(func(sql string, args ...any) pgx.Row {
		return &ssRowVals{vals: []any{uuid.New(), userID, famID, (*time.Time)(nil), (*time.Time)(nil), now, now.Add(24 * time.Hour)}}
	}, func(sql string, args ...any) (pgconn.CommandTag, error) {
		return pgconn.NewCommandTag("UPDATE 0"), nil // lost the race
	})
	res, err := s.ConsumeRefresh(context.Background(), "raced-token")
	if err != nil {
		t.Fatalf("ConsumeRefresh: %v", err)
	}
	if res == nil || !res.Reuse {
		t.Fatalf("lost rotation race must flag reuse, got %+v", res)
	}
}

func TestRevokeFamilyAndUser(t *testing.T) {
	var calls int
	var lastSQL string
	s := ssStore(nil, func(sql string, args ...any) (pgconn.CommandTag, error) {
		calls++
		lastSQL = sql
		return pgconn.NewCommandTag("UPDATE 3"), nil
	})
	n, err := s.RevokeFamily(context.Background(), uuid.New(), "reuse_detected")
	if err != nil || n != 3 || !ssHas(lastSQL, "family_id = $1") {
		t.Fatalf("RevokeFamily: n=%d err=%v sql=%s", n, err, lastSQL)
	}
	n, err = s.RevokeAllForUser(context.Background(), uuid.New(), "logout_everywhere")
	if err != nil || n != 3 || !ssHas(lastSQL, "user_id = $1") {
		t.Fatalf("RevokeAllForUser: n=%d err=%v sql=%s", n, err, lastSQL)
	}
}

func TestRevokeByID_OwnershipAndIdempotency(t *testing.T) {
	s := ssStore(nil, func(sql string, args ...any) (pgconn.CommandTag, error) {
		return pgconn.NewCommandTag("UPDATE 0"), nil
	})
	err := s.RevokeByID(context.Background(), uuid.New(), uuid.New(), "user_revoked")
	if !errors.Is(err, ErrSessionNotFound) {
		t.Fatalf("missing/foreign row must map to ErrSessionNotFound, got %v", err)
	}
	s2 := ssStore(nil, func(sql string, args ...any) (pgconn.CommandTag, error) {
		return pgconn.NewCommandTag("UPDATE 1"), nil
	})
	if err := s2.RevokeByID(context.Background(), uuid.New(), uuid.New(), "user_revoked"); err != nil {
		t.Fatalf("owned revoke failed: %v", err)
	}
}

func TestNilStoreDisablesPersistence(t *testing.T) {
	var s *SessionStore
	if _, err := s.CreateSession(context.Background(), uuid.New(), uuid.New(), uuid.Nil, "t", "", "", time.Now()); err != nil {
		t.Fatalf("nil store CreateSession: %v", err)
	}
	res, err := s.ConsumeRefresh(context.Background(), "t")
	if res != nil || err != nil {
		t.Fatalf("nil store ConsumeRefresh: (%v, %v)", res, err)
	}
	if s.AbsoluteTTL() != 0 {
		t.Fatal("nil store must report zero TTL")
	}
}
