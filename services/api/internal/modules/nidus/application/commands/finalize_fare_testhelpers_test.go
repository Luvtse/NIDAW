package commands

// ============================================================================
// TEST-ONLY fakes for the finalize path (NIDAW FARE INTEGRITY Phase 7).
//
// Shape mirrors services/stop_charge_testhelpers_test.go: a pgx.Row /
// pgx.Rows / PgConn-compatible fake keyed by SQL substring, plus a fake
// pgx.Tx with a programmable terminal UPDATE so the single-winner race guard
// and the durable outbox are exercised without a live Postgres. Per
// dispatch_test.go's documented policy, lifecycle SQL itself remains under
// the NIDUS_TEST_DATABASE_URL-guarded integration suite; these tests cover
// the finalize DECISION logic (authorization, replay, contract validation,
// §2.5 payable math, settlement payload, outbox obligation).
// ============================================================================

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"nidaw-backend/internal/modules/nidus/application/services"
	"nidaw-backend/internal/modules/nidus/domain/entities"
	"nidaw-backend/internal/shared/database"
	"nidaw-backend/internal/shared/eventbus"
)

// --- scan helper -------------------------------------------------------------

func fzScanVal(i int, dest any, v any) error {
	switch p := dest.(type) {
	case *int64:
		x, ok := v.(int64)
		if !ok {
			return fmt.Errorf("fakeRow: want int64 at %d, got %T", i, v)
		}
		*p = x
	case *int:
		switch x := v.(type) {
		case int:
			*p = x
		case int64:
			*p = int(x)
		case float64:
			*p = int(x)
		default:
			return fmt.Errorf("fakeRow: want int at %d, got %T", i, v)
		}
	case *float64:
		switch x := v.(type) {
		case float64:
			*p = x
		case nil:
			*p = 0 // SQL NULL scanned via COALESCE-free column in a test row
		default:
			return fmt.Errorf("fakeRow: want float64 at %d, got %T", i, v)
		}
	case *bool:
		x, ok := v.(bool)
		if !ok {
			return fmt.Errorf("fakeRow: want bool at %d, got %T", i, v)
		}
		*p = x
	case *string:
		x, ok := v.(string)
		if !ok {
			return fmt.Errorf("fakeRow: want string at %d, got %T", i, v)
		}
		*p = x
	case *uuid.UUID:
		x, ok := v.(uuid.UUID)
		if !ok {
			return fmt.Errorf("fakeRow: want uuid.UUID at %d, got %T", i, v)
		}
		*p = x
	case **uuid.UUID:
		x, _ := v.(*uuid.UUID)
		*p = x
	case **float64:
		switch y := v.(type) {
		case nil:
			*p = nil
		case *float64:
			*p = y
		case float64:
			z := y
			*p = &z
		default:
			return fmt.Errorf("fakeRow: unsupported *float64 value %T at %d", v, i)
		}
	case **time.Time:
		x, _ := v.(*time.Time)
		*p = x
	case *time.Time:
		switch x := v.(type) {
		case time.Time:
			*p = x
		case *time.Time:
			if x == nil {
				return fmt.Errorf("fakeRow: NULL into non-nullable *time.Time at %d", i)
			}
			*p = *x
		default:
			return fmt.Errorf("fakeRow: unsupported time value %T at %d", v, i)
		}
	case *entities.RideStatus:
		s, ok := v.(string)
		if !ok {
			return fmt.Errorf("fakeRow: want status string at %d, got %T", i, v)
		}
		*p = entities.RideStatus(s)
	case *int32:
		switch x := v.(type) {
		case int32:
			*p = x
		case int:
			*p = int32(x)
		default:
			return fmt.Errorf("fakeRow: want int32 at %d, got %T", i, v)
		}
	default:
		return fmt.Errorf("fakeRow: unsupported scan target %T at %d", dest, i)
	}
	return nil
}

func fzScan(vals []any, dest []any) error {
	for i, d := range dest {
		if i >= len(vals) {
			return fmt.Errorf("fakeRow: scan target %d of %d missing", i, len(dest))
		}
		if err := fzScanVal(i, d, vals[i]); err != nil {
			return err
		}
	}
	return nil
}

// --- rows --------------------------------------------------------------------

type fzErrRow struct{ err error }

func (r *fzErrRow) Scan(...any) error { return r.err }
func (r *fzErrRow) Err() error        { return r.err }

type fzOneRow struct{ vals []any }

