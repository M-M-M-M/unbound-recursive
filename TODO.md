# Actions
Priorities for pending actions are ordered by the following numbers for the 11 first : 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟
Marked as new with 🆕
Paused with ⏸️
Pending a priority set slot with #️⃣
Once action is done, remove the priority number.

## 0.1.0 — security-first release gates

- [ ] Review full host hardening reference when supplied; record exceptions and approvals. 0️⃣
- [ ] Review pinned Actions and transitive installers; pin approved base image digest and define controlled refresh. 1️⃣
- [ ] Qualify configured Trivy gate, per-platform SBOM attestations, signed manifest and provenance; verify on pull and test scheduled re-scan. 2️⃣
- [ ] Re-qualify dev6 on macOS M1, both CI architectures and Linux amd64 production-like host; verify signed GHCR publication. 3️⃣
- [ ] Verify non-root effective privileges, protected deployment paths, SELinux, resource limits, firewall and Docker routes. 4️⃣
- [ ] Verify first-start state permissions, trust anchor persistence/rollover and restart. 5️⃣
- [ ] Probe IPv4/IPv6 exposure and unauthorized isolated lab clients; check source-IP NAT behavior. 6️⃣
- [ ] Qualify dev6 recovery after total purge using make test-state; verify permissions and timing, digest-based deployment and rollback. 7️⃣
- [ ] Qualify least-privilege stats-only collection or obtain explicit approval for administrative socket access; test Telegraf and Grafana. 8️⃣
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
- [x] Correct absent-container restoration, verify persisted SHA-512 and add isolated live recovery test (live execution pending).
- [x] Configure SHA-pinned workflow, Trivy, SBOM/provenance attestations, Cosign signature and daily re-scan (CI qualification pending).
- [x] Convert Python tooling to core Perl and TAP tests; wire prove into Make and CI (offline tests passed; live and macOS PTY qualification pending).

- [x] Synchronize test confirmation with the actual PTY prompt and keep stdin open; add delayed/split prompt regression tests (Linux offline validated; macOS re-test pending).
