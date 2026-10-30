#!/usr/bin/env python3
"""Static regression checks for independent, acknowledgement-aware consumers."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
checks = []

def check(label, condition):
    checks.append((label, bool(condition)))

kafka = (ROOT / "services/api/internal/shared/eventbus/kafka_bus.go").read_text()
helper = (ROOT / "services/api/internal/shared/eventbus/reliable_subscriber.go").read_text()
notifications = (ROOT / "services/api/internal/modules/notifications/interfaces/event_consumer.go").read_text()
telephony = (ROOT / "services/api/internal/modules/telephony/interfaces/event_consumer.go").read_text()

check("KafkaBus retains configured brokers", "brokers: append([]string(nil), brokers...)" in kafka and "Brokers: b.brokers" in kafka)
check("legacy subscriptions no longer share one hardcoded group", "nidaw-best-effort-%d" in kafka and 'GroupID: "nidaw-consumer"' not in kafka)
check("durable subscription requires explicit stable group ID", '"topic, stable consumer group ID, and event handler are required"' in kafka)
check("reliable subscriber fetches without auto-commit", "reader.FetchMessage(ctx)" in kafka and "reader.ReadMessage(ctx)" not in kafka)
check("handler errors retain message without offset commit", "reliable handler failed; retaining event" in kafka and "if err := handler(ctx, *pendingEvent); err != nil" in kafka)
check("successful handler is not repeated for commit retries", "if !processed" in kafka and "processed = true" in kafka)
handler_pos = kafka.index("if err := handler(ctx, *pendingEvent); err != nil")
commit_pos = kafka.rindex("if err := reader.CommitMessages(ctx, *pending); err != nil")
check("offset commit follows handler success", handler_pos < commit_pos)
check("retry waits respect cancellation", "waitForRetry(ctx, time.Second)" in kafka)
check("compatibility adapter makes fallback limitation explicit", "cannot retry handler failure" in helper)
check("notifications uses stable per-topic reliable groups", '"nidaw-notifications-v1"' in notifications and "SubscribeReliableTopics" in notifications)
check("telephony uses stable per-topic reliable groups", '"nidaw-telephony-v1"' in telephony and "SubscribeReliableTopics" in telephony)
check("notifications subscribes to ride, location, and payment producer topics", all(t in notifications for t in ['"nidus.rides"', '"nidus.locations"', '"payments"']))
check("telephony subscribes to the actual ride producer topic", '"nidus.rides"' in telephony)
check("topic-aware helpers reject duplicate/empty topic declarations", "event topics must be unique" in helper and "event topic cannot be empty" in helper)

failed = [label for label, passed in checks if not passed]
for label, passed in checks:
    print(("PASS" if passed else "FAIL") + ": " + label)
print(f"{len(checks) - len(failed)}/{len(checks)} assertions passed")
if failed:
    raise SystemExit(1)
