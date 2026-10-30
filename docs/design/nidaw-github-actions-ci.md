# NIDAW GitHub Actions CI

The consolidated CI workflow is `.github/workflows/ci.yml`.

It runs on pushes and pull requests targeting `main` or `develop`, and supports manual dispatch. It validates the Go API, consumer and driver Flutter apps, React/Vite admin console, and Go product-module import boundaries. Pull requests also receive dependency review. CI artifacts are retained for 14 days.

The existing staging deployment, production deployment, and security-scan workflows are preserved. The previous standalone backend/frontend CI workflows were removed to avoid duplicate CI runs.

## Repository prerequisites and limitations

- The Go job starts PostgreSQL, Redis, and Kafka service containers and exposes their standard local ports. Backend integration tests must read the documented environment variables if they need these services.
- Flutter analysis runs for both apps. Flutter tests run only when Dart test files exist, so an empty test directory does not fail CI.
- The admin job expects `apps/admin_console/package-lock.json` and the existing `lint` and `build` npm scripts.
- The architecture job runs `scripts/architecture/check-go-product-boundaries.py`; it fails if required product module directories are missing or cross-product private Go imports are detected.
- Action major versions are pinned to official marketplace action release tags. For environments requiring immutable supply-chain pinning, replace action tags with reviewed full commit SHAs and update them through a controlled dependency-update process.
- This workflow performs CI validation; it does not itself deploy artifacts to production.
