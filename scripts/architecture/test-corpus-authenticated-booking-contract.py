#!/usr/bin/env python3
"""Static guardrails for Corpus authenticated booking identity and route wiring."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
router = (ROOT / "services/api/internal/modules/corpus/interfaces/http/router.go").read_text()
command = (ROOT / "services/api/internal/modules/corpus/application/commands/create_booking.go").read_text()
repository = (ROOT / "services/api/internal/modules/corpus/infrastructure/postgres/booking_repository.go").read_text()
main = (ROOT / "services/api/cmd/server/main.go").read_text()
http_tests = (ROOT / "services/api/internal/modules/corpus/interfaces/http/router_test.go").read_text()

checks = {
    "protected Corpus route": 'pr.Use(middleware.AuthRequired(authService))' in router,
    "user identity extracted from auth context": 'auth.GetUserIDFromContext(r.Context())' in router,
    "request does not accept employee ID": 'EmployeeID' not in router,
    "application command carries authenticated user ID": 'UserID: userID' in router and 'UserID        uuid.UUID' in command,
    "membership lookup uses authenticated user and selected corporate account": 'WHERE e.user_id = $1 AND e.corporate_id = $2' in repository,
    "persisted booking uses resolved employee membership ID": 'EmployeeID: employee.ID' in command,
    "account and employee membership must both be active": "e.status = 'active' AND a.status = 'active'" in repository,
    "HTTP tests cover authentication and client-supplied employee ID rejection": 'TestCreateBookingRequiresAuthenticatedUser' in http_tests and 'TestCreateBookingDerivesUserFromContextAndRejectsEmployeeIDField' in http_tests,
    "HTTP errors do not echo arbitrary internal errors": 'message := "booking request could not be processed"' in router,
    "Corpus routes are registered in server composition": 'corpushttp.RegisterRoutes(r, db, authService)' in main,
}
failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if failed:
    raise SystemExit(f"{len(failed)} Corpus booking contract assertion(s) failed")
