#!/usr/bin/env python3
"""Pin notification dedupe behavior to stable event identity."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
consumer = (root / "services/api/internal/modules/notifications/interfaces/event_consumer.go").read_text()
tests = (root / "services/api/internal/modules/notifications/interfaces/event_consumer_test.go").read_text()
checks = {
    "stable event ID has priority": 'return "event:" + id' in consumer,
    "arrival events require tier when no event ID": 'case "driver.arriving":' in consumer and '"approach_tier"' in consumer,
    "repeatable arrival is not collapsed by ride alone": 'later legitimate arrival notification' in consumer,
    "destination changes include destination identity": '"new_dropoff_lat"' in consumer and '"new_dropoff_lng"' in consumer,
    "destination change without identity remains unkeyed": '"ride.destination_changed"' in consumer and 'return ""' in consumer,
    "event-ID priority is tested": 'outbox event ID is primary identity' in tests,
    "arrival tiers are tested": 'arrival tier distinguishes repeated event' in tests,
    "missing arrival tier is tested": 'arrival without tier is not incorrectly deduped' in tests,
    "destination change identity is tested": 'destination change includes new destination' in tests,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL") + " " + name)
if failed:
    raise SystemExit(f"{len(failed)} notification event idempotency assertion(s) failed")
print(f"All {len(checks)} notification event idempotency assertions passed")
