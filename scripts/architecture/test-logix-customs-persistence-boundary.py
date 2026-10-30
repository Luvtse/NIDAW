#!/usr/bin/env python3
"""Static regression checks for the Logix customs application/persistence boundary."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
SERVICE = ROOT / "services/api/internal/modules/logix/application/services/customs_service.go"
REPOSITORY = ROOT / "services/api/internal/modules/logix/infrastructure/postgres/customs_repository.go"
TESTS = ROOT / "services/api/internal/modules/logix/application/services/customs_service_test.go"

checks = []

def check(name: str, condition: bool) -> None:
    checks.append((name, condition))

service = SERVICE.read_text()
repository = REPOSITORY.read_text()
tests = TESTS.read_text()

check("application service depends on a customs repository port", "type CustomsRepository interface" in service and "repository CustomsRepository" in service)
check("application service no longer imports the database adapter", '"nidaw-backend/internal/shared/database"' not in service and "s.db." not in service)
check("PostgreSQL adapter implements the application port", "var _ services.CustomsRepository = (*CustomsRepository)(nil)" in repository)
check("submission state changes share a transaction", "MarkDeclarationSubmitted" in repository and "r.db.WithTx(ctx" in repository)
check("status and shipment clearance changes share a transaction", "UpdateDeclarationStatus" in repository and "entities.CustomsCleared" in repository and "r.db.WithTx(ctx" in repository)
check("writes check affected-row counts", repository.count("RowsAffected() != 1") >= 3)
check("terminal customs states cannot be overwritten by later polls", "status IN ('submitted', 'pending', 'under_review', 'held')" in repository and "'cleared')" not in repository)
check("repository rejects unknown status values and negative duties/taxes", "unsupported customs status" in repository and "duties and taxes must be finite non-negative amounts" in repository and "math.IsInf(dutiesOwed" in repository and "math.IsNaN(taxesOwed" in repository)
check("invalid package counts and non-finite values are rejected", "shipment.PackageCount <= 0" in service and "math.IsInf" in service and "math.IsNaN" in service)
check("tariff exemption failures fail closed", "failed to get duty exemptions" in service)
check("invalid tariff rates and overflowing duties fail closed", "tariff rate must be a finite non-negative percentage" in service and "calculated customs duties must be finite and non-negative" in service)
check("exemptions are not assigned an invented fixed reduction", "duties *= 0.5" not in service and "explicit calculation policy" in service)
check("unknown customs API status fails closed", 'unsupported customs status %q' in service)
check("submission requires non-zero declaration and shipment IDs before external side effects", 'declaration.ID == uuid.Nil || declaration.ShipmentID == uuid.Nil' in service and 'TestSubmitDeclarationRejectsMissingIDsBeforeExternalCall' in tests)
check("empty authority reference is rejected before persistence", 'strings.TrimSpace(externalID) == ""' in service and 'TestSubmitDeclarationRejectsEmptyExternalIDWithoutPersistence' in tests)
check("submission persistence failure is explicitly tested", 'TestSubmitDeclarationPropagatesPersistenceFailure' in tests and 'retry safety depends on authority-side' in service)
check("polling rejects a zero declaration ID before repository lookup", 'if declarationID == uuid.Nil' in service and 'TestPollDeclarationStatusRejectsNilIDBeforeRepositoryLookup' in tests)
check("external polling amounts are validated before persistence", "customs authority returned duties or taxes that are not finite non-negative amounts" in service and "TestPollDeclarationStatusRejectsInvalidAmountsBeforePersistence" in tests)
check("authority status lookup errors include operation context", 'query customs authority status for external declaration' in service)
check("unit regression tests cover validation and status mapping", "TestPrepareDeclarationRejectsInvalidShipmentBeforeTariffLookup" in tests and "TestMapStatusRejectsUnknownExternalValues" in tests)
check("unit tests cover invalid tariff rates, duty overflow, and unresolved exemptions", "TestPrepareDeclarationRejectsInvalidTariffRatesWithoutPersistence" in tests and "TestPrepareDeclarationRejectsDutyOverflowWithoutPersistence" in tests and "TestPrepareDeclarationDoesNotInventExemptionReduction" in tests)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
print(f"{len(checks) - len(failed)}/{len(checks)} assertions passed")
sys.exit(1 if failed else 0)
