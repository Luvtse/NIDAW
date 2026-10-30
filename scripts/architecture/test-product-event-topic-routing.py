#!/usr/bin/env python3
"""Static regression checks for product event topic routing."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
checks = []
def check(label, condition): checks.append((label, bool(condition)))

kafka = (ROOT / "services/api/internal/shared/eventbus/kafka_bus.go").read_text()
mem = (ROOT / "services/api/internal/shared/eventbus/memory_bus.go").read_text()
helper = (ROOT / "services/api/internal/shared/eventbus/reliable_subscriber.go").read_text()
notifications = (ROOT / "services/api/internal/modules/notifications/interfaces/event_consumer.go").read_text()
telephony = (ROOT / "services/api/internal/modules/telephony/interfaces/event_consumer.go").read_text()
ws = (ROOT / "services/api/internal/modules/nidus/interfaces/http/handlers/ws_bridge.go").read_text()
watcher = (ROOT / "services/api/internal/modules/nidus/application/services/driver_arriving_watcher.go").read_text()

def topic_present(source, topic): return f'"{topic}"' in source
check("Kafka Publish honors explicit topic", "Topic: topic" in kafka)
check("MemoryBus stores topic on subscriptions", "topic: topic" in mem)
check("MemoryBus filters by published topic", "if h.topic == topic" in mem)
check("MemoryBus rejects empty publication topic", 'event topic is required' in mem)
check("reliable multi-topic helper exists", "func SubscribeReliableTopics" in helper)
check("multi-topic group IDs are topic-qualified", 'groupID+"-"+topic' in helper)
check("notifications consumes ride topic", topic_present(notifications, "nidus.rides"))
check("notifications consumes location topic", topic_present(notifications, "nidus.locations"))
check("notifications consumes payment topic", topic_present(notifications, "payments"))
check("telephony consumes ride topic", topic_present(telephony, "nidus.rides"))
check("WebSocket bridge consumes ride topic", topic_present(ws, "nidus.rides"))
check("WebSocket bridge consumes location topic", topic_present(ws, "nidus.locations"))
check("driver-arriving watcher consumes location topic", topic_present(watcher, "nidus.locations"))
check("contract review documents observed routing", (ROOT / "docs/architecture/product-event-topic-contracts-2026-10-24.md").exists())

failed = [label for label, passed in checks if not passed]
for label, passed in checks:
    print(("PASS" if passed else "FAIL") + ": " + label)
print(f"{len(checks) - len(failed)}/{len(checks)} assertions passed")
if failed: raise SystemExit(1)
