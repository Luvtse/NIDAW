package eventbus

import (
	"context"
	"testing"
)

func TestMemoryBusRoutesOnlyMatchingTopic(t *testing.T) {
	bus := NewMemoryBus()
	defer bus.Close()
	ctx := context.Background()
	var got []string
	if err := bus.Subscribe(ctx, "nidus.rides", func(ev Event) { got = append(got, ev.Type) }); err != nil {
		t.Fatal(err)
	}
	if err := bus.Subscribe(ctx, "payments", func(ev Event) { got = append(got, ev.Type) }); err != nil {
		t.Fatal(err)
	}
	if err := bus.Publish(ctx, "payments", Event{Type: "payment.failed"}); err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0] != "payment.failed" {
		t.Fatalf("unexpected delivery across topics: %v", got)
	}
}

func TestMemoryBusRejectsMissingTopic(t *testing.T) {
	bus := NewMemoryBus()
	defer bus.Close()
	if err := bus.Publish(context.Background(), "", Event{Type: "ride.matched"}); err == nil {
		t.Fatal("expected empty topic error")
	}
	if err := bus.Subscribe(context.Background(), "", func(Event) {}); err == nil {
		t.Fatal("expected empty subscription topic error")
	}
}
