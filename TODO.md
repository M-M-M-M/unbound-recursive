# Actions
Priorities for pending actions are ordered by the following numbers for the 11 first : 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟
Marked as new with 🆕
Paused with ⏸️
Pending a priority set slot with #️⃣
Once action is done, remove the priority number.

## 0.1.0 — security-first release gates

- [ ] Review all remaining HIGH CVEs and reachable code; LDNS CVE-2026-10846 initial triage recorded; no exceptions. 0️⃣
- [ ] Review full host hardening reference, pinned Actions and transitive installers; qualify pinned base refresh and dev10 build. 1️⃣
- [ ] Qualify dev10 anonymous consumer gate, provenance and both platform SBOM verifications; run revised scheduled/manual re-scan. 2️⃣
- [ ] Qualify dev12 on macOS M1, both CI architectures and Linux amd64 production-like host. 3️⃣
- [ ] Verify non-root effective privileges, protected deployment paths, SELinux, resource limits, firewall and Docker routes. 4️⃣
- [ ] Verify both state backends: native bind and volume recovery (including confirmed purge and symlink refusal), Linux numeric ownership/SELinux, Docker Desktop UID mapping, trust anchor persistence/rollover, migration and restart. 5️⃣
- [ ] Probe IPv4/IPv6 exposure and unauthorized isolated lab clients; check source-IP NAT behavior. 6️⃣
- [ ] Audit installed package inventory; run dev10 manual live deployment qualification on both native CI runners and isolated host, including failure recovery. 7️⃣
- [ ] Qualify stats-only collection, Telegraf, InfluxDB and Grafana including stale data alerts. 8️⃣
- [ ] Add deterministic DNSSEC-negative fixture and bounded resource/load tests. 9️⃣
- [ ] Record all acceptance evidence and approve release before any production deployment. 🔟

## Later milestones

- [ ] 0.2.0: extend monitoring, health probes, alerting and retention tests. #️⃣
- [ ] 0.3.0: evaluate optional PowerDNS dnsdist frontend; preserve real client IPs, aggregate protocols/query types, bound cardinality and test reversible blocking. #️⃣
- [ ] 0.4.0: qualify authenticated DoH/DoT, client compatibility, TLS renewal and secret handling. #️⃣
- [ ] 1.0.0: full operational and recovery qualification for supported deployment profiles. #️⃣

## Completed

- [x] Bootstrap Debian slim recursive Unbound container, local Compose and DNSSEC state.
- [x] Add non-root defaults, bounded logs, healthcheck and initial integration tests.
- [x] Draft multiarchitecture GHCR workflow, Telegraf/Grafana examples and operations documentation.
- [x] Integrate project-template-basic conventions and make hardening a first-release gate.
- [x] Separate safe cleanup and confirmed purge; add DNSSEC state backup/restore tooling and document operational impact (previous snapshot: backup, clean, purge and stopped-container restore passed on M1).
- [x] Extend runtime hardening assertions in integration tests (passed on previous snapshot on M1).
- [x] Previous snapshot: native M1 build/integration, GHCR amd64/arm64 publication and ARM64 image execution validated by operator.
- [x] Correct absent-container restoration, verify persisted SHA-512 and add isolated live recovery test (dev6 live execution passed on M1 and CI).
- [x] Configure SHA-pinned workflow, Trivy, SBOM/provenance attestations, Cosign signature and daily re-scan (dev8 CI passed; re-scan pending).
- [x] Convert Python tooling to core Perl and TAP tests; wire prove into Make and CI (dev6 tests passed on M1 and CI).

- [x] Synchronize test confirmation with the actual PTY prompt and keep stdin open; add delayed/split prompt regression tests (Linux and macOS validated).

- [x] Record dev6 operator qualification: 47 offline assertions and 18 live recovery assertions passed on macOS M1; both CI architectures reached the CVE gate.
- [x] Upgrade base Debian packages at build time; add per-platform package inventory and configurable CVE gate with exact expiring exceptions, summary and Perl regression tests (dev7; live CI pending).
- [x] Record dev7 CI evidence: Debian libzstd1 update removed the fixable finding; four unapproved CRITICAL findings still blocked publication on both architectures.
- [x] Replace BIND diagnostic utilities with LDNS drill; adapt health and integration checks, add dependency regression guard, offline TAP tests and per-platform CI image-size evidence (dev8; live CI passed).

- [x] Dev8 CI on amd64/arm64 passed dependency guard, Trivy gate (0 CRITICAL, 0 blockers), SBOM/provenance, Cosign and GHCR promotion; operator Cosign verification passed. ARM64 size reduced from 152544990 to 142298403 bytes.
- [x] Pin the tested Debian index digest; add reviewed-refresh docs and immutable re-scan selection (dev9, CI pending).
- [x] Implement core Perl verified update/rollback and stats-only file export with offline TAP tests; live operator qualification remains pending.

- [x] Remove GitHub CLI from verification; enforce an actual image signature, exact identity, signed hosted-runner provenance policy and per-platform SBOMs using Cosign; add anonymous pre-promotion gate and opt-in live update/rollback qualification (dev10; live checks pending).

- [x] Add optional dedicated bind-state source, preflight and mount mismatch guards, non-destructive bind purge, backup/restore support, and native CI bind lab (dev11; offline tests pass, live qualification pending).

- [x] Align purge semantics across storage modes; bind deletes only the active anchor after confirmation, with offline tests and live recovery lab (dev12; live qualification pending).
