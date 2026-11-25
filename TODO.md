# Actions
Priorities for pending actions are ordered by the following numbers for the 11 first : 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟
Marked as new with 🆕
Paused with ⏸️
Pending a priority set slot with #️⃣
Once action is done, remove the priority number.

## 0.1.0 — security-first release gates

- [ ] Review full host hardening reference when supplied; record exceptions and approvals. 0️⃣
- [ ] Pin and review trusted GitHub Actions and base image digests; define controlled refresh. 1️⃣
- [ ] Add Trivy vulnerability gate, per-platform SBOM, signed manifest and provenance; verify on pull. 2️⃣
- [ ] Run native macOS M1 and Linux amd64 builds and integration tests; verify CI and GHCR visibility. 3️⃣
- [ ] Verify non-root effective privileges, protected deployment paths, SELinux, resource limits, firewall and Docker routes. 4️⃣
- [ ] Verify first-start state permissions, trust anchor persistence/rollover and restart. 5️⃣
- [ ] Probe IPv4/IPv6 exposure and unauthorized isolated lab clients; check source-IP NAT behavior. 6️⃣
- [ ] Validate digest-based deployment, rollback and DNSSEC backup/restore in isolated instances; exercise purge confirmation, corrupt backup rejection, state persistence after clean and recovery timing. 7️⃣
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
- [x] Separate safe cleanup and confirmed purge; add DNSSEC state backup/restore tooling and document operational impact (live qualification pending).
- [x] Extend runtime hardening assertions in integration tests (execution still pending).
