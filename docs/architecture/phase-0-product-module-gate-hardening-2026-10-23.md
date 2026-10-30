# Phase 0 — Product Module Gate Hardening

## Change

` scripts/architecture/check-go-product-boundaries.py` previously returned exit code 0 when it found no direct product-to-product imports, even though it also reported that the Haven and Vorax Go module directories were absent. Because the check is wired into backend CI, that behavior could make a narrow import scan look green despite missing first-class product modules.

The guard now fails closed when either:

- a direct Go import crosses between the five product modules (`nidus`, `haven`, `vorax`, `logix`, `corpus`); or
- one of the required product module directories is missing.

The output explicitly says not to create empty placeholder packages. The correct resolution is to implement real domain/application behavior or provide an evidence-backed, reviewed alternate-runtime decision before changing the gate.

## Current source result

Expected current result for this repository snapshot: **FAIL** because `services/api/internal/modules/haven/` and `services/api/internal/modules/vorax/` do not exist. The direct import scan found no direct imports between the existing product modules, but that narrow result is not sufficient to accept the five-product architecture.

This is an intentional fail-closed CI result, not a claim that all Go tests failed. It exposes an already documented implementation gap rather than fabricating product code.

## Validation limits

The Go test suite could not compile in this environment because external Go modules are not cached and dependency retrieval is unavailable (`GOPROXY=off` was used to keep the check bounded). This is **blocked/inconclusive**, not a test pass and not evidence of a source-level Go test failure.

The gate does not establish route reachability, data ownership, event contracts, runtime behavior, or completeness of the existing Corpus and Logix modules. Those remain separate acceptance requirements.

## CI ordering

The backend workflow runs Go dependency installation, tests, and the coverage-upload step before this architecture gate. The gate is evaluated with `if: always()` so a missing product module is reported even if an earlier test step fails; it does not suppress the test result. The build job already depends on the test job, so a failing architecture gate blocks image publication.
