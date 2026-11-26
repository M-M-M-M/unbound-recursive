# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed (dev12)

- Make confirmed purge destroy active DNSSEC state in both storage modes.
  Bind purge stops the resolver and removes only root.key via the constrained
  non-root helper, preserving the directory, unrelated files and backups.
  Refuse unsafe anchor types, mount mismatches and active shared mounts.
- Add simulated regressions and extend the live bind recovery lab with
  symlink refusal, actual deletion, unrelated file retention and repeated purge.

### Added (dev11)

- Optional dedicated host bind directory for `/state`, preserving named-volume
  compatibility. Add mount preflight, source checks and bind-mode recovery lab.
- Support stopped bind state backup/restore using the constrained helper. Keep
  the host directory and all volumes on confirmed bind-mode purge; never delete
  arbitrary host paths. Reject mismatched mounts and implicit storage migrations.
- Permit a fixed state source in verified image updates, record it in the local
  deployment journal and refuse unexpected changes. Document storage setup,
  migration, backup, SELinux and Docker Desktop qualification.
- Add offline TAP regressions and native CI bind-state recovery coverage. Real
  bind mount, macOS mapping and Linux deployment remain to be qualified.

### Changed (dev10)

- Replace GitHub CLI verification with Cosign 3.1.4 for signatures, index
  provenance and both CycloneDX platform attestations. Require an actual v3
  image signature; check signed source workflow/ref and hosted-runner provenance.
- Require a separate anonymous read-only consumer check before promotion;
  keep GitHub-generated OCI attestations and the existing CVE policy.
- Add an opt-in native dual-architecture deployment qualification workflow and
  TAP suite for real update, deliberately failed acceptance and automatic rollback,
  explicit rollback, backup checksums and real stats export. No production access.
- Extend mocked verification tests and document compatibility and trust limits.

### Added (dev9)

- Operator-only core Perl digest verification, explicit update and rollback;
  verify Cosign, index provenance and both platform SBOMs before any update.
  Back up stopped DNSSEC state, retain a local journal, test the candidate and
  attempt automatic image-only rollback on failure. Same default profile and
  compatible state schema only; no unattended deployment or automatic purge.
- Stats-only timestamped file exporter, optional Telegraf file input and
  separate Flux dashboard; no administrative socket or Docker access for Telegraf.
- TAP regressions for both tools; update/recovery and vulnerability review docs.

### Changed (dev9)

- Pin Debian to the multiarch base digest recorded in successful dev8 CI;
  Dependabot continues to propose controlled refreshes.
- Resolve the daily re-scan digest once across both architectures; allow manual
  re-scan of an approved deployed digest.
- Record dev8 CI publication, no blocking CVEs, operator Cosign verification
  and ARM64 image size reduction. Preserve CVE policy and empty exception list.


### Changed (dev8)

- Replace `bind9-dnsutils` with Debian `ldnsutils` (`drill`) to reduce
  runtime dependencies; retain the existing CVE gate and empty exception register.
- Adapt local health and DNSSEC/cache integration probes to drill, with bounded
  execution time and strict local answer validation.
- Add installed-package regression guard against BIND, LMDB and libxml2,
  offline TAP tests for the probe and guard, and CI image-size evidence.
- Record dev7 CI findings; actual dev8 image dependency closure and CVE results
  remain to be qualified.

### Changed (dev7)

- Upgrade installed Debian packages before installing resolver dependencies.
- Keep full Trivy findings; block fixable HIGH/CRITICAL and unapproved CRITICAL;
  warn on unfixed HIGH by default, with an optional stricter policy.
- Add exact, expiring Debian package exceptions (empty by default), unique-ID
  and package finding counts, GitHub step summaries and package inventories.
- Extend core Perl TAP tests and document the dev6 qualification and CI gate.
  No vulnerability is individually waived in this snapshot.


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
