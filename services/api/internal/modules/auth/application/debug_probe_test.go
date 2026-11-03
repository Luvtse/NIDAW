package application

import (
"testing"
"time"
)

func TestDebugProbe(t *testing.T) {
got, ok := NormalizePhone("+2510911223344")
t.Logf("PROBE NormalizePhone = %q %v", got, ok)
cc, okcc := legacyCountryCodeLen("2510911223344")
t.Logf("PROBE legacyCountryCodeLen = %d %v", cc, okcc)
svc, _, _ := newTestService(t)
t.Logf("PROBE cfg.ResendCooldown = %v", svc.cfg.ResendCooldown)
}

var _ = time.Now
