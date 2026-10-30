package eventbus

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

type fakeConsumerReader struct {
	mu        sync.Mutex
	message   kafka.Message
	fetchErr  error
	commitErr error
	fetches   int
	commits   int
	closed    bool
}

func (r *fakeConsumerReader) FetchMessage(context.Context) (kafka.Message, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.fetches++
	return r.message, r.fetchErr
}

func (r *fakeConsumerReader) CommitMessages(context.Context, ...kafka.Message) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.commits++
	return r.commitErr
}

func (r *fakeConsumerReader) Close() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.closed = true
	return nil
}

func newTestConsumer(reader *fakeConsumerReader) *Consumer {
	return &Consumer{
		config:   &ConsumerConfig{RetryAttempts: 0},
		reader:   reader,
		handlers: map[string]MessageHandler{},
		logger:   zap.NewNop(),
	}
}

func TestConsumeMessageCommitsAfterSuccessfulHandler(t *testing.T) {
	reader := &fakeConsumerReader{message: kafka.Message{Topic: "orders", Value: []byte(`{"type":"order.created","payload":{},"timestamp":1}`)}}
	consumer := newTestConsumer(reader)
	consumer.RegisterHandler("order.created", func(context.Context, Event) error { return nil })

	if err := consumer.consumeMessage(context.Background()); err != nil {
		t.Fatalf("consumeMessage returned error: %v", err)
	}
	if reader.commits != 1 {
		t.Fatalf("expected one commit after success, got %d", reader.commits)
	}
}

func TestConsumeMessageDoesNotCommitFailedHandler(t *testing.T) {
	reader := &fakeConsumerReader{message: kafka.Message{Topic: "orders", Value: []byte(`{"type":"order.created","payload":{},"timestamp":1}`)}}
	consumer := newTestConsumer(reader)
	consumer.RegisterHandler("order.created", func(context.Context, Event) error { return errors.New("temporary downstream failure") })

	if err := consumer.consumeMessage(context.Background()); err == nil {
		t.Fatal("expected handler failure")
	}
	if reader.commits != 0 {
		t.Fatalf("failed event must remain uncommitted, got %d commits", reader.commits)
	}
}

func TestConsumeMessageCommitsMalformedPoisonMessage(t *testing.T) {
	reader := &fakeConsumerReader{message: kafka.Message{Topic: "orders", Value: []byte(`not-json`)}}
	consumer := newTestConsumer(reader)

	if err := consumer.consumeMessage(context.Background()); err != nil {
		t.Fatalf("consumeMessage returned error: %v", err)
	}
	if reader.commits != 1 {
		t.Fatalf("expected malformed poison message to be committed once, got %d", reader.commits)
	}
}

func TestConsumeMessageDoesNotCommitWhenCommitFails(t *testing.T) {
	reader := &fakeConsumerReader{
		message:   kafka.Message{Topic: "orders", Value: []byte(`{"type":"order.created","payload":{},"timestamp":1}`)},
		commitErr: errors.New("broker unavailable"),
	}
	consumer := newTestConsumer(reader)
	consumer.RegisterHandler("order.created", func(context.Context, Event) error { return nil })

	if err := consumer.consumeMessage(context.Background()); err == nil {
		t.Fatal("expected commit failure")
	}
	if reader.commits != 1 {
		t.Fatalf("expected one failed commit attempt, got %d", reader.commits)
	}
}

func TestConsumeMessageRetainsFailedMessageBeforeFetchingNext(t *testing.T) {
	reader := &fakeConsumerReader{message: kafka.Message{Topic: "orders", Value: []byte(`{"type":"order.created","payload":{},"timestamp":1}`)}}
	consumer := newTestConsumer(reader)
	consumer.RegisterHandler("order.created", func(context.Context, Event) error { return errors.New("temporary failure") })
	if err := consumer.consumeMessage(context.Background()); err == nil {
		t.Fatal("expected first processing attempt to fail")
	}
	consumer.RegisterHandler("order.created", func(context.Context, Event) error { return nil })
	if err := consumer.consumeMessage(context.Background()); err != nil {
		t.Fatalf("expected pending message retry to succeed: %v", err)
	}
	if reader.fetches != 1 {
		t.Fatalf("expected same fetched message to be retried, got %d fetches", reader.fetches)
	}
	if reader.commits != 1 {
		t.Fatalf("expected exactly one successful commit, got %d", reader.commits)
	}
}

func TestConsumeMessageRetriesCommitWithoutRepeatingHandler(t *testing.T) {
	reader := &fakeConsumerReader{
		message:   kafka.Message{Topic: "orders", Value: []byte(`{"type":"order.created","payload":{},"timestamp":1}`)},
		commitErr: errors.New("broker unavailable"),
	}
	consumer := newTestConsumer(reader)
	handlerCalls := 0
	consumer.RegisterHandler("order.created", func(context.Context, Event) error { handlerCalls++; return nil })
	if err := consumer.consumeMessage(context.Background()); err == nil {
		t.Fatal("expected first commit to fail")
	}
	reader.commitErr = nil
	if err := consumer.consumeMessage(context.Background()); err != nil {
		t.Fatalf("expected commit retry to succeed: %v", err)
	}
	if handlerCalls != 1 {
		t.Fatalf("expected handler to run once while retrying commit, got %d calls", handlerCalls)
	}
	if reader.fetches != 1 || reader.commits != 2 {
		t.Fatalf("expected one fetch and two commit attempts, got fetches=%d commits=%d", reader.fetches, reader.commits)
	}
}

func TestNewConsumerRejectsMissingTopic(t *testing.T) {
	_, err := NewConsumer(&ConsumerConfig{Brokers: []string{"localhost:9092"}, GroupID: "test-group"}, zap.NewNop())
	if err == nil {
		t.Fatal("expected missing topic to be rejected")
	}
}
