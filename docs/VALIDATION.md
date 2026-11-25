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

Shell syntax and Make dry-run checks passed. `python3 tests/state-mock.py`
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
