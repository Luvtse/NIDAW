# Phase 0 — Kubernetes CLI credential and preflight ordering

**Date:** 2026-10-23  
**Status:** Static regression guard added; hosted-runner and live-cluster behavior not verified.

## Finding

The staging and production deployment workflows query the target EKS cluster to resolve a compatible `kubectl` client version. That query depends on AWS credentials, and the Secret preflight depends on a configured Kubernetes context. These are ordering requirements, not just step-presence requirements.

## Change

Extended `scripts/audit/test-github-workflow-step-contract.py` to enforce the following sequence for the staging deploy, production canary, and full production deploy jobs:

1. Configure AWS credentials.
2. Query the target EKS cluster and resolve its Kubernetes minor version.
3. Install the resolved `kubectl` client.
4. Verify the installed client version.
5. Configure kubeconfig.
6. Run external Kubernetes Secret preflight.
7. Execute cluster-dependent `kubectl` commands only after kubeconfig setup.

The test continues to verify that Helm is explicitly installed and verified before Helm deployment commands.

## Validation and limits

The static workflow contract test and YAML parsing must pass locally. This does not prove that GitHub-hosted action versions resolve, AWS permissions allow `eks:DescribeCluster`, the cluster is reachable, required Secrets exist, or a deployment succeeds. Those require the actual CI environment and EKS access.
