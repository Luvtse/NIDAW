package tmpprobe

import (
"context"
"errors"
"math/big"
"crypto/rand"
"fmt"
"testing"
"time"

"github.com/alicebob/miniredis/v2"
"github.com/redis/go-redis/v9"
)

var errCooldownActive = errors.New("otp cooldown gate held")

func startCooldown(ctx context.Context, rdb *redis.Client, key string, cooldown time.Duration) error {
if cooldown <= 0 {
return nil
}
const script = `if tonumber(ARGV[2]) <= 0 then return 'OK' end return redis.call('SET', KEYS[1], ARGV[1], 'NX', 'PX', ARGV[2])`
res, err := rdb.Eval(ctx, script, []string{key + ":cooldown"},
time.Now().UTC().Format(time.RFC3339Nano),
cooldown.Milliseconds()).Text()
if errors.Is(err, redis.Nil) || (err == nil && res == "") {
return errCooldownActive
}
if err != nil {
return err
}
return nil
}

func TestProbe(t *testing.T) {
mr, _ := miniredis.Run()
defer mr.Close()
rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
ctx := context.Background()
testPhone := "+251911223344"
key := fmt.Sprintf("auth:otp:%s:%s:%s", "login", "rider", testPhone)
senderFail := true
request := func() error {
if err := startCooldown(ctx, rdb, key, time.Second); err != nil {
if errors.Is(err, errCooldownActive) {
t.Logf("request: cooldown held")
return errors.New("otp resend cooldown active")
}
return err
}
hourKey := key + ":hour"
const qscript = `local c = redis.call('INCR', KEYS[1]) if c == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end return c`
count, err := rdb.Eval(ctx, qscript, []string{hourKey}, int(time.Hour.Seconds())).Int64()
if err != nil { return err }
if count > 5 {
_ = rdb.Decr(ctx, hourKey).Err()
return errors.New("too many requests")
}
ipKey := fmt.Sprintf("auth:otp:ip:%s:%s", "10.0.0.5", "login")
ipCount, err := rdb.Eval(ctx, qscript, []string{ipKey}, int(time.Hour.Seconds())).Int64()
if err != nil { return err }
if ipCount > 50 {
_ = rdb.Decr(ctx, hourKey).Err(); _ = rdb.Decr(ctx, ipKey).Err()
return errors.New("too many ip")
}
max := new(big.Int).Exp(big.NewInt(10), big.NewInt(6), nil)
n, _ := rand.Int(rand.Reader, max)
code := fmt.Sprintf("%0*d", 6, n.Int64())
if err := rdb.Set(ctx, key, code, time.Minute).Err(); err != nil { return err }
_ = rdb.Del(ctx, key+":attempts").Err()
if senderFail {
_ = rdb.Del(ctx, key, key+":cooldown").Err()
_ = rdb.Decr(ctx, hourKey).Err()
_ = rdb.Decr(ctx, ipKey).Err()
return errors.New("sms delivery failed")
}
return nil
}
senderFail = true
err := request()
t.Logf("fail-request err=%v exists=%v cooldownExists=%v", err, mr.Exists(key), mr.Exists(key+":cooldown"))
senderFail = false
for i := 0; i < 5; i++ {
if err := request(); err != nil {
t.Fatalf("post-failure request %d: %v | hour=%v cooldown=%v", i, err, func() string { v, _ := mr.Get(key + ":hour"); return v }(), mr.Exists(key+":cooldown"))
}
}
t.Log("all 5 succeeded")
}
