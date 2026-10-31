package commands

import (
"context"
"fmt"
"testing"

"github.com/google/uuid"
)

func TestFZDebugScan(t *testing.T) {
w := newFzWorld()
w.wire("in_progress", 95.00, 0, 0, "wallet")
t.Logf("rules=%d", len(w.conn.rules))
for i, r := range w.conn.rules {
t.Logf("rule %d: %q present=%v", i, r.substr, r.present)
}
var dpid uuid.UUID
err := w.conn.QueryRow(context.Background(), `SELECT id FROM drivers WHERE user_id = $1`, w.driverUser).Scan(&dpid)
fmt.Println(err)
if err == nil {
t.Errorf("unexpected ok %v", dpid)
}
}
