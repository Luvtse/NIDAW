package application

import (
"context"
"errors"
"testing"
"time"

"github.com/redis/go-redis/v9"
)

func TestProbeNormalizeDirect(t *testing.T) {
got, ok := NormalizePhone("+2510911223344")
t.Logf("PROBE-NP got=%q ok=%v", got, ok)
}

func TestProbeEvalStatus(t *testing.T) {
svc, _, _ := newTestService(t)
ctx := context.Background()
script := `if tonumber(ARGV[2]) <= 0 then return 'OK' end return redis.call('SET', KEYS[1], ARGV[1], 'NX', 'PX', ARGV[2])`
cmd := svc.rdb.Eval(ctx, script, []string{"probe:key"}, "v", int64(time.Second.Milliseconds()))
res, err := cmd.Result()
t.Logf("PROBE-EVAL first res=%#v err=%v cmdErr=%v", res, err, cmd.Err())
cmd2 := svc.rdb.Eval(ctx, script, []string{"probe:key"}, "v", int64(time.Second.Milliseconds()))
res2, err2 := cmd2.Result()
t.Logf("PROBE-EVAL second res=%#v err=%v cmdErr=%v isNil=%v", res2, err2, cmd2.Err(), errors.Is(err2, redis.Nil))
}
