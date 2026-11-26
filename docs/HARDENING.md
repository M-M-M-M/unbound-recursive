# Hardening from the first release

This is the canonical security acceptance checklist for version 0.1.0 and all
subsequent versions. It complements the [threat model](SECURITY.md) and
[infrastructure compliance](COMPLIANCE.md). No production deployment is approved
by this document. Status reflects source inspection, not live validation.

| Control | Source status | Required evidence before 0.1.0 release |
| --- | --- | --- |
| Non-root process | Configured | Effective UID/GID and no elevated capabilities |
| Read-only filesystem | Configured | Inspect mounts, writable state and tmpfs only |
| Least privilege | Configured | No privileged mode, host namespaces, devices or Docker socket; validate actual privileges |
| Private DNS | Configured | Loopback host bindings, independent IPv4/IPv6 refusal probes, bridge ACL and NAT verification |
| Resource and log budgets | Configured | Measured limits, restart and load/rotation tests |
| DNSSEC | Configured | Valid and bogus DNSSEC tests, persistent trust anchor, recovery |
| CI trust | Dev8 CI passed; review pending | Pin action revisions, review dependency changes and minimum token permissions; no secrets on untrusted PRs |
| Base image and Debian packages | Pinned in dev9; rebuild pending | Approved base digest; controlled refresh, record actual package versions and tested digests |
| Vulnerability scan | Dev8 CI passed | Trivy or reviewed equivalent, scan both platform images and block unacceptable findings; documented exceptions with expiry |
| SBOM and provenance | Dev8 CI passed; dev10 anonymous consumer gate pending | Generate per-platform inventories and attestations tied to exact digests |
| Signature | Dev8 CI and M1 Cosign passed; dev10 signature-type check pending | Sign released manifest; verify identity, issuer and digest on pull |
| Operator and host security | Pending | Approved administrative boundary, protected paths, firewall, SELinux, UID/GID, backup and rollback evidence |
| Monitoring boundary | Dev9 stats-file handoff; live test pending | Stats-only export or explicitly authorized administrative socket; no application access to Docker |
| Secrets | N/A core | No secrets needed; review approved secrets framework before adding authentication |

Development CI may publish test images; those are not releases. Until all
applicable gates have evidence and approval, do not use them on production
systems or expose a public listener. A vulnerability scan is not a substitute
for a threat model or operational verification. For findings without a fix,
record risk, exposure, mitigation, owner and review date; do not silently ignore
all unfixed findings. Re-scan released images as advisories change.

## New components

PowerDNS dnsdist is the proposed optional frontend. Keep it separate from
Unbound on a private backend network; enforce authentication before forwarding
when required, validate true source identity, limit connections and requests,
cap event volume/cardinality, and test false positives and recovery. No public
classic UDP DNS; application rate limiting cannot absorb a saturated uplink.
Apply the same runtime, build, release, logging and rollback controls to the
frontend before it is enabled. DoH/DoT and dynamic blocking are design work only.

The full external host-hardening reference has not yet been supplied. Reconcile
this checklist with it before release, document deviations and obtain approval.

See [supply-chain security](SUPPLY-CHAIN.md) for the implemented CI policy and
verification commands. Review and qualify all new controls before release.

### Runtime dependency minimization (dev8)

Use Debian `ldnsutils` for local DNS diagnostics rather than the BIND client
stack. Live integration checks the installed package inventory and fails on
BIND, LMDB or libxml2 packages. Any intentional future addition requires a
review of its purpose, reachable code, vulnerability exposure and updated
policy tests. The full Trivy gate remains mandatory; a smaller dependency
set is not proof of absence of vulnerabilities. Review the per-architecture
SBOM and image-size evidence before promotion.
