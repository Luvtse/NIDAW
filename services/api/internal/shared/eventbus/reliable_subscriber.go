package eventbus

import (
	"context"
	"errors"
	"log"
)

// SubscribeReliable selects the error-aware Kafka implementation when
// available. Test and in-memory buses may implement only EventBus; for those
// compatibility adapters, errors are logged because their callback contract
// cannot express acknowledgement or redelivery.
func SubscribeReliable(ctx context.Context, bus EventBus, topic, groupID string, handler func(context.Context, Event) error) error {
	if bus == nil {
		return errors.New("event bus is required")
	}
	if reliable, ok := bus.(ReliableSubscriber); ok {
		return reliable.SubscribeReliable(ctx, topic, groupID, handler)
	}
	return bus.Subscribe(ctx, topic, func(event Event) {
		if err := handler(ctx, event); err != nil {
			log.Printf("eventbus compatibility subscriber cannot retry handler failure (group=%s, type=%s): %v", groupID, event.Type, err)
		}
	})
}

// SubscribeReliableTopics registers one independent subscription per topic.
// Each topic gets a stable topic-qualified group ID so consumers receive events
// from every declared producer topic without competing with each other.
func SubscribeReliableTopics(ctx context.Context, bus EventBus, topics []string, groupID string, handler func(context.Context, Event) error) error {
	if bus == nil {
		return errors.New("event bus is required")
	}
	if len(topics) == 0 || groupID == "" || handler == nil {
		return errors.New("topics, group ID, and event handler are required")
	}
	seen := make(map[string]struct{}, len(topics))
	for _, topic := range topics {
		if topic == "" {
			return errors.New("event topic cannot be empty")
		}
		if _, exists := seen[topic]; exists {
			return errors.New("event topics must be unique")
		}
		seen[topic] = struct{}{}
	}
	for _, topic := range topics {
		if err := SubscribeReliable(ctx, bus, topic, groupID+"-"+topic, handler); err != nil {
			return err
		}
	}
	return nil
}

// SubscribeTopics registers a best-effort callback on each topic. Use this only
// for ephemeral fan-out such as WebSocket updates; durable side effects should
// use SubscribeReliableTopics.
func SubscribeTopics(ctx context.Context, bus EventBus, topics []string, handler func(Event)) error {
	if bus == nil {
		return errors.New("event bus is required")
	}
	if len(topics) == 0 || handler == nil {
		return errors.New("topics and event handler are required")
	}
	seen := make(map[string]struct{}, len(topics))
	for _, topic := range topics {
		if topic == "" {
			return errors.New("event topic cannot be empty")
		}
		if _, exists := seen[topic]; exists {
			return errors.New("event topics must be unique")
		}
		seen[topic] = struct{}{}
	}
	for _, topic := range topics {
		if err := bus.Subscribe(ctx, topic, handler); err != nil {
			return err
		}
	}
	return nil
}
