# Deployment, operations and recovery

These are illustrative commands for an authorized operator, not an installer.
The actual inventory, FQDN, deployment path, host accounts and permissions must
be recorded in protected local documentation, never in the public repository.
For a future HTTP service, follow the local hosting path convention (including
`sites/`), not an arbitrary migration of existing services.

## Preflight

Use the existing ops administrative mechanism with actual approved privileges.
Docker access is effectively host administration; no application user joins its
group or receives its socket. Check Docker/Compose versions, architecture,
SELinux, available UID/GID and numeric volume ownership, resource budget, NTP,
port collisions, bridge conflicts, outbound TCP/UDP 53 and firewall policy.
Example commands for an authorized Linux operator: `ss -lntup`, `ip route`,
`docker network ls`, `docker compose version`, `getenforce` (if available).
Inspect relevant networks and both IP families. Require current Docker (older
versions have loopback publication exposure issues on adjacent L2 networks).
Don't change firewall rules or system resolv.conf automatically.

Separate approved release code and read-only config, runtime socket directory,
state and backup. Ensure no app-writable parent, symlink, env or Compose input
can influence an administrative command. Use a fixed working directory and
explicit trusted Compose/env files; review local overrides before each update.
Use an admin-protected .env (contains image digest and port, no secrets here).

## Install / pull update

Dev9 adds a guarded operator-only script for the default profile. Follow
[verified updates and rollback](UPGRADING.md) for first install, digest
verification, updates, rollback and the failure recovery runbook. The manual
procedure below remains available for reviewed emergency operations.

From the protected release directory, copy compose.yaml and .env.example.
Replace `UNBOUND_IMAGE` in .env with `ghcr.io/m-m-m-m/unbound-recursive@sha256:<approved manifest digest>`.
Confirm architecture and package visibility in GHCR. Use tested digest rather
than `latest`; compare digest to the qualified build, verify security reports
and signature using [supply-chain verification](SUPPLY-CHAIN.md). Dev8 CI and Cosign verification succeeded, but dev9 operator tooling and host
qualification remain release blockers: the commands
below are for isolated qualification only until the [hardening gates](HARDENING.md)
are satisfied and an operator has approved a release.

```sh
docker compose config --quiet
docker compose pull
docker compose up -d --wait
./tests/integration.sh
```

Before updates, retain the prior approved Compose/config and digest and ensure
its image remains available; take a consistent DNSSEC state backup before replacing it. Perform the
same steps for the new digest. Inspect health, logs, signed and ordinary DNS,
metrics, and external refusal probes. Update one resolver at a time. Do not
switch the host's only DNS to the service until the recovery path is verified;
registry access and host bootstrap must not depend exclusively on this resolver.
No automatic watchtower, SSH from CI, or automatic cron installation.

Rollback: restore previous approved config and digest, run `docker compose pull`
and `docker compose up -d --wait`, repeat acceptance tests. If incompatible state
changes occurred, stop and restore a coherent approved backup before restarting.
Do not silently reset trust anchor state. Keep old image until acceptance.
For normal restart: `docker compose restart unbound`; logs:
`docker compose logs --tail=100 unbound`; stats:
`docker compose exec -T unbound unbound-control -c /etc/unbound/recursive.conf stats_noreset`.

## DNS access

Default is host-local only, on 1053 (or set DNS_PORT=53 after checking collisions).
Ordinary OS resolvers use port 53. For LAN or VPN clients, design a separate
approved override that binds only a specific private interface; require host
and upstream firewall allowlists for UDP/TCP, plus matching Unbound ACLs.
Inspect Docker NAT and actual client source addresses. Do not rely on UFW or
application ACL alone: Docker forwarding may bypass host INPUT rules. Test
outside access and IPv6 independently. Default ACL trusts the dedicated bridge,
including its gateway; it is not a substitute for network isolation. Do not
attach unrelated containers. Private network subnet changes require matching
ACL changes. Never enable public UDP/53. The host firewall and upstream filtering
must be validated before any non-loopback binding. Public encrypted access is
not implemented in this release.

## State, backup and restoration

Cache is memory-only and reconstructible. `/state/root.key` is persisted per
instance so RFC 5011 state survives upgrades. It contains public DNSSEC trust
anchors and their rollover state, not private signing keys. The package supplies
the initial trust anchor; never overwrite an existing anchor casually.

### Impact of cleanup and purge

