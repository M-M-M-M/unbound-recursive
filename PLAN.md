# Delivery plan

The goal is independent, private DNS resolution with reproducible operations.
Versions are targets, not published releases. Hardening is a design constraint
and a release gate from the first version. See [hardening](docs/HARDENING.md)
and [TODO](TODO.md) for acceptance and prioritized work.

| Milestone | Scope | Acceptance gate |
| --- | --- | --- |
| 0.1.0 | Debian slim, recursive Unbound, DNSSEC, non-root, bounded resources/logs, basic telemetry, GHCR and supply-chain security | Native arm64/amd64 tests; private listeners; persistent trust anchor and tested backup/restore; reviewed dependency pins, CVE gate, SBOM, signature/provenance; host preflight and safe rollback |
| 0.2.0 | Extended monitoring and operational tooling | Telegraf/Grafana, bounded data retention, alerts, counter/reset handling and recovery tests |
| 0.3.0 | Optional PowerDNS dnsdist frontend | Private backend; verified source identity; bounded per-IP/protocol aggregation; rate limits and reversible blocking tests |
| 0.4.0 | Authenticated DoH/DoT | Client compatibility matrix, rotation, fail-closed auth, TLS and HTTP publication checks; no public classic DNS |
| 1.0.0 | Full production qualification | Complete runbook, recovery exercise, separate failure domains, measured resources, approved compliance and security review for supported profiles |

## Decisions

- Prefer a small Unbound-only core; PowerDNS dnsdist is the candidate optional
  frontend. Review security before adding each component, not after release.
- Use official Debian packages; compare Debian security tracker and upstream
  advisories. Do not assume Debian always patches faster than Alpine.
- GHCR pull-based delivery. No server names, SSH credentials or private
  configuration in GitHub; each server independently approves and pulls a digest.
- Logs bounded and query logging disabled by default. Design source-IP metrics
  without unbounded InfluxDB series cardinality or sensitive query history.
- Prefer the existing monitoring, secrets, administrative and TLS infrastructure.
  No replacement stack without a justified requirement and approval.
- Development snapshots may be built and published for isolated testing; neither
  a green development workflow nor a mutable tag is a production authorization.
- Prefer a stats-only file handoff to Telegraf over sharing Unbound's
  administrative control socket. Keep timestamp/retention and failure alerts
  explicit; collect client-level data only in a later bounded frontend.
- Digest updates are initiated by the operator on each host. The operator helper
  verifies signatures/attestations using Cosign without GitHub CLI, records a local journal, backs up DNSSEC
  and tests before accepting; configuration/state migrations require review.

- Keep named-volume compatibility; prefer a dedicated bind directory where host
  backup integration is required. Confirmed purge destroys the active trust anchor in both modes; in bind mode it deletes only root.key, never the directory or unrelated files. Validate
  both state profiles and migrations before release.

## Next development snapshots

- dev13: operator reports monitoring CI, manual re-scan and macOS Grafana
  visualization successful; retain reports and verify scheduled execution.
- dev14: interactive lab, bounded synthetic load and resource reporting,
  native ACL smoke tests; M1 tests passed except benchmark initialization.
- dev14.1: remove host port publication, use a separate internal client,
  qualify the revised load path on macOS and native CI; review current HIGH CVEs.
  local run completed, but IP limiting accounted for all failed attempts;
  both CI runners failed before load due to the disabled fixture healthcheck.
- dev14.2: functional fixture healthcheck, paced and separated load profiles,
  persistent TCP, diagnostic retention and post-run Grafana import. Qualify
  live smoke and the opt-in profiles; retain reports and review current CVEs.
  DNSSEC-negative fixture, longer soak and production-like host audit remain open.
- dev15: production-like deployment, state migration and release-gate review.
- 0.1.0-rc.1 / 0.1.0: only after explicit acceptance; snapshot numbers are not
  stable release promises.

- Treat 10,000 q/s as an isolated synthetic performance target, not a record or
  Internet recursion guarantee. Prioritize stability, recovery, actual alerts
  and release security gates; leave exploratory higher-rate tests optional.
