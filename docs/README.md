# NIDAW Engineering Documentation

This directory contains the maintained engineering documentation for the repository. Each file is the single current reference for its subject. It describes verified repository behavior and explicitly identifies incomplete or planned capabilities.

## Architecture

- [System architecture](architecture/system-architecture.md)
- [Domain boundaries](architecture/domain-boundaries.md)
- [Database and data ownership](architecture/database-and-data-ownership.md)
- [API and event contracts](architecture/api-and-event-contracts.md)
- [Deployment architecture](architecture/deployment-architecture.md)

## Products

- [Product documentation index](products/README.md)
- [Nidus](products/nidus.md)
- [Haven](products/haven.md)
- [Vorax](products/vorax.md)
- [Logix](products/logix.md)
- [Corpus](products/corpus.md)

## Engineering and operations

- [Getting started](development/getting-started.md)
- [Development guide](development/development-guide.md)
- [Deployment runbook](operations/deployment-runbook.md)
- [Disaster recovery](operations/disaster-recovery.md)
- [Production operations](operations/production-operations.md)
- [Security architecture](security/security-architecture.md)
- [Security policies](security/security-policies.md)

## Reference

- [API reference](reference/api-reference.md)
- [Configuration reference](reference/configuration-reference.md)

## Documentation maintenance

Update the relevant authoritative document whenever code, configuration, deployment behavior, a contract, or an operational procedure changes. Do not create implementation-phase, audit-session, or pass-number documents. Keep historical release notes in `releases/CHANGELOG.md`; keep legal policies in `legal/`.
