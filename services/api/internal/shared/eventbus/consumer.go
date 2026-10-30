package eventbus

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

// ============================================================================
// ERRORS
// ============================================================================

var (
	ErrConsumerClosed   = errors.New("consumer is closed")
	ErrHandlerNotFound  = errors.New("handler not found for topic")
	ErrProcessingFailed = errors.New("message processing failed")
)

// ============================================================================
// TYPES
// ============================================================================

// MessageHandler is a function that processes a Kafka message
type MessageHandler func(ctx context.Context, event Event) error

// ConsumerConfig holds consumer configuration
type ConsumerConfig struct {
	Brokers       []string
	GroupID       string
	Topics        []string
	MinBytes      int
	MaxBytes      int
	MaxWait       time.Duration
	StartOffset   int64
	RetryAttempts int
	RetryDelay    time.Duration
}

// DefaultConsumerConfig returns sensible defaults
func DefaultConsumerConfig(groupID string, topics ...string) *ConsumerConfig {
	return &ConsumerConfig{
		Brokers:       []string{"localhost:9092"},
		GroupID:       groupID,
		Topics:        topics,
		MinBytes:      10e3, // 10KB
		MaxBytes:      10e6, // 10MB
		MaxWait:       1 * time.Second,
		StartOffset:   kafka.LastOffset,
		RetryAttempts: 3,
		RetryDelay:    1 * time.Second,
	}
}

// Consumer manages Kafka message consumption
type consumerMessageReader interface {
	FetchMessage(context.Context) (kafka.Message, error)
	CommitMessages(context.Context, ...kafka.Message) error
	Close() error
}

type pendingConsumerMessage struct {
	message   kafka.Message
	event     *Event
	poison    bool
	processed bool
}

type Consumer struct {
	config   *ConsumerConfig
	reader   consumerMessageReader
	pending  *pendingConsumerMessage
	handlers map[string]MessageHandler
	logger   *zap.Logger
	mu       sync.RWMutex
	closed   bool
	wg       sync.WaitGroup
}

// NewConsumer creates a new Kafka consumer
func NewConsumer(config *ConsumerConfig, logger *zap.Logger) (*Consumer, error) {
	if config == nil {
		return nil, errors.New("consumer config is required")
	}
	if len(config.Brokers) == 0 {
		return nil, errors.New("at least one Kafka broker is required")
	}
	if len(config.Topics) == 0 || config.Topics[0] == "" {
		return nil, errors.New("at least one Kafka topic is required")
	}
	if config.GroupID == "" {
		return nil, errors.New("Kafka consumer group ID is required")
	}
	if config.RetryAttempts < 0 {
		return nil, errors.New("Kafka retry attempts cannot be negative")
	}
	if logger == nil {
		logger = zap.NewNop()
	}

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:     config.Brokers,
		GroupID:     config.GroupID,
		Topic:       config.Topics[0], // Single topic for now
		MinBytes:    config.MinBytes,
		MaxBytes:    config.MaxBytes,
		MaxWait:     config.MaxWait,
		StartOffset: config.StartOffset,
	})

	return &Consumer{
		config:   config,
		reader:   reader,
		handlers: make(map[string]MessageHandler),
		logger:   logger,
	}, nil
}

// RegisterHandler registers a handler for a specific event type
func (c *Consumer) RegisterHandler(eventType string, handler MessageHandler) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.handlers[eventType] = handler
	c.logger.Info("registered event handler",
		zap.String("event_type", eventType),
	)
}

// Start begins consuming messages
func (c *Consumer) Start(ctx context.Context) error {
	c.logger.Info("starting consumer",
		zap.String("group_id", c.config.GroupID),
		zap.Strings("topics", c.config.Topics),
	)

	c.wg.Add(1)
	go c.consumeLoop(ctx)

	return nil
}

// consumeLoop is the main consumption loop
func (c *Consumer) consumeLoop(ctx context.Context) {
	defer c.wg.Done()

	for {
		select {
		case <-ctx.Done():
			c.logger.Info("consumer context cancelled, shutting down")
			return
		default:
			if err := c.consumeMessage(ctx); err != nil {
				if errors.Is(err, context.Canceled) {
					return
				}
				c.logger.Error("error consuming message", zap.Error(err))
				time.Sleep(1 * time.Second) // Backoff on error
			}
		}
	}
}

