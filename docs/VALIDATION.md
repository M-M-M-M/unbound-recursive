# Validation record — 2026-11-25

Scope: initial source bundle prepared locally from the project requirements and
owner-provided infrastructure standards. No server access or changes, no Git
commit/push, no registry publication, and no secret retrieval.

## Local checks performed

- POSIX shell syntax (`sh -n`) for entrypoint, healthcheck and integration tests.
- YAML parsing of Compose, workflow and Dependabot files (custom Compose
  `!override` tag recognized for parsing only).
- JSON parsing of Grafana dashboard and TOML parsing of Telegraf configuration.
- Relative Markdown link existence and Makefile dry-run.
- Source scan for private infrastructure hostnames, email/domain and paths.
- ZIP integrity check at packaging.

These checks do not establish Docker/Compose semantics, a successful image
build, DNSSEC correctness, CI permissions, dashboard rendering, or host security.
Docker and Unbound binaries were not available in the preparation environment.
No live integration, load, ACL rejection, arm64, SELinux, rollback, restore or
monitoring test has been performed. No CVE scan, SBOM or signing yet. These are mandatory 0.1.0 gates. The
workflow is a first implementation and uses mutable action tags. Review and
qualify it before deploying or relying on its published artifacts.

## First operator acceptance

Run `make build`, `make start`, `make test` and `make stats` on macOS M1;
check `dig @127.0.0.1 -p 1053 example.org A +dnssec` from the host. Stop/start
and repeat; confirm anchor state persists. Run on Linux amd64 and in CI.
The integration checks require external authoritative DNS reachability and a
working deliberately bogus external DNSSEC test domain; a blocked network or
fixture failure must not be interpreted as a DNSSEC pass. The container
liveness check intentionally does not depend on public DNS availability.
Check both host loopback port publications, actual source IPs and refusals
from an unauthorized external test host; never open public UDP for testing.
Review Docker Engine security version and host firewall independently.

Record each outcome with date, architecture, Docker/Compose versions, image
digest, configuration revision and evidence in local protected documentation.
Do not claim compliance or production readiness until gates in [PLAN](../PLAN.md)
and [HARDENING](HARDENING.md) pass.

## Revised development bundle

Integrated the four reusable project-template-basic files (merging AGENTS, TODO
and CHANGELOG without copying the template maintenance history). Added the
first-release hardening checklist and extended integration assertions for
effective identity, resource limits, log rotation, capabilities, devices,
namespace isolation and absence of default bind mounts. Only shell syntax
and static file checks were run for these changes; Docker execution remains
required. Markdown formatting/lint tools were unavailable.


## State operations revision

Shell syntax and Make dry-run checks passed. the former dev3 mocked state test
passed using a simulated Docker CLI and pseudo-terminal: backup/checksum,
running-instance refusal, corrupt backup refusal, noninteractive refusal,
confirmation cancellation, confirmed purge and simulated restore. This does
not test actual Docker mounts, filesystem ownership or real DNSSEC recovery.
Run an isolated live exercise: start and validate, stop and back up, clean and
recreate (verify the saved state survives), stop and back up again, purge only
the disposable project, create its stopped container, restore the trusted
backup, start and repeat live DNSSEC tests. Verify recovery time, ownership,
volume independence and failed/corrupt backup behavior. Do not run this exercise
on a production instance. No real Docker operations were performed here.

## Operator evidence — previous snapshot, 2026-11-25

Source archive commit d8239a448a456ec1e82f66f1786a18a9c84dbfcb. Operator
reported successful main workflow, native macOS M1 build and integration, GHCR
manifest with linux/amd64 and linux/arm64, native ARM64 pull and live DNSSEC
(NOERROR/AD and deliberately bogus SERVFAIL). Published manifest digest:
`sha256:2c214010380c9541c45ee6fac956e0fee2323f2bc64cc9f5fb0abaa7953c1c2e`.
Backup, non-destructive clean, confirmed purge, backup survival and restore to
a recreated stopped container succeeded. Direct restore after complete purge
failed because the original script required an existing container.

## dev4 recovery and security revision