func (r *fzOneRow) Scan(dest ...any) error { return fzScan(r.vals, dest) }
func (r *fzOneRow) Err() error             { return nil }

type fzRows struct {
	rows [][]any
	idx  int
	err  error
}

func (r *fzRows) Next() bool                                   { r.idx++; return r.idx < len(r.rows) }
func (r *fzRows) Scan(dest ...any) error                       { return fzScan(r.rows[r.idx], dest) }
func (r *fzRows) Err() error                                   { return r.err }
func (r *fzRows) Close()                                       {}
func (r *fzRows) Columns() []string                            { return nil }
func (r *fzRows) CommandTag() pgconn.CommandTag                { return pgconn.CommandTag{} }
func (r *fzRows) FieldDescriptions() []pgconn.FieldDescription { return nil }
func (r *fzRows) Values() ([]any, error)                       { return nil, nil }
func (r *fzRows) RawValues() [][]byte                          { return nil }
func (r *fzRows) Conn() *pgx.Conn                              { return nil }

// --- connection fake -----------------------------------------------------------

type fzConn struct {
	mu       sync.Mutex
	rules    []fzRule
	execs    []string
	execArgs [][]any
}

type fzRule struct {
	substr  string
	rowFn   func(args ...any) pgx.Row
	rowsFn  func(args ...any) (pgx.Rows, error)
	present bool
}

// add installs a rule. Re-adding the same substring REPLACES the previous
// rule: production code has exactly one query per SQL shape, so a test that
// overrides a lookup (e.g. unauthorized driver) must not leave two competing
// fake rows for the same statement.
func (c *fzConn) add(substr string, row pgx.Row) {
	c.addFn(substr, func(...any) pgx.Row { return row })
}

func (c *fzConn) addFn(substr string, fn func(args ...any) pgx.Row) {
	c.mu.Lock()
	defer c.mu.Unlock()
	r := fzRule{substr: substr, present: true, rowFn: fn}
	for i := range c.rules {
		if strings.EqualFold(c.rules[i].substr, substr) {
			c.rules[i] = r
			return
		}
	}
	c.rules = append(c.rules, r)
}

// addSeq installs a rule that returns successive rows on repeated calls
// (models the winner committing between our read and re-read). Like addFn it
// replaces any existing rule for the same substring.
func (c *fzConn) addSeq(substr string, rows ...pgx.Row) {
	c.mu.Lock()
	defer c.mu.Unlock()
	i := 0
	r := fzRule{substr: substr, present: true,
		rowFn: func(...any) pgx.Row {
			if i < len(rows)-1 {
				i++
			}
			return rows[i]
		}}
	for j := range c.rules {
		if strings.EqualFold(c.rules[j].substr, substr) {
			c.rules[j] = r
			return
		}
	}
	c.rules = append(c.rules, r)
}

func (c *fzConn) addRows(substr string, rows [][]any) {
	c.mu.Lock()
	defer c.mu.Unlock()
	r := fzRule{substr: substr, present: true,
		rowsFn: func(...any) (pgx.Rows, error) { return &fzRows{rows: rows, idx: -1}, nil }}
	for i := range c.rules {
		if strings.EqualFold(c.rules[i].substr, substr) {
			c.rules[i] = r
			return
		}
	}
	c.rules = append(c.rules, r)
}

func (c *fzConn) find(sql string) *fzRule {
	c.mu.Lock()
	defer c.mu.Unlock()
	low := strings.ToLower(sql)
	// Match the MOST SPECIFIC rule first (longest substring), not insertion
	// order: "select user_id from drivers where id" is a case-insensitive
	// substring of "select id from drivers where user_id = $1", so an
	// insertion-order scan would route the wrong query to the wrong fake row.
	best := -1
	bestLen := -1
	for i := range c.rules {
		sub := strings.ToLower(c.rules[i].substr)
		if strings.Contains(low, sub) && len(sub) > bestLen {
			best, bestLen = i, len(sub)
		}
	}
	if best >= 0 {
		return &c.rules[best]
	}
	return nil
}

func (c *fzConn) QueryRow(_ context.Context, sql string, args ...any) pgx.Row {
	if r := c.find(sql); r != nil && r.rowFn != nil {
		return r.rowFn(args...)
	}
	return &fzErrRow{err: fmt.Errorf("fzConn: unexpected QueryRow %q", sql)}
}

