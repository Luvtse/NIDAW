#!/usr/bin/env python3
"""Structural regression checks for the versioned cross-product event catalog."""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "packages/event-contracts/catalog.json"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def main() -> None:
    try:
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read valid catalog JSON: {exc}")
    if catalog.get("catalog_version") != 1:
        fail("catalog_version must be 1")
    policy = catalog.get("compatibility_policy", {})
    for key in ("new_events", "legacy_events", "breaking_change", "delivery"):
        if not policy.get(key):
            fail(f"compatibility policy missing {key}")
    events = catalog.get("events")
    if not isinstance(events, list) or not events:
        fail("events must be a non-empty list")
    seen = set()
    for event in events:
        for field in ("type", "schema_version", "producer", "topic", "required_fields", "consumers", "consumer_status", "source_paths"):
            if field not in event:
                fail(f"{event.get('type', '<unknown>')} missing {field}")
        event_type = event["type"]
        if event_type in seen:
            fail(f"duplicate event type: {event_type}")
        seen.add(event_type)
        if not isinstance(event["schema_version"], int) or event["schema_version"] < 0:
            fail(f"invalid schema_version for {event_type}")
        if not isinstance(event["required_fields"], list) or not event["required_fields"]:
            fail(f"required_fields must be a non-empty list for {event_type}")
        if not event["producer"] or not event["topic"] or not event["consumer_status"]:
            fail(f"producer/topic/status must be documented for {event_type}")
        if not isinstance(event["source_paths"], list) or not event["source_paths"]:
            fail(f"source_paths must be a non-empty list for {event_type}")
        for source_path in event["source_paths"]:
            source = ROOT / source_path
            if not source.is_file():
                fail(f"source path missing for {event_type}: {source_path}")
    # Pin the highest-risk integration edges so the catalogue cannot silently
    # lose the Corpus -> Logix freight approval or Logix customs handoff records.
    by_type = {event["type"]: event for event in events}
    required = {
        "corpus.booking.approved": "booking_data",
        "corpus.booking.rejected": "corporate_booking_id",
        "logix.customs.cleared": "shipment_id",
        "logix.load.matched": "carrier_id",
    }
    for event_type, field in required.items():
        event = by_type.get(event_type)
        if event is None:
            fail(f"required cross-product event missing: {event_type}")
        if field not in event["required_fields"]:
            fail(f"{event_type} missing required contract field {field}")
    print(f"PASS: event contract catalog structure ({len(events)} event contracts)")
    print("PASS: source files exist for every catalog entry")
    print("PASS: compatibility policy and required Corpus/Logix handoff contracts")


if __name__ == "__main__":
    main()
