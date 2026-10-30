#!/usr/bin/env python3
"""Static GitHub Actions step contract: every step must use exactly one execution mode."""
from pathlib import Path
import sys
import yaml

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"
errors = []
workflow_count = 0
step_count = 0

for path in sorted(WORKFLOWS.glob("*.yml")):
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"{path.relative_to(ROOT)}: YAML parse error: {exc}")
        continue
    workflow_count += 1
    jobs = data.get("jobs", {}) if isinstance(data, dict) else {}
    if not isinstance(jobs, dict):
        errors.append(f"{path.relative_to(ROOT)}: jobs must be a mapping")
        continue
    for job_name, job in jobs.items():
        steps = job.get("steps", []) if isinstance(job, dict) else []
        for index, step in enumerate(steps):
            step_count += 1
            where = f"{path.relative_to(ROOT)} job={job_name} step={index}"
            if not isinstance(step, dict):
                errors.append(f"{where}: step must be a mapping")
                continue
            has_uses = isinstance(step.get("uses"), str)
            has_run = isinstance(step.get("run"), str)
            if has_uses == has_run:
                errors.append(f"{where}: step must define exactly one of 'uses' or 'run'")

# The architecture gate must not prevent Go tests from running. It should still
# report missing required product modules after earlier test/coverage steps fail.
backend_ci = yaml.safe_load((WORKFLOWS / "backend-ci.yml").read_text(encoding="utf-8"))
backend_steps = backend_ci["jobs"]["test"]["steps"]
backend_names = {step.get("name"): index for index, step in enumerate(backend_steps) if isinstance(step, dict) and step.get("name")}
for required_step in ("Run tests", "Upload coverage", "Enforce product module presence and import boundaries"):
    assert required_step in backend_names, f"backend-ci: missing {required_step} step"
assert backend_names["Run tests"] < backend_names["Upload coverage"] < backend_names["Enforce product module presence and import boundaries"], (
    "backend-ci: product architecture gate must run after the Go test and coverage steps"
)
assert backend_steps[backend_names["Enforce product module presence and import boundaries"]].get("if") == "always()", (
    "backend-ci: architecture gate must still report missing product modules after test failures"
)

# Runner network visibility must be enabled before checkout and test commands.
staging = yaml.safe_load((WORKFLOWS / "deploy-staging.yml").read_text(encoding="utf-8"))
smoke_steps = staging["jobs"]["smoke-tests"]["steps"]
assert smoke_steps[0].get("name") == "Harden runner network visibility", (
    "staging smoke-tests must enable runner network visibility before other steps"
)
assert smoke_steps[0].get("uses") == "step-security/harden-runner@v2"
assert smoke_steps[0].get("with", {}).get("egress-policy") == "audit"

# Every active Helm deployment job must provision a pinned Helm 3 CLI before use.
for workflow_name, job_names in (("deploy-staging.yml", ("deploy",)), ("deploy-prod.yml", ("canary", "deploy"))):
    workflow = yaml.safe_load((WORKFLOWS / workflow_name).read_text(encoding="utf-8"))
    for job_name in job_names:
        steps = workflow["jobs"][job_name]["steps"]
        setup_indexes = [
            index for index, step in enumerate(steps)
            if step.get("uses") == "azure/setup-helm@v5.0.1"
        ]
        assert len(setup_indexes) == 1, f"{workflow_name} job={job_name}: expected one pinned Helm setup action"
        setup_index = setup_indexes[0]
        assert steps[setup_index].get("with", {}).get("version") == "v3.18.4", (
            f"{workflow_name} job={job_name}: Helm version must remain pinned to v3.18.4"
        )
        verify_indexes = [
            index for index, step in enumerate(steps)
            if step.get("name") == "Verify Helm version" and step.get("run") == "helm version --short"
        ]
        assert len(verify_indexes) == 1 and setup_index < verify_indexes[0], (
            f"{workflow_name} job={job_name}: Helm version must be checked after setup"
        )
        first_helm_use = next(
            index for index, step in enumerate(steps)
            if isinstance(step.get("run"), str)
            and any(command in step["run"] for command in ("helm upgrade", "helm uninstall"))
        )
        assert setup_index < first_helm_use and verify_indexes[0] < first_helm_use, (
            f"{workflow_name} job={job_name}: Helm must be installed and checked before use"
        )