// consumeMessage reads and processes a single message
// consumeMessage fetches without committing, processes with retries, and only
// advances the consumer offset after success. Failed messages remain eligible
// for redelivery after the retry budget is exhausted.
func (c *Consumer) consumeMessage(ctx context.Context) error {
	if c.pending == nil {
		msg, err := c.reader.FetchMessage(ctx)
		if err != nil {
			return err
		}
		c.pending = &pendingConsumerMessage{message: msg}
	}
	pending := c.pending

	if pending.event == nil && !pending.poison {
		var event Event
		if err := json.Unmarshal(pending.message.Value, &event); err != nil {
			c.logger.Error("failed to unmarshal event; committing poison message",
				zap.Error(err), zap.ByteString("value", pending.message.Value),
			)
			pending.poison = true
		} else if event.Type == "" {
			c.logger.Error("event type is missing; committing poison message", zap.String("topic", pending.message.Topic))
			pending.poison = true
		} else {
			pending.event = &event
		}
	}

	if !pending.poison && !pending.processed {
		if err := c.processWithRetry(ctx, *pending.event); err != nil {
			c.logger.Error("failed to process event after retries; retaining message for redelivery",
				zap.String("event_type", pending.event.Type), zap.Error(err))
			return err
		}
		pending.processed = true
	}

	if err := c.reader.CommitMessages(ctx, pending.message); err != nil {
		return fmt.Errorf("commit processed Kafka event: %w", err)
	}
	c.pending = nil
	return nil
}

func (c *Consumer) processWithRetry(ctx context.Context, event Event) error {
	var lastErr error

	for attempt := 0; attempt <= c.config.RetryAttempts; attempt++ {
		if err := c.processEvent(ctx, event); err != nil {
			lastErr = err
			c.logger.Warn("event processing failed, retrying",
				zap.String("event_type", event.Type),
				zap.Int("attempt", attempt+1),
				zap.Error(err),
			)
			if attempt < c.config.RetryAttempts {
				if waitErr := waitForRetry(ctx, c.config.RetryDelay*time.Duration(attempt+1)); waitErr != nil {
					return waitErr
				}
			}
			continue
		}
		return nil
	}

	return fmt.Errorf("%w: %v", ErrProcessingFailed, lastErr)
}

func waitForRetry(ctx context.Context, delay time.Duration) error {
	if delay <= 0 {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			return nil
		}
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

// processEvent routes event to appropriate handler
func (c *Consumer) processEvent(ctx context.Context, event Event) error {
	c.mu.RLock()
	handler, exists := c.handlers[event.Type]
	c.mu.RUnlock()

	if !exists {
		c.logger.Debug("no handler for event type",
			zap.String("event_type", event.Type),
		)
		return nil
	}

	start := time.Now()
	if err := handler(ctx, event); err != nil {
		return err
	}

	c.logger.Debug("event processed successfully",
		zap.String("event_type", event.Type),
		zap.Duration("duration", time.Since(start)),
	)

	return nil
}

// Stop gracefully stops the consumer
func (c *Consumer) Stop() error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return nil
	}
	c.closed = true
	c.mu.Unlock()

	c.logger.Info("stopping consumer")

	// Wait for processing to complete
	c.wg.Wait()

	// Close reader
	if err := c.reader.Close(); err != nil {
		c.logger.Error("failed to close reader", zap.Error(err))
		return err
	}

	c.logger.Info("consumer stopped successfully")
	return nil
}

// ============================================================================
// CONSUMER GROUP (Multiple Topics)
// ============================================================================

// ConsumerGroup manages multiple consumers for different topics
type ConsumerGroup struct {
	consumers []*Consumer
	logger    *zap.Logger
	mu        sync.Mutex
}

// NewConsumerGroup creates a new consumer group
func NewConsumerGroup(logger *zap.Logger) *ConsumerGroup {
	return &ConsumerGroup{
		consumers: make([]*Consumer, 0),
		logger:    logger,
	}
}

// AddConsumer adds a consumer to the group
func (g *ConsumerGroup) AddConsumer(consumer *Consumer) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.consumers = append(g.consumers, consumer)
}

// StartAll starts all consumers in the group
func (g *ConsumerGroup) StartAll(ctx context.Context) error {
	for _, consumer := range g.consumers {
		if err := consumer.Start(ctx); err != nil {
			return err
		}
	}
	return nil
}

// StopAll stops all consumers in the group
func (g *ConsumerGroup) StopAll() error {
	var lastErr error
	for _, consumer := range g.consumers {
		if err := consumer.Stop(); err != nil {
			lastErr = err
		}
	}
	return lastErr
}