func (c *fzConn) Query(_ context.Context, sql string, args ...any) (pgx.Rows, error) {
	if r := c.find(sql); r != nil && r.rowsFn != nil {
		return r.rowsFn(args...)
	}
	return nil, fmt.Errorf("fzConn: unexpected Query %q", sql)
}

func (c *fzConn) Exec(_ context.Context, sql string, args ...any) (pgconn.CommandTag, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.execs = append(c.execs, sql)
	c.execArgs = append(c.execArgs, args)
	return pgconn.NewCommandTag("UPDATE 1"), nil
}

// --- transaction fake ------------------------------------------------------------

type fzTx struct {
	conn *fzConn
	// terminalRows is the RowsAffected reported by the guarded
	// `UPDATE rides SET status = 'completed' ... status = 'in_progress'`
	// statement: 1 => this finalizer won the race, 0 => it lost.
	terminalRows int64
	// failTerminal makes that UPDATE error out (rollback path).
	failTerminal bool

	commitCalls   int
	rollbackCalls int
}

func (t *fzTx) ensureTx() {}
func (t *fzTx) Begin(_ context.Context) (pgx.Tx, error) {
	return t, nil
}

func (t *fzTx) Commit(context.Context) error { t.commitCalls++; return nil }
func (t *fzTx) Rollback(context.Context) error {
	t.rollbackCalls++
	return nil
}

func (t *fzTx) CopyFrom(context.Context, pgx.Identifier, []string, pgx.CopyFromSource) (int64, error) {
	return 0, nil
}
func (t *fzTx) SendBatch(context.Context, *pgx.Batch) pgx.BatchResults { return nil }
func (t *fzTx) LargeObjects() pgx.LargeObjects                          { return pgx.LargeObjects{} }
func (t *fzTx) Prepare(context.Context, string, string) (*pgconn.StatementDescription, error) {
	return nil, nil
}
func (t *fzTx) Conn() *pgx.Conn { return nil }

func (t *fzTx) QueryRow(_ context.Context, sql string, args ...any) pgx.Row {
	if r := t.conn.find(sql); r != nil && r.rowFn != nil {
		return r.rowFn(args...)
	}
	return &fzErrRow{err: fmt.Errorf("fzTx: unexpected QueryRow %q", sql)}
}

func (t *fzTx) Query(_ context.Context, sql string, args ...any) (pgx.Rows, error) {
	if r := t.conn.find(sql); r != nil && r.rowsFn != nil {
		return r.rowsFn(args...)
	}
	return nil, fmt.Errorf("fzTx: unexpected Query %q", sql)
}

func (t *fzTx) Exec(_ context.Context, sql string, args ...any) (pgconn.CommandTag, error) {
	t.conn.mu.Lock()
	t.conn.execs = append(t.conn.execs, sql)
	t.conn.execArgs = append(t.conn.execArgs, args)
	t.conn.mu.Unlock()

	low := strings.ToLower(sql)
	if strings.Contains(low, "set status = 'completed'") {
		if t.failTerminal {
			return pgconn.CommandTag{}, errors.New("fzTx: simulated terminal update failure")
		}
		return pgconn.NewCommandTag(fmt.Sprintf("UPDATE %d", t.terminalRows)), nil
	}
	return pgconn.NewCommandTag("INSERT 1"), nil
}

// hasExec reports whether an executed statement contains the substring.
func (c *fzConn) hasExec(substr string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, s := range c.execs {
		if strings.Contains(strings.ToLower(s), strings.ToLower(substr)) {
			return true
		}
	}
	return false
}

// execArgsFor returns the args of the first Exec whose SQL contains substr.
func (c *fzConn) execArgsFor(substr string) ([]any, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for i, s := range c.execs {
		if strings.Contains(strings.ToLower(s), strings.ToLower(substr)) {
			return c.execArgs[i], true
		}
	}
	return nil, false
}

// --- recording event bus --------------------------------------------------------

type fzBus struct {
	mu      sync.Mutex
	published []eventbus.Event
	err     error // when set, Publish fails (simulated bus outage)
}

func (b *fzBus) Publish(_ context.Context, _ string, ev eventbus.Event) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.err != nil {
		return b.err
	}
	b.published = append(b.published, ev)
	return nil
}
func (b *fzBus) Subscribe(context.Context, string, func(eventbus.Event)) error { return nil }
func (b *fzBus) Close() error                                                  { return nil }

func (b *fzBus) events() []eventbus.Event {
	b.mu.Lock()
	defer b.mu.Unlock()
	out := make([]eventbus.Event, len(b.published))
	copy(out, b.published)
	return out
}