# Kubernetes CLI version must be resolved from the target EKS cluster, installed, and verified
# before kubeconfig-dependent preflight or any kubectl command.
for workflow_name, job_names in (("deploy-staging.yml", ("deploy",)), ("deploy-prod.yml", ("canary", "deploy"))):
    workflow = yaml.safe_load((WORKFLOWS / workflow_name).read_text(encoding="utf-8"))
    for job_name in job_names:
        steps = workflow["jobs"][job_name]["steps"]
        named = {step.get("name"): index for index, step in enumerate(steps) if isinstance(step, dict) and step.get("name")}
        aws_credentials_index = named.get("Configure AWS")
        resolve_index = named.get("Resolve compatible kubectl version")
        setup_index = named.get("Set up kubectl")
        verify_index = named.get("Verify kubectl version")
        kubeconfig_index = named.get("Update kubeconfig")
        secret_preflight_index = named.get("Preflight external Kubernetes Secrets")
        assert None not in (
            aws_credentials_index,
            resolve_index,
            setup_index,
            verify_index,
            kubeconfig_index,
            secret_preflight_index,
        ), f"{workflow_name} job={job_name}: missing AWS/kubectl/kubeconfig/Secret preflight steps"
        assert aws_credentials_index < resolve_index < setup_index < verify_index < kubeconfig_index < secret_preflight_index, (
            f"{workflow_name} job={job_name}: AWS credentials must precede EKS version lookup; kubectl must be installed and verified before kubeconfig and Secret preflight"
        )
        for index, step in enumerate(steps):
            command = step.get("run", "") if isinstance(step, dict) else ""
            cluster_commands = [
                line.strip()
                for line in command.splitlines()
                if line.strip().startswith("kubectl ")
                and not line.strip().startswith("kubectl version --client")
            ]
            if cluster_commands:
                assert index > kubeconfig_index, (
                    f"{workflow_name} job={job_name} step={index}: cluster-dependent kubectl command precedes kubeconfig setup"
                )
        resolve_step = steps[resolve_index]
        resolve_run = resolve_step.get("run", "")
        assert resolve_step.get("id") == "kubectl-version", (
            f"{workflow_name} job={job_name}: version resolver output id changed"
        )
        assert "aws eks describe-cluster" in resolve_run and "cluster.version" in resolve_run, (
            f"{workflow_name} job={job_name}: kubectl version must derive from the target EKS cluster"
        )
        assert "https://dl.k8s.io/release/stable-${cluster_version}.txt" in resolve_run, (
            f"{workflow_name} job={job_name}: resolve the latest patch for the cluster minor version"
        )
        assert steps[setup_index].get("uses") == "azure/setup-kubectl@v4", (
            f"{workflow_name} job={job_name}: expected explicit kubectl setup action"
        )
        assert steps[setup_index].get("with", {}).get("version") == "${{ steps.kubectl-version.outputs.version }}", (
            f"{workflow_name} job={job_name}: kubectl setup must use the resolved version"
        )
        assert steps[verify_index].get("run") == "kubectl version --client --output=yaml", (
            f"{workflow_name} job={job_name}: kubectl client version must be verified"
        )

if errors:
    print("\n".join(f"FAIL: {item}" for item in errors), file=sys.stderr)
    raise SystemExit(1)

print(f"PASS: parsed {workflow_count} workflow files and checked {step_count} steps")
print("PASS: every step defines exactly one of uses or run")
print("PASS: backend architecture gate runs after tests/coverage and still reports blockers on failure")
print("PASS: staging smoke-test network visibility is enabled before checkout")
print("PASS: staging and production deployment jobs install and verify pinned Helm v3.18.4")
print("PASS: staging and production jobs resolve kubectl from the EKS minor version, install it, and verify it before use")
