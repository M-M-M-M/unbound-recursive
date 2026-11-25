# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed (dev6)

- Wait for the interactive prompt before sending test confirmations and keep
  the PTY input pipe open until the child exits. Fix the suspected cause of
  BSD/macOS `script` cancelling valid confirmations in dev5; preserve the
  production operator safeguards.
- Add delayed/split prompt regression tests for correct and incorrect input.

### Changed (dev5)

- Replace Python vulnerability gate and recovery test runners with core Perl
  (5.26+) and TAP/Test::More; use prove in local Make targets and CI.
- Separate offline tests from explicitly enabled live Docker tests; keep the
  actual operator confirmation checks and use a platform pseudo-terminal.
- Remove `scripts/vulnerability-gate.py`, `tests/vulnerability-gate.py`,
  `tests/state-mock.py`, and `tests/state-live.py`.

### Added

- Isolated live recovery test, Trivy vulnerability gate and per-architecture reports and CycloneDX SBOMs.
- SHA-pinned GitHub Actions, GitHub attestations, keyless Cosign manifest signing and verification before promotion, and daily published-image re-scan.
- Supply-chain policy and verification documentation; restore local ignore rules for backup and environment files.

- Initial Dockerfile and private Compose deployment with persistent DNSSEC trust anchor, bounded logs, local healthcheck and integration tests.
- Native two-platform GHCR development workflow, optional Telegraf configuration and starter Grafana assets.
- Operational, security, compliance and delivery documentation.
- Project template agent conventions and Perl formatting configuration.
- First-release hardening checklist and additional runtime security assertions.

- Operator-only DNSSEC backup and restore with SHA-512 verification, local locking, and recovery documentation.

### Fixed

- Restore after complete purge without a prior resolver start; verify restored bytes by SHA-512.

### Changed

- Separate unprivileged native qualification jobs from the main-only publishing job and transport tested images with verified checksums and IDs.

- `make stop` retains the stopped container; `make clean` retains named volumes. Explicit interactive `make purge` is the destructive alternative.

- Adopt project-template-basic action priorities and Keep a Changelog format.
- Treat supply-chain and runtime hardening as 0.1.0 acceptance requirements, not later refactoring.
- Identify PowerDNS dnsdist as the optional candidate frontend, with authentication and traffic protection still unimplemented.

No version has been released or production-qualified by this source bundle. The
initial development snapshot was prepared on 2026-11-25.
