package eventbus

import (
	"context"
	"errors"
	"testing"
)

type recordingReliableBus struct {
	EventBus
	topic   string
	groupID string
	handler func(context.Context, Event) error
}

func (b *recordingReliableBus) SubscribeReliable(_ context.Context, topic, groupID string, handler func(context.Context, Event) error) error {
	b.topic, b.groupID, b.handler = topic, groupID, handler
	return nil
}

func TestSubscribeReliableUsesNamedReliableSubscriber(t *testing.T) {
	bus := &recordingReliableBus{}
	wantErr := errors.New("retry me")
	if err := SubscribeReliable(context.Background(), bus, "events", "billing-v1", func(context.Context, Event) error { return wantErr }); err != nil {
		t.Fatalf("SubscribeReliable returned error: %v", err)
	}
	if bus.topic != "events" || bus.groupID != "billing-v1" || bus.handler == nil {
		t.Fatalf("reliable subscription not wired: topic=%q group=%q handler nil=%t", bus.topic, bus.groupID, bus.handler == nil)
	}
	if err := bus.handler(context.Background(), Event{Type: "payment.failed"}); !errors.Is(err, wantErr) {
		t.Fatalf("handler error was not preserved: got %v", err)
	}
}

func TestSubscribeReliableRejectsNilBus(t *testing.T) {
	if err := SubscribeReliable(context.Background(), nil, "events", "consumer-v1", func(context.Context, Event) error { return nil }); err == nil {
		t.Fatal("expected nil bus to be rejected")
	}
}

func TestSubscribeReliableTopicsRegistersTopicQualifiedGroups(t *testing.T) {
	bus := &recordingTopicsBus{}
	handler := func(context.Context, Event) error { return nil }
	if err := SubscribeReliableTopics(context.Background(), bus, []string{"nidus.rides", "payments"}, "notify-v1", handler); err != nil {
		t.Fatalf("SubscribeReliableTopics: %v", err)
	}
	if len(bus.subscriptions) != 2 {
		t.Fatalf("subscriptions = %d, want 2", len(bus.subscriptions))
	}
	if bus.subscriptions[0] != "nidus.rides:notify-v1-nidus.rides" || bus.subscriptions[1] != "payments:notify-v1-payments" {
		t.Fatalf("unexpected subscriptions: %v", bus.subscriptions)
	}
}

type recordingTopicsBus struct{ subscriptions []string }

func (b *recordingTopicsBus) Publish(context.Context, string, Event) error         { return nil }
func (b *recordingTopicsBus) Subscribe(context.Context, string, func(Event)) error { return nil }
func (b *recordingTopicsBus) Close() error                                         { return nil }
func (b *recordingTopicsBus) SubscribeReliable(_ context.Context, topic, group string, _ func(context.Context, Event) error) error {
	b.subscriptions = append(b.subscriptions, topic+":"+group)
	return nil
}

func TestSubscribeReliableTopicsRejectsDuplicateTopics(t *testing.T) {
	bus := &recordingTopicsBus{}
	err := SubscribeReliableTopics(context.Background(), bus, []string{"payments", "payments"}, "notify-v1", func(context.Context, Event) error { return nil })
	if err == nil {
		t.Fatal("expected duplicate topic error")
	}
	if len(bus.subscriptions) != 0 {
		t.Fatalf("partial subscriptions created before validation: %v", bus.subscriptions)
	}
}