// --- world fixture -----------------------------------------------------------------

type fzWorld struct {
	conn *fzConn
	tx   *fzTx
	bus  *fzBus

	rideID, snapID, userID, driverProfile, driverUser uuid.UUID
	snap                                               *entities.FareSnapshot
	stops                                              []servicesApprovedStopView
	strayCharges                                     int64
}

type servicesApprovedStopView = struct {
	Seq              int
	FixedFeeSantim   int64
	WaitingChargeSan int64
}

func fzPtr[T any](v T) *T { return &v }

func newFzWorld() *fzWorld {
	w := &fzWorld{
		conn:          &fzConn{},
		userID:        uuid.MustParse("11111111-1111-1111-1111-111111111111"),
		driverProfile: uuid.MustParse("22222222-2222-2222-2222-222222222222"),
		driverUser:    uuid.MustParse("33333333-3333-3333-3333-333333333333"),
		rideID:        uuid.MustParse("44444444-4444-4444-4444-444444444444"),
		snapID:        uuid.MustParse("55555555-5555-5555-5555-555555555555"),
	}
	w.snap = &entities.FareSnapshot{
		ID:                  w.snapID,
		RideID:              w.rideID,
		IdempotencyKey:      "ride:" + w.rideID.String(),
		PickupLat:           9.03, PickupLng: 38.74, DropoffLat: 9.01, DropoffLng: 38.79,
		PickupAddress:       "Bole", DropoffAddress: "CMC",
		ContractDistanceKm:  10, ContractDurationMin: 30,
		Components: entities.FareComponents{
			BaseFareSantim: 3000, DistanceFareSantim: 5000, TimeFareSantim: 1500,
			SurgeAmountSantim: 0, MinimumFareSantim: 1000, GrossFareSantim: 9500,
			RideType: "standard", DistanceRatePerKm: 50, TimeRatePerMinute: 5,
			SurgeMultiplier: 1.0,
		},
		PricingConfigVersion: "vtest", DurationRuleVersion: "duration-v1", MinutesPerKm: 3.0,
		Currency:            entities.CurrencyETB,
		QuotedTotalSantim:   9500,
		FrozenAt:            time.Unix(1700000000, 0).UTC(),
	}
	w.tx = &fzTx{conn: w.conn, terminalRows: 1}
	w.bus = &fzBus{}
	return w
}

// rideVals builds the 34-column loadRide scan row in exact production order:
// id, user_id, driver_id, p_lat, p_lng, d_lat, d_lng, p_addr, d_addr,
// ride_type, status, fare_amount, currency, tip_amount, cancel_fee,
// cancelled_by, cancel_reason, distance_km, duration_minutes,
// fare_snapshot_id, payment_method_type, cash_collected_at, scheduled_at,
// promo_code, promo_discount, base/dist/time/surge/service components,
// requested_at, matched_at, started_at, completed_at, rating, created_at, updated_at.
func (w *fzWorld) rideVals(status string, fare float64, promoDiscount float64, tip float64, method string) []any {
	now := time.Unix(1700000001, 0).UTC()
	base := fzPtr(30.00)
	dist := fzPtr(50.00)
	tm := fzPtr(15.00)
	var surge *float64 // nil component => receipt shows honest unavailable state
	sfee := fzPtr(0.0)
	return []any{
		w.rideID, w.userID, &w.driverProfile,
		9.03, 38.74, 9.01, 38.79,
		"Bole", "CMC",
		"standard", status,
		fare, "ETB", tip,
		0.0, "", "",
		10.0, 30,
		&w.snapID,
		method, nil, nil,
		"", promoDiscount,
		base, dist, tm,
		surge, sfee,
		now, nil, &now, nil,
		0, now, now,
	}
}

// wire installs all query rules for the world onto its conn.
func (w *fzWorld) wire(status string, fare float64, promoDiscount, tip float64, method string) {
	w.conn.add("FROM drivers WHERE user_id", &fzOneRow{vals: []any{w.driverProfile}})
	w.conn.add("SELECT user_id FROM drivers WHERE id", &fzOneRow{vals: []any{w.driverUser}})
	w.conn.addFn("FROM rides WHERE id", func(args ...any) pgx.Row {
		return &fzOneRow{vals: w.rideVals(status, fare, promoDiscount, tip, method)}
	})
	w.wireSnapshot()
	w.wireStops()
}

