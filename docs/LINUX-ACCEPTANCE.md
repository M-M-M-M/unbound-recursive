# Representative Linux host acceptance — dev17

Use a disposable or explicitly approved non-production Linux host, on each
supported architecture where practicable. Record date, actual OS/kernel,
Docker/Compose version, approved immutable manifest and image IDs, source
revision and evidence in protected operator records; do not commit addresses,
mount paths, credentials or raw host inspection output to the public project.
This runbook complements [hardening](HARDENING.md) and [deployment](DEPLOYMENT.md).

## Preflight and isolation

- Confirm host patching, clock synchronization, Docker Engine support,
  Compose version and protected operator access. Inspect `docker info`,
  `docker version`, `docker compose version`, `uname -r`, `timedatectl status`.
- Review host firewall and Docker-managed rules (`nft list ruleset` or the
  host's applicable firewall tooling) with authorized administrative access.
  Verify both IPv4 and IPv6, including forwarding/NAT chains. Do not change
  the firewall from this checklist. Confirm port 1053 and the configured
  bridge subnet are free; do not publish on public addresses.
- Use the existing documented protected bind-state directory or named
  volume. Check numeric ownership and effective UID mapping, parent path
  traversal, filesystem permissions, SELinux enforcing status/labels where
  applicable. Do not disable SELinux or grant broad privileges as a workaround.
- Inspect the running test instance (`docker compose ps`, `docker compose
  port unbound 5353`, `docker compose port --protocol udp unbound 5353`,
  `ss -lntup`). Confirm loopback-only publications, no IPv6 public listener,
  no extra mounts, no Docker socket or host namespaces. Inspect PID 1
  `Uid`, `Gid`, `CapEff`, `NoNewPrivs`, `Seccomp` in `/proc/1/status` and
  effective Docker resource/log limits. Compare with source hardening.

## Local qualification and exact published artifact

Run local test suites only in the development checkout on the test host:

```sh
make test-unit
make build
make start
make test
make test-state
make test-state-bind
make test-network
make test-dnssec
make audit-runtime
make test-monitoring-operations
make benchmark-soak-check
```

The DNSSEC fixture uses no external network, no production state and ephemeral
keys. `make test` additionally checks live DNSSEC with public authoritative
servers; external DNS failure is not a DNSSEC pass. Probe authorized loopback
UDP/TCP and unauthorized isolated peers; from an independently authorized
external test machine check the designated test host has no public DNS
listener on TCP/UDP 53 or 1053 over either IP family. A UDP timeout alone is
not proof of a firewall policy; correlate with listener and firewall evidence.
Inspect NAT behavior/source IP separately before relying on IP-based ACLs.
Never expose the service to obtain a test result.

Resolve and approve the manifest once, verify it with `scripts/deploy.pl verify`
per the deployment guide, preserve SBOM/provenance and both-platform scan
reports, and exercise signed update/rollback using the documented disposable
qualification. Verify the actual pulled digest, state preservation and recovery.
Local builds and published images may differ; local benchmark results alone do
not certify the exact published image. Qualify numeric bind ownership,
SELinux, trust-anchor backup/migration/rollover and restart on this host.
Never purge a production state volume as an acceptance exercise.

## Sign-off

Record results independently for permissions, network/firewall, DNSSEC,
backup/restore, digest verification, rollback, resource/log limits, actual
notification delivery and observed storage growth. Run the separate 24 h
endurance test on an uninterrupted machine; no production traffic generated.
Review both runtime audit files and the current HIGH findings, named owner,
mitigations and review dates. Do not tag or deploy the RC until the operator
reviews all remaining gates in [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md).
