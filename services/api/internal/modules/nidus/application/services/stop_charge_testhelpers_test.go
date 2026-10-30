package services

// ============================================================================
// TEST-ONLY fakes: pgx.Row / pgx.Rows / pgconn.CommandTag-compatible helpers
// so stop-charge service SQL logic is unit-testable without a live Postgres.
// ============================================================================

import (
"context"
"fmt"
"strings"
"time"

"github.com/google/uuid"
"github.com/jackc/pgx/v5"
"github.com/jackc/pgx/v5/pgconn"

"nidaw-backend/internal/shared/database"
)

// --- command tag -------------------------------------------------------------

func mkTag(rows int64) pgconn.CommandTag {
return pgconn.NewCommandTag(fmt.Sprintf("UPDATE %d", rows))
}

// --- single-row fake ---------------------------------------------------------

type fakeRowVals struct{ vals []any }

func (r *fakeRowVals) Scan(dest ...any) error { return scanVals(r.vals, dest) }
func (r *fakeRowVals) Err() error             { return nil }

type errRowScan struct{ err error }

func (e *errRowScan) Scan(...any) error { return e.err }
func (e *errRowScan) Err() error        { return e.err }

func noRow() pgx.Row { return &errRowScan{err: pgx.ErrNoRows} }

func scanVals(vals []any, dest []any) error {
for i, d := range dest {
if i >= len(vals) {
return fmt.Errorf("fakeRow: scan target %d of %d missing", i, len(dest))
}
switch p := d.(type) {
case *int64:
v, ok := vals[i].(int64)
if !ok {
return fmt.Errorf("fakeRow: want int64 at %d, got %T", i, vals[i])
}
*p = v
case *int:
*p = vals[i].(int)
case *bool:
v, ok := vals[i].(bool)
if !ok {
return fmt.Errorf("fakeRow: want bool at %d, got %T (fake does not scan NULL into plain bool)", i, vals[i])
}
*p = v
case *string:
*p = vals[i].(string)
case **time.Time:
v, _ := vals[i].(*time.Time)
*p = v
case *time.Time:
switch v := vals[i].(type) {
case time.Time:
*p = v
case *time.Time:
if v == nil {
return fmt.Errorf("fakeRow: NULL scanned into non-nullable *time.Time")
}
*p = *v
default:
return fmt.Errorf("fakeRow: unsupported time value %T", vals[i])
}
case *uuid.UUID:
*p = vals[i].(uuid.UUID)
default:
return fmt.Errorf("fakeRow: unsupported scan target %T", d)
}
}
return nil
}

// --- multi-row fake ----------------------------------------------------------

type fakeRows struct {
cols []string
rows [][]any
idx  int
err  error
open bool
}

func newFakeRows(cols []string, rows [][]any) *fakeRows {
return &fakeRows{cols: cols, rows: rows, idx: -1, open: true}
}

func (r *fakeRows) Scan(dest ...any) error {
if r.idx < 0 || r.idx >= len(r.rows) {
return fmt.Errorf("fakeRows: no current row")
}
return scanVals(r.rows[r.idx], dest)
}
func (r *fakeRows) Next() bool                       { r.idx++; return r.open && r.idx < len(r.rows) }
func (r *fakeRows) Err() error                        { return r.err }
func (r *fakeRows) Close()                             { r.open = false }
func (r *fakeRows) Columns() []string                  { return r.cols }
func (r *fakeRows) CommandTag() pgconn.CommandTag      { return pgconn.CommandTag{} }
func (r *fakeRows) FieldDescriptions() []pgconn.FieldDescription { return nil }
func (r *fakeRows) Values() ([]any, error)             { return nil, nil }
func (r *fakeRows) RawValues() [][]byte                { return nil }
func (r *fakeRows) Conn() *pgx.Conn                    { return nil }

// --- connection fake ----------------------------------------------------------

type fakeConn struct {
queryRowFn func(sql string, args ...any) pgx.Row
queryFn    func(sql string, args ...any) (pgx.Rows, error)
execFn     func(sql string, args ...any) (pgconn.CommandTag, error)
}

func (c *fakeConn) QueryRow(_ context.Context, sql string, args ...any) pgx.Row {
if c.queryRowFn != nil {
return c.queryRowFn(sql, args...)
}
return &errRowScan{err: fmt.Errorf("fakeConn: unexpected QueryRow %q", sql)}
}
func (c *fakeConn) Query(_ context.Context, sql string, args ...any) (pgx.Rows, error) {
if c.queryFn != nil {
return c.queryFn(sql, args...)
}
return nil, fmt.Errorf("fakeConn: unexpected Query %q", sql)
}
func (c *fakeConn) Exec(_ context.Context, sql string, args ...any) (pgconn.CommandTag, error) {
if c.execFn != nil {
return c.execFn(sql, args...)
}
return pgconn.CommandTag{}, nil
}

func newSvc(qr func(string, ...any) pgx.Row, ex func(string, ...any) (pgconn.CommandTag, error)) *StopChargeService {
return newSvcFull(qr, ex, nil)
}
func newSvcFull(qr func(string, ...any) pgx.Row, ex func(string, ...any) (pgconn.CommandTag, error), q func(string, ...any) (pgx.Rows, error)) *StopChargeService {
fc := &fakeConn{queryRowFn: qr, execFn: ex, queryFn: q}
return &StopChargeService{db: database.NewPostgresWithDriver(fc)}
}

func has(sql, sub string) bool { return strings.Contains(strings.ToLower(sql), strings.ToLower(sub)) }

func ptrTime(t time.Time) *time.Time { return &t }