// wireDriversAndRide reinstalls only the driver + ride rules (used by tests
// that deliberately clear all rules and re-add a subset).
func (w *fzWorld) wireDriversAndRide(status string) {
	w.conn.add("FROM drivers WHERE user_id", &fzOneRow{vals: []any{w.driverProfile}})
	w.conn.add("SELECT user_id FROM drivers WHERE id", &fzOneRow{vals: []any{w.driverUser}})
	w.conn.addFn("FROM rides WHERE id", func(args ...any) pgx.Row {
		return &fzOneRow{vals: w.rideVals(status, 95.00, 0, 0, "wallet")}
	})
}

func (w *fzWorld) wireSnapshot() {
	vals := []any{
		w.snap.ID, w.snap.RideID, w.snap.IdempotencyKey,
		w.snap.PickupLat, w.snap.PickupLng, w.snap.DropoffLat, w.snap.DropoffLng,
		w.snap.PickupAddress, w.snap.DropoffAddress,
		w.snap.ContractDistanceKm, w.snap.ContractDurationMin,
		w.snap.Components.BaseFareSantim, w.snap.Components.DistanceFareSantim, w.snap.Components.TimeFareSantim,
		w.snap.Components.SurgeAmountSantim, w.snap.Components.MinimumFareSantim, w.snap.Components.GrossFareSantim,
		w.snap.Components.RideType, w.snap.Components.DistanceRatePerKm, w.snap.Components.TimeRatePerMinute,
		w.snap.Components.SurgeMultiplier, w.snap.Components.SurgeReason, w.snap.MinutesPerKm,
		w.snap.PricingConfigVersion, w.snap.DurationRuleVersion,
		w.snap.Currency, w.snap.QuotedTotalSantim, w.snap.FrozenAt,
	}
	rule := &fzOneRow{vals: vals}
	w.conn.add("ride_fare_snapshots WHERE ride_id", rule)
	w.conn.add("quoted_total_santim FROM ride_fare_snapshots", &fzOneRow{vals: []any{w.snap.QuotedTotalSantim}})
}

func (w *fzWorld) wireStops() {
	if len(w.stops) > 0 {
		rows := make([][]any, 0, len(w.stops))
		for _, st := range w.stops {
			rows = append(rows, []any{st.Seq, st.FixedFeeSantim, st.WaitingChargeSan, true})
		}
		w.conn.addRows("seq, stop_fee_santim, waiting_charge_santim, approved_by_rider", rows)
		return
	}
	// No stop charges: SettlementCharges returns empty; stray-count guard reads 0.
	w.conn.addRows("seq, stop_fee_santim, waiting_charge_santim, approved_by_rider", nil)
	w.conn.add("count(*) FROM ride_stop_charges", &fzOneRow{vals: []any{w.strayCharges}})
}

// handler assembles the finalize handler over the fake world. The stop port
// is ALWAYS wired (the production graph always passes StopChargeService);
// w.nilStopCharger exercises the documented fail-closed guard for a handler
// built without it.
func (w *fzWorld) handler() *FinalizeFareHandler {
	db := database.NewPostgresWithTestTx(w.tx, w.conn)
	snaps := NewPostgresFareSnapshotRepository(db)
	return newFinalizeFareHandlerForTest(db, w.bus, snaps, fzStopCharger{w: w})
}

// handlerNoStopPort builds the handler with a nil stop charger so Execute
// falls back to its stray-approved-charge count guard.
func (w *fzWorld) handlerNoStopPort() *FinalizeFareHandler {
	db := database.NewPostgresWithTestTx(w.tx, w.conn)
	snaps := NewPostgresFareSnapshotRepository(db)
	return newFinalizeFareHandlerForTest(db, w.bus, snaps, nil)
}

type fzStopCharger struct{ w *fzWorld }

func (f fzStopCharger) SettlementCharges(ctx context.Context, rideID uuid.UUID) ([]services.ApprovedStop, error) {
	rows, err := f.w.conn.Query(ctx, `SELECT seq, stop_fee_santim, waiting_charge_santim, approved_by_rider FROM ride_stop_charges WHERE ride_id = $1 ORDER BY seq`, rideID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []services.ApprovedStop
	for rows.Next() {
		var st services.ApprovedStop
		var approved bool
		if err := rows.Scan(&st.Seq, &st.FixedFeeSantim, &st.WaitingChargeSan, &approved); err != nil {
			return nil, err
		}
		if approved {
			out = append(out, st)
		}
	}
	return out, rows.Err()
}
