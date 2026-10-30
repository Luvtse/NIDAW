#!/usr/bin/env python3
"""Regression checks for deployment workflow token permissions and shell input handling."""
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"

def load(name):
    return yaml.safe_load((WORKFLOWS / name).read_text(encoding="utf-8"))

staging = load("deploy-staging.yml")
production = load("deploy-prod.yml")

for name, workflow in (("staging", staging), ("production", production)):
    assert workflow.get("permissions") == {"contents": "read"}, (name, workflow.get("permissions"))

for job_name in ("build-backend", "build-frontend"):
    perms = staging["jobs"][job_name].get("permissions")
    assert perms == {"contents": "read", "packages": "write"}, (job_name, perms)
assert staging["jobs"]["notify"].get("permissions") == {}

assert production["jobs"]["build"].get("permissions") == {"contents": "read", "packages": "write"}
assert production["jobs"]["release"].get("permissions") == {"contents": "write"}
assert production["jobs"]["notify"].get("permissions") == {}

validate = next(s for s in production["jobs"]["validate"]["steps"] if s.get("name") == "Validate version tag")
assert validate.get("env", {}).get("VERSION_INPUT") == "${{ github.ref_name || inputs.version }}"
assert "${{" not in validate.get("run", ""), "version input must not be interpolated directly into shell source"
assert 'VERSION="$VERSION_INPUT"' in validate["run"]

get_version = next(s for s in production["jobs"]["build"]["steps"] if s.get("name") == "Get version")
assert get_version.get("env", {}).get("VERSION_INPUT") == "${{ github.ref_name || inputs.version }}"
assert "${{" not in get_version.get("run", ""), "version output must not interpolate user input into shell source"
assert '"$VERSION_INPUT"' in get_version["run"]

# Keep validation useful while ensuring the production release remains blocked.
validate_steps = production["jobs"]["validate"]["steps"]
assert not any(s.get("name") == "Fail closed until production migration execution is reviewed" for s in validate_steps)
assert any(s.get("name") == "Run full test suite" for s in validate_steps)
scan = next(s for s in validate_steps if s.get("name") == "Scan repository for vulnerabilities, misconfiguration, and secrets")
assert scan.get("uses") == "aquasecurity/trivy-action@v0.36.0"
assert scan.get("with", {}).get("scan-type") == "fs"
assert scan.get("with", {}).get("scanners") == "vuln,misconfig,secret"
assert scan.get("with", {}).get("severity") == "CRITICAL,HIGH"
assert str(scan.get("with", {}).get("exit-code")) == "1"
assert "trivy fs" not in "\n".join(str(step.get("run", "")) for step in validate_steps)
assert "gitleaks detect" not in "\n".join(str(step.get("run", "")) for step in validate_steps)
gate = production["jobs"]["production-migration-review-gate"]
assert gate.get("needs") == "validate"
guard = next(s for s in gate["steps"] if s.get("name") == "Fail closed until production migration execution is reviewed")
assert "exit 1" in guard.get("run", "")
assert production["jobs"]["build"].get("needs") == ["validate", "production-migration-review-gate"]

print("PASS: staging and production workflows default to contents: read")
print("PASS: registry write permission is scoped to image-build jobs")
print("PASS: notification jobs receive no GITHUB_TOKEN permissions")
print("PASS: production version input reaches shell only through an environment variable")
print("PASS: production migration-review guard remains fail-closed")