| Operation | Containers and their logs | DNSSEC named volume | Cache |
| --- | --- | --- | --- |
| `make stop` | Stopped, retained | Preserved | Lost on stop |
| `make clean` | Removed | Preserved | Lost |
| `make purge` | Removed after confirmation | Deleted | Lost |

These Make targets refer to the local development Compose project. The operator
must identify the correct project and volumes before running destructive commands.
`purge` requires an interactive terminal and the exact word `PURGE`; it cannot run
unattended. It removes all Compose-managed non-external volumes in the selected
base project, not just the trust anchor. It is not a routine production operation.
The separate backup directory is not deleted. The resolver is unavailable until
restarted, and external InfluxDB data is unaffected by these default operations.

After a purge, a fresh volume is initialized from the Debian root.key shipped
with the selected image. Normal resolution may recover immediately with a current
valid anchor, but RFC 5011 rollover observations and hold-down history are lost.
With a stale or inappropriate anchor, validation can fail (`SERVFAIL`) for signed
names. Never disable DNSSEC to work around this. Prefer the saved state or follow
the official Unbound trust-anchor recovery procedure; verify time synchronization
and live signed/bogus DNS responses. Update only one resolver at a time.

### Consistent backup and restore

Use the existing approved backup tooling for configuration, approved image digest,
local inventory and retention. The supplied operator-only `scripts/state.sh`
handles the current default profile's named `/state` volume and its only durable
file, `root.key`. It does not archive cache, logs or secrets. Backup requires an existing stopped container (not `down`); restoration can
create one if absent. Both require a trusted local image and a protected
working directory and backup directory. No root process in the helper, host bind
mount, network, extra capability or Docker socket is used inside the helper.
The invoking operator must have authorized Docker access. Use a separate procedure
for deployments with different Compose file sets or state layouts.

For a published-image installation using the base Compose file:

```sh
docker compose -f compose.yaml stop unbound
BACKUP_DIR=/path/to/approved/backups ./scripts/state.sh backup
docker compose -f compose.yaml up -d --wait
./tests/integration.sh
```

For local development, use `make stop`, `make backup-state`, `make start`.
`BACKUP_DIR` defaults to `backups/` for local testing. Each successful backup is
published as a unique UTC-timestamped directory containing `root.key` and
`root.key.sha512`. The checksum detects accidental corruption, not malicious
replacement; trust and protect the source. A failed backup does not publish a
complete set. The script does not prune or mirror backup sets. Keep backup sets
and their metadata outside the repository and distinguish instances in the
protected backup catalog. Serialize all Docker/Compose operations through the
approved operator mechanism; the script's local lock covers its own operations,
not arbitrary concurrent Docker commands. A stale lock after abrupt termination
requires operator investigation, not automatic removal.

Restore first in an isolated instance. Stop one resolver, preserve its current
state if present, and choose an approved backup from that same resolver. Use the
base profile. If the container was removed, the restore script recreates a
stopped container and its named volume after validating the backup and receiving
confirmation, using the selected image already present locally. No pull, build
or resolver start is performed. If the selected image is absent, retrieve and
verify it separately. For a new volume, confirm numeric ownership and permissions.

```sh
BACKUP_SET=/path/to/approved/backups/dnssec-<timestamp>-<suffix> ./scripts/state.sh restore
# Confirm RESTORE interactively, then:
docker compose -f compose.yaml up -d --wait
./tests/integration.sh
```

The restore verifies SHA-512 before writing, then replaces the anchor atomically
as UID/GID 10001 and reads back the persisted SHA-512 before reporting success. It does not start the resolver or establish that an old anchor
is still valid. Check DNSSEC after starting. If restore fails, investigate the
error and retain the last healthy backup; never automatically purge the volume.
For local tests, `make restore-state BACKUP_SET=/path/to/backup` is equivalent.
No routine cross-replication of running anchor state between independent nodes.
For useful backup sets, use local mandated backup root, last success for each of
7 days plus last per older ISO week up to 23 weeks (nominal 30), Europe/Paris
calendar, UTC timestamps, preserve last healthy archive, suspend purge on doubt.
If applicable mirror the backup set to the other server using single-source,
bounded SSH, verified checksums and controlled deletion; test restoration.
Actual backup identifiers, paths, retention and restore evidence are local.
No backup job or cron is installed; if a scheduled job is later approved, use
least privilege, locking, documented duration/failure, `MAILTO=root`, verify MTA
and forwarding, and avoid secrets in output.
