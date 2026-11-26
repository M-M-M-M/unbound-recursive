# Actions
Priorities for pending actions are ordered by the following numbers for the 11 first : 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟
Marked as new with 🆕
Paused with ⏸️
Pending a priority set slot with #️⃣
Once action is done, remove the priority number.

## 0.1.0 — security-first release gates

- [ ] Review runtime audit on both architectures and approve risk dispositions for the 25 HIGH IDs triaged in dev17; retain drill and guard; no exceptions. 0️⃣
- [ ] Review full host hardening reference, pinned Actions and transitive installers; qualify pinned base refresh and dev10 build. 1️⃣
- [ ] Retain approved dev17 scan and runtime-audit artifacts; dev16.1 both-platform re-scan reports reviewed, scheduled run confirmation remains. 2️⃣
- [ ] Retain dev12 operator qualification evidence and qualify on Linux amd64 production-like host. 3️⃣
- [ ] Verify non-root effective privileges, protected deployment paths, SELinux, resource limits, firewall and Docker routes. 4️⃣
- [ ] Complete production-like Linux numeric ownership/SELinux, trust anchor rollover and migration; dev12 local volume/bind recovery and purge reported successful. 5️⃣
- [ ] Probe IPv4/IPv6 exposure and unauthorized isolated lab clients; check source-IP NAT behavior. 6️⃣
- [ ] Audit installed package inventory and qualify signed deployment on isolated production-like host; dev12 manual CI workflow reported passed. 7️⃣
- [ ] Dev16.1 72 operations assertions passed locally; qualify real notification delivery, per-host absence, daily storage growth and deployment-specific permissions using dev17 runbook. 8️⃣
- [ ] Dev16.1 independent 10k phase PASS and both native CI comparisons reviewed. Run 24 h endurance, deterministic DNSSEC fixture on both platforms and host trust-anchor rollover/migration. 9️⃣
- [ ] Record all acceptance evidence and approve release before any production deployment. 🔟

## Later milestones

- [ ] 0.2.0: extend monitoring, health probes, alerting and retention tests. #️⃣
- [ ] 0.3.0: evaluate optional PowerDNS dnsdist frontend; preserve real client IPs, aggregate protocols/query types, bound cardinality and test reversible blocking. #️⃣
- [ ] 0.4.0: qualify authenticated DoH/DoT, client compatibility, TLS renewal and secret handling. #️⃣
- [ ] 1.0.0: full operational and recovery qualification for supported deployment profiles. #️⃣

## Completed

- [x] Dev16.1 operator: independent 10k soak PASS (5,993,142 valid, zero failed, 40/40 samples), 72 monitoring assertions, native comparison and re-scan successful. Both CI comparison and Trivy archives reviewed in dev17; 25 distinct HIGH IDs triaged, not formally accepted. Dev17 audit and DNSSEC fixture implemented; live gates pending.

- [x] Corrected dev16 local evidence: 362 unit, 72 monitoring operations assertions, 120 s sampling smoke, then 70 min full resource coverage and 9,432,913 valid answers, zero failed sends. 10k phase underdriven. Dev16.1 includes command-runner regression, detailed emission diagnostics, independent profiles and status classification; live validation pending.

- [x] Dev15 operator logs and JSON: 321 unit and existing live suites passed; all three CI workflows reported successful. 9,529,369 valid soak answers, zero failed sends, both DNS gates met; resource sampling missing last 23 minutes of first phase. Dev16 implements coverage/interrupt safeguards and opt-in operations checks; live qualification pending.

- [x] Dev14.2: operator logs show 408 passing assertions before randomized-name failure; corrected smoke 48/48 and all three workflows reported passed. Four supplied JSON reports reviewed; measured evidence in docs/PERFORMANCE-EVIDENCE.md. Dev15 implements the name fix and bounded async/soak profiles; live validation pending.

- [x] Dev14.1 local report: 7,645 attempts, 5,467 successes, 2,178 IP-limited counter increments, 355 unscheduled; recovery passed. Both native CI ACL audits passed; fixture healthcheck missing. Dev14.2 corrective implementation (live validation pending).

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

- [x] Dev12: operator reports successful signed deployment/rollback workflow using distinct dev8/dev12 indexes; full successful-run logs not supplied.
- [x] Dev13: implement manifest discovery, collection helper, dashboard extension and opt-in monitoring lab/CI; live results pending.
- [x] Dev13: operator reports all workflows successful, manual re-scan successful and visible Grafana graphs on macOS ARM64; latest logs not supplied.
- [x] Dev14: implement interactive monitoring lifecycle, usage snapshot, bounded synthetic forwarding benchmark, ACL/process audit and historical CVE inventory; live Docker tests and individual CVE review pending.

- [x] Dev14 M1: 225 unit, 1 integration, 18 volume, 22 bind, 48 monitoring, 25 network assertions passed; benchmark failed before load (`unsafe benchmark binding`).
- [x] Dev14.1: replace benchmark host-port access with an internal non-root client and verify actual network isolation; live qualification pending.