Local simulated state test reproduces and covers the absent-container case,
checksum mismatch, cancellation and no implicit start. New `make test-state`
uses a unique disposable project with dynamic loopback ports and subnet, then
cleans up only that project. It tests existing-volume recovery after clean,
complete purge, corrupted backup refusal, exact restored bytes before start and
live integration. In dev4 it required Python 3; dev5 replaces this dependency with Perl and prove. The live test requires Docker and a previously built local
image (override `TEST_IMAGE` to an already pulled approved image). Run it only
on a test Docker host. No production volume is targeted. CI now runs it on
both native architectures, followed by vulnerability scans, inventory,
publishing and verification. Live execution of dev4 is still pending.

## dev5 Perl migration

Offline regression tests were executed using Perl 5.40.1 on Linux, with
`prove -v tests/*.t`. The CVE gate and mock state operations passed (45
assertions); the two Docker-dependent test files were explicitly skipped.
The real PTY confirmations were exercised using util-linux `script`. macOS
BSD `script`, the minimum Perl 5.26 runtime, live Docker recovery and the
modified CI workflows remain to be qualified. `make test-unit` runs without
Docker; `make test-state` explicitly enables the isolated live recovery suite.

## dev6 interactive confirmation portability

Operator evidence for dev5 on macOS M1: vulnerability-gate.t 16/16,
local build/start and integration.t passed. state-mock.t failed seven of 29
assertions; state-live.t stopped at confirmed restore with `confirmation
cancelled`, then cleaned up its disposable project. The failure is consistent
with early input/EOF in the BSD script driver, not proof of a resolver fault.

Dev6 waits for the prompt and leaves the input pipe open; confirmation.t
checks delayed and split prompts and incorrect confirmation. The production
state.sh is unchanged. Offline tests passed under Linux with util-linux
script. Re-run `prove -v tests/*.t` and `make test-state` on macOS to qualify
the BSD implementation and actual recovery. CI and Linux production-like
qualification are still pending.

## dev6 operator and CI evidence / dev7 gate

Operator report: 47 offline assertions and 18 live state recovery assertions
passed on macOS M1. The GitHub Actions log export for run 123680798438 shows
both native jobs reaching the CVE gate after tests and scan. Each image had
86 HIGH/CRITICAL package findings (82 HIGH, 4 CRITICAL). The gate blocked
promotion. The four CRITICAL findings were CVE-2019-16224, CVE-2019-16225 and
CVE-2019-16227 in liblmdb0 and CVE-2026-6653 in libxml2. The reported fix for
CVE-2026-124851 in libzstd1 was 1.5.7+dfsg-1+deb13u1. These are historical
scanner observations, not a current exploitability assessment.

Dev7 upgrades existing Debian packages, captures an installed package inventory,
and evaluates the full report using the documented policy and empty exception
register. The previous findings would still block on the four unapproved
CRITICAL findings, plus any fixable HIGH/CRITICAL still present. No CVE is
approved by this change. Run `make test-unit`, rebuild and run `make test` and
`make test-state`; inspect both CI summaries and evidence artifacts. Verify
whether the available libzstd1 fix is installed and re-evaluate all remaining
critical findings. Signing and promotion remain gated. Keep the previous
approved digest until the new one is qualified.

The dev7 dependency audit retains Unbound, dns-root-data, bind9-dnsutils (dig
is used by the healthcheck and integration tests), and ca-certificates. Do not
remove transitive packages blindly; review the package inventory, Debian
package dependency graph and runtime tests before any removal. The dev7
archive has not been built with Docker in the preparation environment.

## dev7 CI evidence / dev8 dependency reduction

GitHub Actions log export 123684682709: both native jobs reached the CVE gate.
Each reported 347 package findings, 157 unique vulnerability IDs, 81 HIGH,
4 CRITICAL, zero reported fixes, four blockers, 103 warnings and 240
informational findings. No exceptions were used. The build installed updated
libzstd1 1.5.7+dfsg-1+deb13u1, removing the previously reported fixable finding.
The four remaining blockers were the three LMDB findings and libxml2 finding
listed above. Publication did not proceed. The amd64 build log reports 47.2 MB
additional disk space for the dependency installation (not total image size).

Dev8 replaces `bind9-dnsutils` with `ldnsutils`. Debian's package metadata
indicates that the BIND diagnostic stack introduces the unwanted libraries;
removal from the actual transitive closure must be confirmed by a new build.
See <https://packages.debian.org/trixie/ldnsutils> and
<https://manpages.debian.org/trixie/ldnsutils/drill.1.en.html>.
The healthcheck checks the exact synthetic record and NOERROR, with a bounded
probe; the live suite still tests UDP, TCP, positive AD, negative SERVFAIL,
checking-disabled availability and cache counters. A package policy rejects
installed BIND, LMDB and libxml2 packages; deliberate future changes require
review rather than silently relaxing this check. The CVE gate and exceptions
are unchanged.

