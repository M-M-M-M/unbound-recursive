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
make test-network    # unmodified production config, isolated unauthorized peer
make test-benchmark  # small deterministic UDP/TCP warm/cold smoke test
make benchmark       # bounded concurrent workload, not part of ordinary CI
```

The smoke test uses 12 requests per case and checks correct A responses and
cache hit/miss counters. The full benchmark uses 1,000 requests per case
(4 workers), then 4,000 unique UDP names (16 workers). Each worker stops
issuing requests after 30 seconds per phase; each request has a nominal
one-second timeout. No arbitrary destination or names are accepted. Warm
queries use a primed fixed name; cold queries use unique names. The fixture
returns 192.0.2.80. The wire response is checked for transaction ID, question,
rcode, truncation and expected A record. TCP timings include new connection
establishment; this is not a persistent-TCP throughput benchmark. Local
health probes can affect the counters; cache deltas are supporting evidence,
not exact per-request accounting. IP rate limiting may intentionally reduce
success rates. Losses, invalid replies and unattempted requests are not
included in successful latency statistics. Recovery is checked on both UDP
and TCP after the load.

`benchmark-results/run-*/report.{json,csv,md}` is ignored by Git. JSON includes
image ID and size, OS/architecture, Docker version, cache counters, attempts,
outcome counts, actual worker wall time, successful QPS, latency percentiles
and sampled `docker stats` CPU/memory/network/I/O. Schema 2 records the client
image separately and labels samples with `role=resolver` or `role=client`.
Timings are measured inside the load generator; they exclude host-side Docker
exec and stats polling. A local image ID is not a
signed multiarchitecture GHCR digest. For publication-grade comparisons record
verified manifest digest, build commit, CPU allocation, Docker version, host
load and repetitions separately. Docker stats samples can miss short bursts;
empty samples mean no sample collected, not zero resource use. Do not compare
macOS VM and native Linux numbers without noting the difference. Do not
compare the old host-loopback architecture to this container-to-container
architecture as if the measurement path were identical. No universal
throughput acceptance threshold is imposed by CI. Full benchmark is opt-in.

`make test-network` uses the unchanged production image on a randomly allocated
internal network outside the allowed subnet. It checks loopback success,
unauthorized peer REFUSED responses on UDP/TCP, process capabilities,
NoNewPrivs, seccomp and absence of published ports. It is not a substitute for
host firewall, IPv6, Docker NAT/source-IP behavior, SELinux, remote-network
exposure or amplification measurements on a production-like host. Do not
probe public hosts. Deterministic DNSSEC-negative fixtures, prolonged soak,
precise resource peaks and real alert/retention qualification remain release
gates. The monitoring and benchmark labs are deliberately separate; the
current Grafana dashboard does not automatically consume benchmark results.
