package eventbus

import (
	"context"
	"errors"
	"sync"
)

// MemoryBus is an in-process EventBus implementation used by integration
// tests and single-node development. It preserves topic routing semantics: a
// publication is delivered only to handlers subscribed to that topic. Delivery
// is synchronous so tests can assert on side effects without sleeping.
type memoryHandler struct {
	topic  string
	handle func(Event)
}

type MemoryBus struct {
	mu       sync.RWMutex
	handlers []memoryHandler
}

// NewMemoryBus returns an empty bus with no subscriptions.
func NewMemoryBus() *MemoryBus {
	return &MemoryBus{}
}

// Publish delivers the event to every registered handler, skipping handlers
// whose context has already been cancelled (the same lifecycle rule KafkaBus
// applies when its reader loop exits on ctx cancellation).
func (b *MemoryBus) Publish(_ context.Context, topic string, event Event) error {
	if topic == "" {
		return errors.New("event topic is required")
	}
	b.mu.RLock()
	defer b.mu.RUnlock()
	for _, h := range b.handlers {
		if h.topic == topic {
			h.handle(event)
		}
	}
	return nil
}

// Subscribe registers a handler. The handler stops being invoked once ctx is
// cancelled; the entry itself stays until Close for simplicity (test-only type).
func (b *MemoryBus) Subscribe(ctx context.Context, topic string, handler func(Event)) error {
	if topic == "" || handler == nil {
		return errors.New("topic and handler are required")
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	b.handlers = append(b.handlers, memoryHandler{topic: topic, handle: func(ev Event) {
		select {
		case <-ctx.Done():
			return
		default:
			handler(ev)
		}
	}})
	return nil
}

// Close satisfies the EventBus interface. It drops all handlers.
func (b *MemoryBus) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.handlers = nil
	return nil
}

var _ EventBus = (*MemoryBus)(nil)
