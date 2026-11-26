# unbound-recursive

A self-hosted recursive DNS resolver based on Unbound and Debian slim. No public
recursive forwarder is used. The default deployment is private, not a public
DNS service. DNSSEC authenticates signed DNS data; it does not encrypt recursion.

**Status: 0.1.0-dev10 — Cosign-only verification and disposable deployment qualification, not production-qualified.**
Dev6 passed macOS M1 recovery tests; dev7 CI passed functional tests but was
blocked by four CRITICAL findings. Dev8 replaces the in-container BIND DNS
client with LDNS drill, retaining Debian upgrades, the CVE policy and empty
exception register. Dev8 CI passed on both architectures, signed GHCR publication
and operator Cosign verification succeeded. Dev9 pins the tested Debian base,
adds digest-only update/rollback and stats-file handoff. Dev10 removes the
GitHub CLI requirement, gates promotion on anonymous Cosign verification and
adds a manually dispatched live update/rollback qualification. Live
qualification and host review remain required. DoH,
DoT, authentication, per-client monitoring and automated blocking remain planned.
Hardening is mandatory from 0.1.0; the outstanding supply-chain checks are
release blockers, not deferred to a later version.

## Quick start (macOS M1 / Linux)

Requirements: Docker Engine or Docker Desktop, Compose v2 (2.24.4+ for optional
monitoring override), Make or the equivalent Compose commands. Outbound UDP and
TCP port 53 to authoritative DNS servers, correct clock, and working registry
access for image pulls. Check port 1053 and subnet 172.30.53.0/24 are free first.

```sh
make build
make start
make test
make stats
# macOS / hosts with dig installed:
dig @127.0.0.1 -p 1053 example.org A +dnssec
make stop
```

The default Compose file publishes TCP and UDP only on IPv4 loopback at port
1053; no public listener. Port 1053 avoids the usual macOS mDNS port 5353.
The container listens on 5353, uses UID/GID 10001 (container-only proposed ID),
no Linux capabilities, read-only root, bounded resources and rotated logs.
Docker's own privileges are separate. The bridge is IPv4-only by design in this
first version. AAAA records can still be resolved. Do not attach untrusted
containers to the resolver network. Never change the bind to `0.0.0.0`.

To test a published image (only after CI has succeeded and package visibility
has been reviewed), without building locally:

```sh
cp .env.example .env
docker compose pull
docker compose up -d --wait
make test
```

`make stop` stops the local container without removing it. `make clean` removes
containers and networks but preserves the DNSSEC state volume. Only `make purge`
removes the volume, after interactive confirmation; see the
[impact and recovery procedure](docs/DEPLOYMENT.md#state-backup-and-restoration).
To back up an existing local instance, stop it first (do not clean it):

```sh
make stop
make backup-state
make start
```

Backups default to the ignored `backups/` directory for local tests; use an
approved protected external backup location in production. `make restore-state`
requires `BACKUP_SET` and explicit confirmation; it can recreate a stopped
container and volume without starting the resolver. Use `make test-state`
(Perl and `prove`) to exercise destructive recovery in a disposable Compose project. The healthcheck uses `drill` from Debian `ldnsutils` to test a local record,
not upstream reachability. The integration script tests UDP, TCP, live DNSSEC
and cache behavior and rejects installed BIND, LMDB or libxml2 packages.
`dig` remains optional on the host; it is not shipped in the image.

## Deployment and operations

The registry is `ghcr.io/m-m-m-m/unbound-recursive`. The workflow builds natively
for amd64/arm64, tests each platform image and assembles a manifest from their
published digests. Daily builds refresh Debian packages; they do not update
production automatically. Review CI, scan results and pin the approved manifest
digest before deploying. The [vulnerability policy](security/README.md) blocks fixable HIGH/CRITICAL and unapproved CRITICAL findings; unfixed HIGH findings warn by default. Direct GitHub Actions are SHA-pinned; Trivy, SBOM, provenance and Cosign
checks passed in dev8 CI. Debian base is pinned to the multiarch digest used
in dev8; Dependabot proposes reviewed refreshes. See [supply-chain security](docs/SUPPLY-CHAIN.md).
The development workflow may publish test snapshots only; do not treat `latest`
as a qualified production release.

Use the approved operator account and protected deployment directory; keep
site-specific addresses, FQDNs, paths and secrets in local inventory, not this
public repository. No actual deployment has been inspected. See
[deployment](docs/DEPLOYMENT.md) for digest-based updates, rollback, backup,
permissions and acceptance checks. See [verified upgrades](docs/UPGRADING.md)
for `scripts/deploy.pl verify latest`, explicit digest updates and rollback.
No remote SSH deployment or GitHub CLI/token is required for public-image
verification and pull. Cosign 3.1.4 (or a reviewed compatible newer version)
verifies the signature, SLSA provenance and each platform SBOM from GHCR.
See [qualification](docs/UPGRADING.md#qualification-before-production) for the
manual CI workflow and disposable lab test.

## Monitoring and security

- [Monitoring and logs](docs/MONITORING.md): preferred stats-only file handoff, optional native Telegraf input example,
  starter InfluxDB 2/Flux Grafana dashboard, log rotation and limitations.
- [Security and encrypted DNS](docs/SECURITY.md): threat model, private access,
  client authentication design and future HAProxy/TLS integration.
- [Hardening and release gates](docs/HARDENING.md): implemented controls,
  required checks and unqualified items.
- [Infrastructure compliance](docs/COMPLIANCE.md): requirements, evidence,
  unknowns and conditional checks.
- [Plan](PLAN.md), [TODO](TODO.md), [changelog](CHANGELOG.md),
  [security reporting](SECURITY.md), [validation evidence](docs/VALIDATION.md).

The initial resolver needs no secrets, web publication, TLS certificates or host
cron. Future authenticated DoH will use the approved existing secret workflow
and HTTP infrastructure. Do not publish a recursive UDP resolver to the Internet.

Project code/configuration: MIT (see LICENSE). Unbound, Debian and other bundled
packages retain their own licenses; see package copyright files in the image.

## Development tests

Use Perl 5.26 or newer (core modules only), `prove`, POSIX shell and the
platform's `script` utility (BSD on macOS, util-linux on Linux). Perl and
`prove` run on the development/CI host, not in the resolver image.

- `prove -v tests/*.t` or `make test-unit`: offline regression tests; live tests
  are skipped unless explicitly enabled.
- `make test`: integration tests against the running local test instance.
- `make test-state`: opt-in destructive recovery in a disposable Compose project
  on a test Docker host; requires the local development image.
- `make test-all`: all tests (running local test instance and Docker required).

The state tests use a real pseudo-terminal via `script` to exercise operator
confirmation without bypassing the production safety checks. Do not enable
Docker tests on production hosts.

When upgrading an existing dev4 checkout by copying this bundle, remove the
four obsolete tracked Python files explicitly (`git rm`); copying files with
rsync does not remove them. See the changelog for their paths.
