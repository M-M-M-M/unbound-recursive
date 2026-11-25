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