Local offline `make test-unit` passed 108 assertions (76 existing, 15 probe,
17 dependency policy). These are simulated probe/inventory inputs, not a
live drill execution. Docker and drill were unavailable here. Run on M1:

```sh
make test-unit
# Optional: record the existing dev7 image before rebuilding, if still present.
docker image inspect unbound-recursive:dev --format '{{.Size}}'
make build
make start
make test
make test-state
docker image inspect unbound-recursive:dev --format '{{.Size}}'
```

Record which image ID/digest and revision each size represents. Compare sizes
only for the same platform and measurement (Docker image inspect .Size).
CI now records `image-size-bytes.txt` along with `packages.tsv`, Trivy JSON
and CycloneDX SBOM. Compare dev8 with the historical dev7 reports/inventory
from run 123684682709, not with the number of vulnerabilities alone. A new
scanner DB or Debian package version may change the findings independently.
The four blockers are expected to disappear if their packages are absent;
new HIGH/CRITICAL findings remain subject to the existing policy. Signing,
attestations, promotion and Linux host qualification remain unverified.

## dev8 evidence and dev9 changes

Owner-provided dev8 CI logs (run 123689349415) show successful native builds,
integration/recovery, Trivy and SBOM on both architectures. Per image: 324
findings, 148 IDs, 76 HIGH, zero CRITICAL/blockers or exceptions. Signed
manifest published and promoted, digest
`sha256:1f174bcd92333948337b359a0773aaefbff1e50eeddc6c22a6003ac356562e81`.
Owner verified Cosign from macOS. ARM64 image size measured locally: 152544990
bytes before LDNS change, 142298403 after. Dev8 CI used the same Debian index
digest on both platforms; this is now pinned. See [triage](VULNERABILITY-REVIEW.md).

