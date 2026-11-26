# Verified image updates and rollback (dev12)

This is an operator-only helper for the **default loopback profile**, with the
same Compose file and DNSSEC state schema across versions. Not an unattended
updater, configuration migration tool or production release authorization.
Never use it on the optional control-socket profile, dnsdist, or a modified
state layout without a separately reviewed procedure. Test on a disposable
host first. No server address, credentials or remote SSH is needed.

## Prerequisites

Use trusted Docker/Compose v2, Buildx, Perl 5.26+ and Cosign 3.1.4 (or a
reviewed compatible newer version). The public image and its OCI attestations
are read without a GitHub account, token, GitHub CLI or registry login.
Keep the checked-in `security/github-provenance.cue` with the reviewed scripts.
Use the default trusted Sigstore configuration and verify registry access as
the operator. See [supply-chain security](SUPPLY-CHAIN.md).
Run from a protected, operator-owned directory containing the reviewed
`compose.yaml`, `scripts/` and `tests/` of this revision. All files/parents
must be trusted and not writable by application accounts. `.env` must be a
regular operator-owned file, not group/world writable (0600 recommended),
containing only literal `UNBOUND_IMAGE`, optional `DNS_PORT` and optional
`DNSSEC_STATE_SOURCE` assignments,
blank lines and comments. `DNSSEC_STATE_SOURCE` must be `state` (default) or
a pre-created absolute canonical protected path without spaces. Keep the source
unchanged for an image-only update or rollback. See [storage](STATE-STORAGE.md).
No Compose environment overrides are accepted by
the update helper. Set an existing protected absolute `BACKUP_DIR` (operator
owned, no group/world write). Keep it outside the repository on production.
The journal and lock stay local; serialize all operational actions, including
manual Compose/state commands, through the approved admin mechanism. Do not
run as the resolver or Telegraf account. No cron is installed.

## Verify before approval

```sh
./scripts/deploy.pl verify latest
# Optional backward-compatibility test with the dev8 signed reference:
./scripts/deploy.pl verify sha256:1f174bcd92333948337b359a0773aaefbff1e50eeddc6c22a6003ac356562e81
```

`verify` resolves `latest` exactly once, verifies Cosign on the index, GitHub
provenance for the index, and both CycloneDX SBOM attestations using the two
platform digests using only Cosign. It requires the exact certificate identity
and issuer, validates the signed provenance workflow/ref and requires the
`github-hosted` runner field in the provenance predicate. This is not a
certificate-extension check; see the supply-chain documentation. The only successful stdout line
is the immutable image reference; diagnostics are on stderr. It does not pull
layers or deploy. Check the associated CI reports, current Trivy rescan, source
revision, release gates and risk review before approving any digest. A valid
signature does not establish current vulnerability status or authorize a release.

## First install (isolated qualification)

Copy `.env.example` to `.env` only if it does not exist. Replace the image
line with the approved exact reference printed above; chmod 0600. Ensure
no conflicting Compose environment variables. After preflight:

```sh
./scripts/state.sh check
docker compose -f compose.yaml config --quiet
docker compose -f compose.yaml pull
docker compose -f compose.yaml up -d --wait --no-build --pull never
COMPOSE_FILE=compose.yaml ./tests/integration.sh
```

The update helper expects an existing healthy instance using that pinned image.
Do not use `make start` for a published image (it selects the development override).

## Update (explicit approval)

```sh
# replace with local protected directory and reviewed immutable digest
export BACKUP_DIR=/path/to/approved/backups
./scripts/deploy.pl update sha256:REPLACE_WITH_APPROVED_DIGEST
```

The helper rejects tags for update, concurrent/stale locks, inconsistent journal
or configuration, an altered storage source, unsafe `.env`, and an unexpected running image ID. It verifies
both candidate and previous signed images, downloads both by digest before
stopping, records a pending local journal, stops and backs up DNSSEC, starts
the candidate without pull/build, checks its exact running image ID and health,
and runs the integration suite. It changes `.env` atomically only after tests
pass, and records the prior digest in `.deployment-state.json`. It never
purges volumes or modifies firewall/host DNS. Each server is updated separately.

