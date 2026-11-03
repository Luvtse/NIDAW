package application

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

type fakeSender struct {
	sent  map[string]string
	calls int
	fail  bool
}

func newFakeSender() *fakeSender { return &fakeSender{sent: map[string]string{}} }

func (f *fakeSender) SendOTP(_ context.Context, to, code string) error {
	f.calls++
	if f.fail {
		return errors.New("provider down")
	}
	f.sent[to] = code
	return nil
}

func newTestService(t *testing.T) (*OTPService, *fakeSender, *miniredis.Miniredis) {
	t.Helper()
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	t.Cleanup(mr.Close)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	sender := newFakeSender()
	svc := NewOTPService(rdb, sender, OTPConfig{
		TTL:                time.Minute,
		ResendCooldown:     time.Second,
		MaxAttempts:        3,
		MaxRequestsPerHour: 5,
		CodeLength:         6,
		HMACSecret:         "test-secret-test-secret-test-secret",
	})
	return svc, sender, mr
}

const testPhone = "+251911223344"

func TestNormalizePhone(t *testing.T) {
	cases := []struct {
		in   string
		want string
		ok   bool
	}{
		{"+251 911 22 33 44", "+251911223344", true},
		{"+2510911223344", "+251911223344", true}, // legacy trunk artifact
		{"(091) 122-3344", "", false},             // bare national rejected: ambiguous without +CC
		{"+25191a223344", "", false},
		{"1234567", "", false}, // too short even with + stripped? len 7 < 9 bare
		{"", "", false},
		{"   ", "", false},
		{"+1234567890123456", "", false}, // >15 digits
	}
	for _, c := range cases {
		got, ok := NormalizePhone(c.in)
		if ok != c.ok || got != c.want {
			t.Errorf("NormalizePhone(%q) = (%q,%v), want (%q,%v)", c.in, got, ok, c.want, c.ok)
		}
	}
}

func TestRequestVerifyHappyPathSingleUse(t *testing.T) {
	svc, sender, _ := newTestService(t)
	ctx := context.Background()

	res, err := svc.Request(ctx, testPhone, AccountRider, OTPOpLogin, "10.0.0.1")
	if err != nil {
		t.Fatalf("Request: %v", err)
	}
	if res.TTL != time.Minute {
		t.Fatalf("TTL = %v", res.TTL)
	}
	code := sender.sent[testPhone]
	if len(code) != 6 || strings.TrimLeft(code, "0123456789") != "" {
		t.Fatalf("code not 6 digits: %q", code)
	}

	if err := svc.Verify(ctx, testPhone, code, AccountRider, OTPOpLogin); err != nil {
		t.Fatalf("Verify: %v", err)
	}
	// Replay of a consumed code must fail as if no challenge existed.
	if err := svc.Verify(ctx, testPhone, code, AccountRider, OTPOpLogin); !errors.Is(err, ErrOTPNoChallenge) {
		t.Fatalf("replay err = %v, want ErrOTPNoChallenge", err)
	}
}

func TestChallengeBoundToOperationAndAccountType(t *testing.T) {
	svc, sender, _ := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpRegister, "10.0.0.1"); err != nil {
		t.Fatalf("Request: %v", err)
	}
	code := sender.sent[testPhone]

	// Same phone/code but different operation or account type must not verify.
	if err := svc.Verify(ctx, testPhone, code, AccountRider, OTPOpLogin); !errors.Is(err, ErrOTPNoChallenge) {
		t.Fatalf("cross-operation err = %v, want ErrOTPNoChallenge", err)
	}
	if err := svc.Verify(ctx, testPhone, code, AccountDriver, OTPOpRegister); !errors.Is(err, ErrOTPNoChallenge) {
		t.Fatalf("cross-account err = %v, want ErrOTPNoChallenge", err)
	}
	if err := svc.Verify(ctx, testPhone, code, AccountRider, OTPOpRegister); err != nil {
		t.Fatalf("matching scope Verify: %v", err)
	}
}

func TestVerifyClearsCooldownForNextChallenge(t *testing.T) {
	svc, sender, _ := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpLogin, "10.0.0.9"); err != nil {
		t.Fatalf("Request: %v", err)
	}
	if err := svc.Verify(ctx, testPhone, sender.sent[testPhone], AccountRider, OTPOpLogin); err != nil {
		t.Fatalf("Verify: %v", err)
	}
	// A fresh login challenge right after consumption must not hit cooldown.
	if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpLogin, "10.0.0.9"); err != nil {
		t.Fatalf("post-verify Request: %v", err)
	}
}

