#!/usr/bin/env python3
"""Exercise Secret preflight with a fake kubectl; never use a real cluster."""
import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/deploy/preflight-kubernetes-secrets.py"


def run_case(secret_map, expected_code, expected_fragments=(), forbidden_fragments=(), cli_args=(), expect_no_kubectl=False):
    with tempfile.TemporaryDirectory() as temp:
        bindir = Path(temp)
        fake = bindir / "kubectl"
        fake.write_text("""#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
if '-o' not in args or 'json' not in args:
    sys.exit(3)
if args[0:2] == ['get', 'namespace']:
    print('cluster-scoped namespace query should not be required', file=sys.stderr)
    sys.exit(5)
if args[0:2] == ['get', 'secret']:
    name = args[2]
    payload = json.loads(os.environ['FAKE_SECRET_MAP'])
    if name not in payload:
        print('secret missing with potentially sensitive details', file=sys.stderr)
        sys.exit(1)
    print(json.dumps(payload[name]))
    sys.exit(0)
sys.exit(4)
""", encoding="utf-8")
        fake.chmod(0o755)
        env = os.environ.copy()
        env["PATH"] = f"{bindir}{os.pathsep}{env['PATH']}"
        env["FAKE_SECRET_MAP"] = json.dumps(secret_map)
        env["FAKE_KUBECTL_MARKER"] = str(bindir / "kubectl-called")
        fake.write_text(fake.read_text(encoding="utf-8").replace("args = sys.argv[1:]", "args = sys.argv[1:]\nopen(os.environ['FAKE_KUBECTL_MARKER'], 'w').write('called')"), encoding="utf-8")
        fake.chmod(0o755)
        result = subprocess.run(
            ["python3", str(SCRIPT), "--namespace", "nidaw-staging", "--tls-secret", "nidaw-tls", *cli_args],
            env=env, text=True, capture_output=True, check=False,
        )
        if expect_no_kubectl:
            assert not (bindir / "kubectl-called").exists(), "kubectl was invoked for invalid input"
        assert result.returncode == expected_code, (result.returncode, result.stdout, result.stderr)
        combined = result.stdout + result.stderr
        for fragment in expected_fragments:
            assert fragment in combined, (fragment, combined)
        for fragment in forbidden_fragments:
            assert fragment not in combined, (fragment, combined)

backend = {
    "metadata": {"name": "nidaw-backend-secrets"}, "type": "Opaque",
    "data": {key: "BASE64-SECRET-SENTINEL" for key in ("db-password", "jwt-secret", "kafka-brokers", "redis-url")},
}
tls = {
    "metadata": {"name": "nidaw-tls"}, "type": "kubernetes.io/tls",
    "data": {"tls.crt": "CERT-SENTINEL", "tls.key": "PRIVATE-KEY-SENTINEL"},
}
run_case({"nidaw-backend-secrets": backend, "nidaw-tls": tls}, 0,
         ("PASS: deployment Secret preflight succeeded", "TLS Secret nidaw-tls"),
         ("BASE64-SECRET-SENTINEL", "PRIVATE-KEY-SENTINEL", "CERT-SENTINEL"))

missing_key = {**backend, "data": {"db-password": "opaque"}}
run_case({"nidaw-backend-secrets": missing_key, "nidaw-tls": tls}, 1,
         ("missing required key(s): jwt-secret, kafka-brokers, redis-url",),
         ("BASE64-SECRET-SENTINEL", "PRIVATE-KEY-SENTINEL"))

wrong_tls = {**tls, "type": "Opaque"}
run_case({"nidaw-backend-secrets": backend, "nidaw-tls": wrong_tls}, 1,
         ("TLS Secret nidaw-tls must have type kubernetes.io/tls",),
         ("PRIVATE-KEY-SENTINEL", "CERT-SENTINEL"))

print("PASS: Secret preflight accepts required keys and valid TLS metadata without exposing values")
print("PASS: Secret preflight fails closed for missing backend keys and wrong TLS type")
print("PASS: Secret preflight does not require cluster-scoped Namespace read permission")

run_case({}, 2, ("namespace must be a valid DNS-label",), cli_args=("--namespace", "BAD_NAMESPACE"), expect_no_kubectl=True)
run_case({}, 2, ("backend Secret name must be a valid Kubernetes DNS-subdomain",), cli_args=("--backend-secret", "Bad_Name"), expect_no_kubectl=True)
run_case({}, 2, ("TLS Secret name must be a valid Kubernetes DNS-subdomain",), cli_args=("--tls-secret", "Bad_Name"), expect_no_kubectl=True)
print("PASS: malformed namespace and Secret identifiers are rejected before kubectl execution")
