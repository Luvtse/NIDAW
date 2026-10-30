package eventbus

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"sync/atomic"
	"time"

	"github.com/segmentio/kafka-go"
)

type Event struct {
	ID            string                 `json:"event_id,omitempty"`
	SchemaVersion int                    `json:"schema_version,omitempty"`
	Type          string                 `json:"type"`
	Payload       map[string]interface{} `json:"payload"`
	Timestamp     int64                  `json:"timestamp"`
	TraceID       string                 `json:"trace_id,omitempty"`
}

type EventBus interface {
	Publish(ctx context.Context, topic string, event Event) error
	Subscribe(ctx context.Context, topic string, handler func(Event)) error
	Close() error
}

type KafkaBus struct {
	writer          *kafka.Writer
	brokers         []string
	subscriptionSeq atomic.Uint64
}

func NewKafkaBus(brokers []string) *KafkaBus {
	// Keep Writer.Topic unset so each Publish call can select its own topic.
	// A fixed writer topic silently routes module-specific outbox records to
	// the same topic, defeating the EventBus.Publish contract.
	writer := &kafka.Writer{
		Addr:     kafka.TCP(brokers...),
		Balancer: &kafka.LeastBytes{},
	}

	return &KafkaBus{writer: writer, brokers: append([]string(nil), brokers...)}
}

func (b *KafkaBus) Publish(ctx context.Context, topic string, event Event) error {
	msg, err := json.Marshal(event)
	if err != nil {
		return err
	}

	if topic == "" {
		return errors.New("event bus topic is required")
	}
	return b.writer.WriteMessages(ctx, kafka.Message{
		Topic: topic,
		Key:   []byte(event.Type),
		Value: msg,
	})
}

// ReliableSubscriber exposes error-aware consumption for durable handlers. Each
// subscriber must use a stable, product-specific group ID so independent
// consumers receive their own copy instead of competing in one consumer group.
type ReliableSubscriber interface {
	SubscribeReliable(ctx context.Context, topic, groupID string, handler func(context.Context, Event) error) error
}

// Subscribe preserves the legacy best-effort callback contract used by live
// WebSocket fan-out. It uses configured brokers and a distinct group per
// subscription so independent in-process subscribers do not steal each other's
// messages. Durable consumers should use SubscribeReliable instead.
func (b *KafkaBus) Subscribe(ctx context.Context, topic string, handler func(Event)) error {
	if topic == "" || handler == nil {
		return errors.New("topic and event handler are required")
	}
	if len(b.brokers) == 0 {
		return errors.New("at least one Kafka broker is required")
	}
	groupID := fmt.Sprintf("nidaw-best-effort-%d", b.subscriptionSeq.Add(1))
	reader := kafka.NewReader(kafka.ReaderConfig{Brokers: b.brokers, Topic: topic, GroupID: groupID})
	go func() {
		defer reader.Close()
		for {
			msg, err := reader.FetchMessage(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				log.Printf("event bus: fetch failed: %v", err)
				if waitForRetry(ctx, time.Second) != nil {
					return
				}
				continue
			}
			var event Event
			if err := json.Unmarshal(msg.Value, &event); err != nil || event.Type == "" {
				log.Printf("event bus: malformed event committed to avoid poison loop (topic=%s): %v", topic, err)
			} else {
				handler(event)
			}
			if err := reader.CommitMessages(ctx, msg); err != nil {
				log.Printf("event bus: best-effort commit failed (topic=%s): %v", topic, err)
				if waitForRetry(ctx, time.Second) != nil {
					return
				}
				// The legacy callback has no error result; successful callback return
				// is the only acknowledgement available on this compatibility path.
				for err := reader.CommitMessages(ctx, msg); err != nil; err = reader.CommitMessages(ctx, msg) {
					log.Printf("event bus: retrying best-effort commit (topic=%s): %v", topic, err)
					if waitForRetry(ctx, time.Second) != nil {
						return
					}
				}
			}
		}
	}()
	return nil
}

// SubscribeReliable commits only after an error-aware handler succeeds. A
// failed message is retained and retried with a one-second delay until success or
// context cancellation; this deliberately provides at-least-once delivery.
func (b *KafkaBus) SubscribeReliable(ctx context.Context, topic, groupID string, handler func(context.Context, Event) error) error {
	if topic == "" || groupID == "" || handler == nil {
		return errors.New("topic, stable consumer group ID, and event handler are required")
	}
	if len(b.brokers) == 0 {
		return errors.New("at least one Kafka broker is required")
	}
	reader := kafka.NewReader(kafka.ReaderConfig{Brokers: b.brokers, Topic: topic, GroupID: groupID, MinBytes: 1, MaxBytes: 10e6, MaxWait: time.Second})
	go func() {
		defer reader.Close()
		var pending *kafka.Message
		var pendingEvent *Event
		var poison, processed bool
		for ctx.Err() == nil {
			if pending == nil {
				msg, err := reader.FetchMessage(ctx)
				if err != nil {
					if ctx.Err() != nil {
						return
					}
					log.Printf("event bus: reliable fetch failed (group=%s): %v", groupID, err)
					if waitForRetry(ctx, time.Second) != nil {
						return
					}
					continue
				}
				pending = &msg
				pendingEvent, poison, processed = nil, false, false
			}
			if pendingEvent == nil && !poison {
				var event Event
				if err := json.Unmarshal(pending.Value, &event); err != nil || event.Type == "" {
					log.Printf("event bus: malformed event skipped and committed by poison-message policy (group=%s): %v", groupID, err)
					poison = true
				} else {
					pendingEvent = &event
				}
			}
			if poison {
				if err := reader.CommitMessages(ctx, *pending); err != nil {
					log.Printf("event bus: poison-message commit failed (group=%s): %v", groupID, err)
					if waitForRetry(ctx, time.Second) != nil {
						return
					}
					continue
				}
				pending, pendingEvent, poison, processed = nil, nil, false, false
				continue
			}
			if !processed {
				if err := handler(ctx, *pendingEvent); err != nil {
					log.Printf("event bus: reliable handler failed; retaining event (group=%s, type=%s): %v", groupID, pendingEvent.Type, err)
					if waitForRetry(ctx, time.Second) != nil {
						return
					}
					continue
				}
				processed = true
			}
			if err := reader.CommitMessages(ctx, *pending); err != nil {
				log.Printf("event bus: reliable commit failed; retrying commit (group=%s, type=%s): %v", groupID, pendingEvent.Type, err)
				if waitForRetry(ctx, time.Second) != nil {
					return
				}
				continue
			}
			pending, pendingEvent, poison, processed = nil, nil, false, false
		}
	}()
	return nil
}

func (b *KafkaBus) Close() error {
	return b.writer.Close()
}
