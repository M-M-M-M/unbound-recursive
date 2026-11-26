# Isolated performance and network qualification (development)

This lab does **not** benchmark Internet recursion or DNSSEC cryptography.
Never deploy its configuration. It measures the same local resolver binary,
cache sizes, process limits and rate limit settings using a synthetic unsigned
forwarding fixture and no external DNS workload. The fixture shares the lab
resolver network namespace and listens on 127.0.0.1:5354; the resolver forwards
only to that address, without fallback. The separate internal Docker bridge
has no normal external route. The bounded Perl load generator joins this same
bridge as a distinct container, with no published ports on any service. The
host orchestration checks the actual bridge, its membership, the fixture
network namespace, container bindings and the numeric resolver endpoint
before any benchmark query. Its broad resolver ACL is deliberately lab-only.
Do not run with a remote Docker context. Docker network isolation is not a
substitute for host security; the client only queries the inspected resolver IP
and synthetic fixture names. Do not attach other services to this lab.

Dev14 failed locally on Docker Desktop 4.99.0 / Engine 29.9.3 with
`unsafe benchmark binding` before sending benchmark traffic. Dev14.1 removes
the dependency on host port publication rather than weakening isolation. The
exact original binding response was not recorded. The client uses a separate
locally built Debian/Perl image with a pinned base, non-root UID/GID 10001,
read-only root filesystem, no capabilities, no-new-privileges, resource limits
and a small writable tmpfs. Its unique local tag is removed on teardown;
Docker build cache may remain. Build-time package downloads require network
access; the runtime lab does not use public DNS workloads. The production
Unbound image is unchanged and neither the lab nor client is published.

```sh
make build
make test-network       # actual production config, isolated unauthorized peer
make test-benchmark     # four paced small smoke phases; limits retained
make benchmark          # baseline without lab-only IP/domain limits
make benchmark-production
make benchmark-ratelimit
make benchmark-stress
```

| Profile | Target rate (queries/s) | Emission window | Limits in lab |
|---|---|---|---|
| quick | 12 | 1 s per case | 100 IP / 200 domain |
| baseline | 1000 | 10 s per case | off |
| production | 50 | 10 s per case | 100 IP / 200 domain |
| ratelimit | 50, 200 | 10 s per case | 100 IP / 200 domain |
| stress | 500, 1000, 2500, 5000, 10000; 1000 | 10 s; 30 and 60 s | off |

Baseline and production-like profiles exercise UDP/TCP warm/cold plus
persistent TCP warm; the rate-limit profile exercises both transports with
warm cache, below and above the IP limit. Stress uses unique UDP names with
16 workers. The production-like profile reproduces the limiter settings,
not every aspect of production: the lab still forwards to a synthetic fixture
and has a deliberately broad lab ACL. The production configuration is never
changed. Baseline/stress change exactly two directives in the private copy
of the benchmark resolver configuration. The smoke checks all expected
responses and observes cache hits/misses. The rate-limit profile checks
at least 95% success and no IP limiting below threshold; above threshold it
requires actual offered rate >100 and a positive IP-limit counter delta.
These are lab assertions, not universal service-level objectives.

Workers follow an absolute monotonic schedule with a fixed count/duration
and skip missed slots instead of replaying them. This is a bounded,
closed-loop worker implementation with paced slots, not an unlimited
open-loop traffic generator. If the generator cannot sustain the offered
rate, the report identifies that limitation instead of calling it resolver
packet loss. Each worker has at most one outstanding query; request timeout
is nominally one second. The wall-clock goodput includes the full emission
window plus any drain/worker finalization. `offered_qps` counts fully sent
queries divided by the scheduled emission window. `attempted` includes
connection/write failures; `sent` requires a complete wire write (not proof of
server receipt); `not_attempted` counts missed slots. DNS errors, peer EOF,
timeout, connection/write/read errors are distinguished from successful replies.
The aggregate limiter counter is not a per-request attribution. Persistent
TCP reuses a connection until error and then reconnects on a later slot;
there is no pipelining. Success latencies exclude failed requests.

Warm queries use a primed fixed name; cold queries use unique names. The
fixture returns 192.0.2.80. Validate the transaction ID, question, rcode,
truncation and answer. Local health probes can affect counters. Recovery is
checked on UDP and TCP after load. The fixture healthcheck verifies the local
record directly at 127.0.0.1:5354; the client process healthcheck is a Perl
runtime check; the subsequent end-to-end probes verify actual reachability.

`benchmark-results/run-*/report.{json,csv,md}` is ignored by Git. JSON schema 3
records the profile, phase start (host epoch seconds), target/actual rates,
outcomes, counters, latency percentiles and resource samples by role. Docker
stats is requested repeatedly with a short pause; Docker's own sampling
interval and VM scheduling limit precision. Phase/resource times are approximate
host time, not wire packet timestamps; samples can overlap the phase boundary.
Empty samples mean no sample, not zero CPU/RAM. The reports are not a maximum
capacity claim. Completed `phases.json`, `error.txt`, `ps.txt`, and `logs.txt`
are retained on failure when available, before removing disposable containers.
Review local reports before sharing. A local image ID is not a signed GHCR
manifest digest; record commit, verified digest, host/VM and repeat measurements.

## Grafana (post-run)

```sh
make monitoring-start
make benchmark-monitoring REPORT=benchmark-results/run-XXXXXXXX/report.json
```

Stop the foreground monitoring traffic first if running. The importer reads
only a schema-3 local report and writes validated numeric line protocol via
stdin to the existing disposable InfluxDB lab, not to production. It adds a
five-panel dashboard and prints its URL; wait for Grafana file provisioning
or refresh the browser. Select the benchmark time range, within the lab's
24-hour retention. Phase summaries and resource samples are separate
measurements tagged by run/profile/case (and resource role). Reimport of the
same report uses the same points. This is post-run visualization, not live
benchmark streaming; no network bridge between labs is required. The
monitoring integration test checks import and dashboard queries with a known
synthetic report. Real Docker qualification and longer-duration retention,
alert delivery and production-like soak remain pending.
