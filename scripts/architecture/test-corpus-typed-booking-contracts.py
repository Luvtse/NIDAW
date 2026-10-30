#!/usr/bin/env python3
"""Static regression checks for Corpus service-specific booking contracts."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
contracts = ROOT / "services/api/internal/modules/corpus/domain/bookingdata/contracts.go"
tests = ROOT / "services/api/internal/modules/corpus/domain/bookingdata/contracts_test.go"
command = ROOT / "services/api/internal/modules/corpus/application/commands/create_booking.go"
source = contracts.read_text()
test_source = tests.read_text()
command_source = command.read_text()
required = ["type RideV1 struct", "type HotelV1 struct", "type FoodV1 struct", "type FreightV1 struct", "const SchemaVersion = 1", "func Parse(", "RawPayload()"]
missing = [item for item in required if item not in source]
if missing:
    raise SystemExit(f"typed booking contract definitions missing: {missing}")
for service in ["ServiceRides", "ServiceHotels", "ServiceFood", "ServiceFreight"]:
    if service not in source:
        raise SystemExit(f"typed contract parser missing service: {service}")
if "bookingdata.Parse(cmd.ServiceType, cmd.BookingData)" not in command_source:
    raise SystemExit("booking command does not validate the typed contract before processing")
for token in ["TestParseReturnsTypedRideContractAndPreservesExtraFields", "TestParseRejectsMissingOrInvalidPolicyFields", "TestParseRejectsUnsupportedService"]:
    if token not in test_source:
        raise SystemExit(f"typed contract test missing: {token}")
print("Corpus typed booking contract assertions passed")
