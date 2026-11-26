# Persistent DNSSEC state: named volume or bind mount

The only durable resolver state is `/state/root.key` (RFC 5011 trust-anchor
observations). Cache and Docker logs are not stored there. The root filesystem
remains read-only and Unbound runs as UID/GID 10001. Each resolver has its own
state and independent backups. This is a local Docker Engine/Desktop profile;
remote Docker contexts, NFS/shared storage, rootless UID mapping and SELinux
must be reviewed separately. Never share a state directory between resolvers.

## Select a dedicated directory

The default remains the existing Compose volume `state`. To use a host folder,
prepare a dedicated directory **outside the Git checkout** on the Docker host.
Use an absolute canonical path without spaces for the deployment helper. Do not
mount `/`, an application root, a home directory, a backup root or a socket.
Only the resolver and authorized backup/administration operators should have
access. The backup destination must be outside this directory.

Example for Linux with ordinary Docker UID mapping; choose the approved local
path and review the parent permissions first:

```sh
sudo install -d -o 10001 -g 10001 -m 0750 /path/to/private/dnssec-state
```

On SELinux enforcing hosts, arrange an approved persistent container-compatible
label for this dedicated directory (e.g. `container_file_t` where appropriate),
including access by the constrained backup helper. Do not disable SELinux or
relabel broad directories. On Docker Desktop/macOS, prepare a shared host
folder and check actual UID mapping before use; never fix permission errors by
making the state directory world writable. Use `pwd -P` to obtain the canonical
path. A Linux VM/user namespace may map 10001 to a different host UID.

In the local, ignored `.env` (preserve existing values):

```dotenv
DNSSEC_STATE_SOURCE=/path/to/private/dnssec-state
```

```sh
./scripts/state.sh check
docker compose -f compose.yaml config --quiet
# Once the approved image is present and the profile is verified:
docker compose -f compose.yaml up -d --wait --no-build --pull never
./tests/integration.sh
```

For a development image use `make start` instead; it checks the mount first.
The check refuses a missing or noncanonical bind path and group/world writable
state directories; it also compares the actual container mount to Compose when
a container exists. These checks do not audit all parent ownership, symlinks,
SELinux labels or Docker Desktop mappings. Direct Compose commands can bypass
the preflight and short mount syntax can create missing paths: always check
before `up`/`create`. A missing or unwritable directory must not be silently
repaired by the runtime container. Review the effective mounts and test both
DNSSEC and writable anchor state in a disposable instance before deployment.

## Existing named-volume migration (manual, reviewed)

1. Stop the current service, use `scripts/state.sh backup` (or `make backup-state`
   for development) and verify the saved SHA-512. Retain that backup outside
   the new state directory. Record the old image and volume in private inventory.
2. Use `docker compose -f compose.yaml down` (without `--volumes`) or `make clean`
   for the development project. Do not run purge. The old named volume remains.
3. Prepare the new dedicated directory as above. Change only the local `.env`
   `DNSSEC_STATE_SOURCE` value. Run `./scripts/state.sh check`. A migration is
   not an image update: review existing deployment journal and record the new
   profile separately; do not delete a pending/failed journal or edit its hash
   to bypass the guard. The image update helper is not a migration tool.
4. Restore the approved backup into the new storage with the locally available
   image; the restore creates a stopped container if necessary, without starting
   it. For development use `make restore-state BACKUP_SET=...`.

   ```sh
   BACKUP_SET=/path/to/approved/backup ./scripts/state.sh restore
   # Confirm RESTORE, then start and run integration tests.
   ```

5. Verify DNSSEC and take a fresh backup. Keep the previous volume until the
   migration and rollback procedure are approved. To revert the storage choice,
   stop and back up current state, clean without volumes, switch to the old
   source, restore reviewed current state if needed, and validate again.

## Backup and deletion

The bind folder can be included in ordinary host backups when Unbound is stopped.
Preserve numeric ownership, permissions and integrity. The supplied state backup
continues to work in both modes: it uses a non-root, network-disabled helper with
only the selected mount and a SHA-512 checksum. Backups remain independent of
`purge`; never write them inside `/state`.

| Operation | Named volume | Bind directory |
| --- | --- | --- |
| `stop` / `clean` | Retained | Retained |
| confirmed `purge` | Compose-managed volumes removed | Active `root.key` removed; directory, unrelated files and named volumes retained |
| `restore-state` | Recreates stopped service if absent | Same, but operator must pre-create directory |

In either mode, confirmed purge destroys the active DNSSEC state and removes
containers and their logs. In bind mode the service is stopped first; a
constrained non-root helper deletes only the regular `/state/root.key` file.
A missing anchor is harmless, but a symlink, directory or deletion failure
is refused. The path is checked against the effective Compose mount and
running users of the mount are checked before deletion. After `clean`, purge
can create a stopped container using the approved local image, without starting
or pulling it. It then removes that container. The bind directory itself,
other files, and independent backups are preserved. Never recursively delete
a host folder. If a failure occurs after stopping, inspect the stopped service
and state before retrying. Do not run concurrent manual Docker operations or
change the configured directory during state operations. A fresh anchor loses
RFC 5011 history; see [impact](DEPLOYMENT.md#state-backup-and-restoration).

## Qualification

`make test-unit` covers simulated bind backup/restore, mismatch and purge guards.
`make test-state` exercises named-volume recovery; `make test-state-bind` runs
an isolated bind-directory lab with a write probe. On a disposable native Linux
CI runner, `TEST_BIND_PROVISION=1 make test-state-bind` explicitly permits a
one-time `sudo -n chown` of the newly created lab directory to 10001:10001 and
returns ownership after cleanup. The actual resolver and backup helper remain
non-root. Do not use this flag on a host without reviewing the lab path and UID
mapping. On macOS try the unprivileged lab first; if the write probe fails,
review Docker Desktop mapping before retrying with explicit test provisioning.
Live tests and host backup/SELinux behavior are not yet qualified for dev12.
