# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial Dockerfile and private Compose deployment with persistent DNSSEC trust anchor, bounded logs, local healthcheck and integration tests.
- Native two-platform GHCR development workflow, optional Telegraf configuration and starter Grafana assets.
- Operational, security, compliance and delivery documentation.
- Project template agent conventions and Perl formatting configuration.
- First-release hardening checklist and additional runtime security assertions.

- Operator-only DNSSEC backup and restore with SHA-512 verification, local locking, and recovery documentation.

### Changed

- `make stop` retains the stopped container; `make clean` retains named volumes. Explicit interactive `make purge` is the destructive alternative.

- Adopt project-template-basic action priorities and Keep a Changelog format.
- Treat supply-chain and runtime hardening as 0.1.0 acceptance requirements, not later refactoring.
- Identify PowerDNS dnsdist as the optional candidate frontend, with authentication and traffic protection still unimplemented.

No version has been released or production-qualified by this source bundle. The
initial development snapshot was prepared on 2026-11-25.