Dev9 offline checks: `make test-unit` passed 141 assertions, including 21
mocked deployment checks and 12 stats export checks. No real Docker, Cosign,
GitHub CLI, Telegraf or Grafana execution was possible in the preparation
environment. Run the new [upgrade qualification](UPGRADING.md) in an isolated
instance and [monitoring qualification](MONITORING.md#preferred-stats-only-file-handoff-dev9-qualification-pending).
Manually dispatch the revised re-scan workflow with the dev8 digest, then
without input, confirm matching immutable manifest in both artifact records.
Daily schedule, dev9 publication and real Linux host qualification remain pending.


## dev10 verification and live deployment lab

Dev10 local `make test-unit`: 150 assertions passed (including 30 deployment
mock tests). Tests check an actual signature type, wrong digest, exact workflow
identity, each platform attestation, provenance policy invocation and fail-closed
behavior. Mocked Cosign is not evidence of real cryptographic verification or
CUE evaluation. Docker, Cosign and Telegraf/Grafana were not available in this
preparation environment. No dev9 CI results were supplied; the dev8 evidence
above remains the last confirmed real build. The new consumer verification
job and independent promotion job are pending live CI qualification.

Run `make test-unit`, then verify the published dev8 digest with dev10 before
attempting an upgrade. Push the reviewed dev10 changes and check that the
consumer verification job succeeds before `latest` moves. Run the manual
**Qualify signed deployment and rollback** workflow with two distinct verified
manifest digests; see [upgrading](UPGRADING.md). This also checks the stats-file
export against real Unbound output; it does not qualify Telegraf or Grafana.
No CVE policy or exception change has been made.

## dev11 storage qualification

Offline `make test-unit` passed 164 assertions under Linux (14 new state
assertions). No Docker daemon is available in the preparation environment.
Run `make test-state` and `make test-state-bind` in a disposable local lab and
review both native CI jobs. Verify exact anchor bytes survive bind-mode purge,
corrupt restore creates no container, and recovery after simulated anchor loss
works. Qualify Docker Desktop mapping, Linux SELinux/UID ownership, signed
update/rollback with unchanged storage and the manual migration runbook.

## dev12 consistent purge qualification

The simulated state suite exercises bind cancellation, stop-before-delete,
shared mount refusal, helper failure, preservation of backups and unrelated
files, and purge after clean. Run the real bind lab to verify symlink refusal,
actual anchor deletion, preservation of a sentinel, repeated purge and recovery.
The dev11 results above are historical; dev12 intentionally changes bind purge
semantics. Docker live qualification remains pending.

Preparation evidence: `make test-unit` passed 182 assertions under Linux
(61 state-mock assertions, 18 more than dev11). Shell syntax and the live TAP
file compile successfully. Docker is not available in the preparation runtime;
no live bind or volume tests were executed for dev12.

## dev12 operator report and dev13 preparation

The operator reported successful local dev12 tests (182 offline, 18 volume,
22 bind assertions), anonymous verification of both indexes and a successful
manual signed-deployment/rollback workflow after correcting the digest inputs.
The earlier failed workflow used the two platform digests of one build. The
correct multiarchitecture indexes were:

- dev8: `sha256:1f174bcd92333948337b359a0773aaefbff1e50eeddc6c22a6003ac356562e81`
- dev12: `sha256:54805783f2fab5ea443e7eca2bf9e819a981dbce26bf1a45f09a5b8f14565bbb`

Successful final workflow logs were not provided; the report is operator
confirmation, not independently re-inspected CI evidence. Re-scan, production-
like Linux permissions/SELinux and host hardening remain open.

Dev13 preparation: `make test-unit` passed 195 assertions on Linux (37 deploy,
6 collector, other suites unchanged). The live monitoring TAP file compiles;
Docker is unavailable in the preparation environment, so the lab and new CI
workflow have not run. Follow `make test-monitoring` on a disposable Docker
host and retain the AMD64 CI run. The lab checks source timestamps, duplicate
point handling, real statistics, read-only handoff, Flux dashboard queries,
restart/reset and freshness after stopping the resolver. Actual alert delivery,
retention expiry and real storage footprint remain separate acceptance tests.

## dev14 and dev14.1 performance qualification

The supplied macOS ARM64 dev14 log shows 225 offline assertions, one
functional integration assertion, 18 named-volume recovery, 22 bind recovery,
48 monitoring and 25 network assertions passed (339 total). The new network
audit verified UDP/TCP ACL refusal, no published ports and effective non-root,
capabilities, no-new-privileges and seccomp checks. `make test-benchmark`
failed before load with `unsafe benchmark binding`. The operator reported
Docker Desktop 4.99.0 / Engine 29.9.3 and pushed dev14 as commit `d8e9101`.
The exact port response was not recorded; the fix eliminates the dependency
on host publishing on an internal bridge.

Dev14.1 introduces a separate local-only load generator. The targeted suite
checks actual network-inspection data using simulated Docker objects and
exercises the moved multi-worker workload over real loopback sockets. Run
`make test-benchmark`, inspect both native performance CI jobs and retain
`make benchmark` JSON/CSV/Markdown reports before performance acceptance.
Docker is unavailable in the preparation runtime; no corrected live lab has
been executed here. The existing production image/configuration are unchanged.

Preparation: 249 unit assertions passed under Linux, including 24 new
benchmark-lab assertions. The Perl entry points compile; Docker and live
Compose qualification remain pending.

## dev14.2 corrective qualification

Dev14.1 operator report: AMD64/ARM64 CI each passed the 25 network assertions,
then failed at `compose up --wait` because the fixture had no healthcheck.
The local ARM64 schema-2 report shows 8,000 requested, 7,645 attempted,
5,467 successes, 2,178 failed attempts and 355 unattempted. In each phase
failed attempts match the aggregate IP-limit counter delta; recovery is true.
This supports the limiter hypothesis, not individual packet attribution or
unlimited throughput. Monitoring and build workflows were reported successful.

Dev14.2 adds independent load profiles, fixed fixture healthcheck, persistent
TCP, resource/phase reporting and post-run Grafana import. Linux preparation:
285 offline assertions across 14 files passed; real UDP/TCP loopback and
persistent socket tests run, Docker inspection and healthcheck parser use
mocks. Docker unavailable here. Re-run the full local routine, native CI smoke,
then opt-in `make benchmark`, `make benchmark-production`,
`make benchmark-ratelimit`, `make benchmark-stress`. Import a completed report
into Grafana and retain evidence. The live monitoring test adds nine assertions
for benchmark import and five dashboard queries (57 total if all run).
Production image, resolver settings and CVE policy are unchanged.