On a failed application it attempts to restart and test the previously verified
image, preserving the state storage, restores the original `.env`, records the
rollback outcome and returns nonzero. This automatic rollback is **image-only**:
it assumes the state/config schema is compatible. It never silently restores
or resets a trust anchor. Review and test a coherent state recovery separately
when needed. A failed rollback or interrupted deployment leaves evidence in the
journal (a killed process may also leave the lock); do not delete these blindly.

## Explicit rollback and recovery

```sh
./scripts/deploy.pl rollback
```

This uses the previous digest from the last completed update, re-verifies it,
backs up current state, and performs the same acceptance sequence. It requires
a healthy current instance and unchanged Compose file. This is not the emergency
recovery path if the current instance is unhealthy or registry/signature services
are unavailable. For emergency recovery: inspect `.env`, journal, lock, actual
containers and local image IDs; identify the last verified image and coherent
backup; use the manual procedure in [deployment](DEPLOYMENT.md) with the
previous approved config/digest, and the explicit `RESTORE` path only if needed.
Retain old local images, prior reviewed source/config and verification evidence.
Record the incident; reconcile the journal only after operator approval. Atomic
file replacement is not a guarantee of durability after host/power failure.

## Qualification before production

- `prove -v tests/deploy.t` tests orchestration using mocked tools (no Docker).
- Once a newer candidate is published, dispatch **Qualify signed deployment and rollback**
  on `main` in GitHub Actions. Supply two distinct signed, approved manifest
  digests (for example dev8 and the newer candidate, only if both pass the new verifier).
  The read-only workflow runs on fresh native amd64/arm64 runners. It exercises
  install, deliberate acceptance-test failure and automatic rollback, successful
  update, backup checksum, real stats export, manual rollback and final integration.
  No credentials, production host or remote deployment are involved.
- The same test is available on a **disposable Docker host** with free port
  1053 and subnet 172.30.53.0/24. Do not run alongside a real resolver; use a
  trusted local Docker context. The test copies the reviewed files into a random
  lab project, removes only its resources and retains local lab evidence.

  ```sh
  RUN_DEPLOY_LIVE=1 PREVIOUS_DIGEST=sha256:OLD_DIGEST \
    CANDIDATE_DIGEST=sha256:NEW_DIGEST prove -v tests/deploy-live.t
  ```

  Replace both placeholders with exact 64-hex digests. Failed verification is a
  hard stop; never bypass the attestation checks to migrate an older image.
  `prove` without this opt-in skips the live lab. On CI the runner is disposable.
- Verify a wrong digest/signature is refused before interruption. Exercise failed
  acceptance and rollback only in a disposable environment with a reviewed test
  fixture; do not sabotage the real resolver. Record recovery time.
- Simulate registry failure, lost process and failed rollback in an isolated lab;
  establish manual recovery and independently verify host firewall and exposure.
- Keep the previous resolver online while updating the other one. Never switch
  the host's only DNS to this service until bootstrap/recovery are qualified.

Mock tests are not evidence that live Cosign, Compose, rollback or
host permissions work on the actual production hosts.

## Discover the correct manifest digest (dev13)

`make digest` prints only the current multiarchitecture index SHA-256. It is
structural discovery, not authorization or signature verification:

```sh
make digest
./scripts/deploy.pl verify latest
```

For a manual deployment qualification, open the successful Build and qualify
run, Summary, and the **Deployment qualification inputs** section. Copy
`Previous manifest digest` into `previous` and `Published manifest digest`
into `candidate`. These must be distinct approved indexes, each containing
both Linux amd64 and arm64. If the previous digest is unavailable or identical,
select an earlier successful run's published index and verify it explicitly.
Do not use the nested per-platform digests printed by imagetools inspect.
A single-platform digest now fails before Cosign with an actionable error.

Run **Re-scan published snapshot** manually with the approved index (or leave
blank to resolve latest once) and retain both platform reports. A green scan
is evidence for the policy at scan time, not automatic deployment approval.
