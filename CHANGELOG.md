# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added (dev17)

- Record the 26 November both-platform scan inventory and individual HIGH
  triage, package dependency/file evidence, LDNS decision and native performance
  comparisons; retain the existing CVE gate and excluded-package guard.
- Audit installed dependency fields, actual dynamic linkage, build options,
  effective configuration and simulated LDNS removal in a private local image.
- Add isolated signed/tampered DNSSEC fixture, positive/negative/CD controls,
  response-parser regressions and native build qualification before publication.
- Add read-only lab storage/source-count snapshots, notification acceptance
  instructions and representative Linux host runbook; actual delivery and
  long-run storage measurements remain operator gates.
- No production image recipe, resolver configuration, deployment or rate-limit
  changes; no new runtime packages or external notification destinations.

### Fixed (dev16.1)

- Scope File::Temp command capture handles to each invocation; regressions
  exercise 200 commands and 40 exceptional exits under a 64-descriptor limit.
- Record per-reason async UDP skipped slots and dispatch/wakeup delays without
  catch-up bursts; retain exact schedule accounting and unchanged thresholds.
- Add independent 1,000/10,000 q/s soak profiles and explicit PASS,
  INCONCLUSIVE and FAIL qualification, with failure precedence and saved
  recovery evidence. Both non-pass outcomes fail Make.
- Expose Grafana polling and cleanup diagnostics; add a retention-only test.
- Record corrected dev16 operator evidence; no production image, security
  policy, rate limit, or CI runner architecture changes.

### Added (dev16)

- Validate resource records, journal Docker stats errors, retry missing roles,
  track atomic heartbeats and abort long phases on missing samples or timing gaps.
- Require complete sampling coverage and observed container health for soak
  gates; publish completed phases atomically and add a two-minute sampling check.
- Add opt-in lab freshness provisioning, alert firing/recovery and retention
  fixture tests; native comparison workflow input and release evidence checklist.
- Record dev15 measured endurance and its incomplete resource evidence. Current
  CVE reports, notification delivery, physical storage growth and host review
  remain open. No production configuration or policy change.

### Added (dev15)

- Normalize temporary Docker repository names, avoid removal of unbuilt images,
  and cover underscore/separator regressions.
- Add bounded asynchronous UDP for smoke, rate-limit and opt-in endurance
  profiles; fixed-size latency histograms, independent timeouts, progress and
  retained resource samples. Keep the short baseline/stress comparison.
- Add 60-minute/10-minute and separate 24-hour soak profiles and explicit
  acceptance thresholds; long runs are manual, never automatic CI jobs.
- Record measured dev14.2 evidence; document alert delivery and retention
  qualification, and add read-only lab retention metadata inspection.
- Production resolver, deployment and CVE policy unchanged. Release gates
  remain open pending operator evidence.

### Fixed (dev14.2)

- Add a real, local-only DNS fixture healthcheck (port 5354 and exact A answer)
  and client process healthcheck for Compose `up --wait`. Retain startup logs,
  errors and completed phase results even on failed CI runs.
- Separate paced baseline and stress profiles (limits disabled only in the
  disposable configuration) from production-like and rate-limit profiles.
  Record requested, attempted, sent, skipped, failed and successful queries,
  target versus actual offered rates, TCP EOF/timeout/I/O outcomes and
  persistent TCP; add 10/30/60-second phases and recovery probes.
- Add opt-in post-run report import and a separate five-panel Grafana dashboard
  in the existing disposable monitoring lab; add live integration checks.
  No connection between benchmark and monitoring networks, no production data.
- Record operator-provided dev14.1 local report and both CI startup failures.
  Production Dockerfile, resolver configuration and security policy unchanged.

### Fixed (dev14.1)

- Replace host loopback port publication with a dedicated non-root Perl client
  on the internal benchmark bridge. No ports are published; check the actual
  network membership, endpoints, namespace and bindings before sending traffic.
- Keep the load generator in a local-only, separately built pinned Debian
  image. Collect worker timings in the client, and label resource samples
  for the resolver and client separately in report schema 2.
- Add network-guard regressions and real multi-worker loopback socket tests.
  Record dev14 macOS evidence: 339 assertions passed, benchmark initialization
  failed with `unsafe benchmark binding`; new Docker qualification pending.
- No production image, resolver configuration, CVE policy or storage change.

### Added (dev14)

- Add interactive, isolated Grafana lab lifecycle and InfluxDB disk usage command.
- Add core Perl synthetic loopback UDP/TCP benchmark with response validation,
  bounded concurrency, warm/cold cache and post-load recovery checks,
  JSON/CSV/Markdown reports and sampled Docker resources.
- Add isolated production ACL test and effective process security assertions;
  qualify smoke tests in native AMD64 and ARM64 CI.
- Inventory the 25 historical dev8 HIGH CVEs individually; current advisory
  and reachability review remains open. No CVE policy or production image change.
- Record operator-reported dev13 CI, manual re-scan and macOS Grafana success.

### Added (dev13)

- Add `make digest` for index-only discovery, early multiarchitecture validation,
  and previous/published index digest summaries in the publication workflow.
- Reuse structural index validation in the manual/scheduled re-scan resolver.
- Add locked stats-only collection helper, explicit timestamp precision and a
  disposable native monitoring integration lab with InfluxDB 2.x, Telegraf and
  Grafana, plus an independent AMD64 CI workflow.
- Extend the Flux dashboard with freshness, uptime, cache ratio and selected
  response/query types; document alert thresholds, missing data and reset limits.
- Record operator-reported dev12 qualification; monitoring lab and re-scan
  execution still require real Docker/CI evidence. No change to CVE policy.

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