func TestInvalidCodeCountsAttemptsThenBurns(t *testing.T) {
	svc, sender, _ := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Request(ctx, testPhone, AccountDriver, OTPOpLogin, "10.0.0.2"); err != nil {
		t.Fatalf("Request: %v", err)
	}
	real := sender.sent[testPhone]

	for i := 0; i < 3; i++ {
		if err := svc.Verify(ctx, testPhone, "000000", AccountDriver, OTPOpLogin); !errors.Is(err, ErrOTPInvalidCode) {
			t.Fatalf("attempt %d err = %v, want ErrOTPInvalidCode", i, err)
		}
	}
	// 4th attempt exceeds MaxAttempts=3 → burn.
	if err := svc.Verify(ctx, testPhone, real, AccountDriver, OTPOpLogin); !errors.Is(err, ErrOTPMaxAttempts) {
		t.Fatalf("burned err = %v, want ErrOTPMaxAttempts", err)
	}
	// While burned, re-request is refused.
	if _, err := svc.Request(ctx, testPhone, AccountDriver, OTPOpLogin, "10.0.0.2"); !errors.Is(err, ErrOTPMaxAttempts) {
		t.Fatalf("request-while-burned err = %v, want ErrOTPMaxAttempts", err)
	}
}

func TestResendCooldownEnforced(t *testing.T) {
	svc, _, mr := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpLogin, "10.0.0.3"); err != nil {
		t.Fatalf("Request: %v", err)
	}
	// Immediate resend is inside the ResendCooldown window.
	if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpLogin, "10.0.0.3"); !errors.Is(err, ErrOTPCooldown) {
		t.Fatalf("second Request err = %v, want ErrOTPCooldown", err)
	}
	// After the cooldown elapses (but before the challenge TTL), resend works.
	mr.FastForward(2 * time.Second)
	if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpLogin, "10.0.0.3"); err != nil {
		t.Fatalf("post-cooldown Request: %v", err)
	}
}

func TestHourlyQuotaPerIdentity(t *testing.T) {
	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("miniredis: %v", err)
	}
	defer mr.Close()
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	sender := newFakeSender()
	svc := NewOTPService(rdb, sender, OTPConfig{
		TTL:                time.Minute,
		ResendCooldown:     0, // disabled so the hourly quota is what gates
		MaxAttempts:        3,
		MaxRequestsPerHour: 5,
		CodeLength:         6,
		HMACSecret:         "test-secret-test-secret-test-secret",
	})
	ctx := context.Background()
	for i := 0; i < 5; i++ {
		if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpRecovery, "10.0.0.4"); err != nil {
			t.Fatalf("request %d: %v", i, err)
		}
	}
	if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpRecovery, "10.0.0.4"); !errors.Is(err, ErrOTPTooManyReqs) {
		t.Fatalf("over-quota err = %v, want ErrOTPTooManyReqs", err)
	}
}

func TestSMSFailureRollsBackState(t *testing.T) {
	svc, sender, mr := newTestService(t)
	ctx := context.Background()
	sender.fail = true
	if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpLogin, "10.0.0.5"); !errors.Is(err, ErrSMSDelivery) {
		t.Fatalf("err = %v, want ErrSMSDelivery", err)
	}
	// Challenge and cooldown must have been rolled back...
	if mr.Exists("auth:otp:login:rider:" + testPhone) {
		t.Fatal("challenge left dangling after SMS failure")
	}
	// ...and quota not consumed: five more successes must still be possible
	// (cooldown key was deleted too, so no FastForward needed).
	sender.fail = false
	for i := 0; i < 5; i++ {
		if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpLogin, "10.0.0.5"); err != nil {
			t.Fatalf("post-failure request %d: %v", i, err)
		}
	}
}

func TestUnavailableServiceFailsExplicitly(t *testing.T) {
	svc := NewOTPService(nil, nil, OTPConfig{})
	if svc.Available() {
		t.Fatal("nil deps must mark service unavailable")
	}
	if err := svc.Verify(context.Background(), testPhone, "123456", AccountRider, OTPOpLogin); !errors.Is(err, ErrSMSDelivery) {
		t.Fatalf("Verify err = %v, want ErrSMSDelivery", err)
	}
}

func TestCodesStoredAsDigestsNotPlaintext(t *testing.T) {
	svc, sender, mr := newTestService(t)
	ctx := context.Background()
	if _, err := svc.Request(ctx, testPhone, AccountRider, OTPOpLogin, "10.0.0.6"); err != nil {
		t.Fatalf("Request: %v", err)
	}
	stored, err := mr.Get("auth:otp:login:rider:" + testPhone)
	if err != nil {
		t.Fatalf("stored key: %v", err)
	}
	if stored == sender.sent[testPhone] {
		t.Fatal("plaintext code persisted in Redis")
	}
	if len(stored) != 64 {
		t.Fatalf("digest length = %d, want hex SHA-256 (64)", len(stored))
	}
}
