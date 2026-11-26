# Isolated performance and network qualification (development)

This lab does **not** benchmark Internet recursion or DNSSEC cryptography.
Never deploy its configuration. It measures the same local resolver binary,
cache sizes, process limits and rate limit settings using a synthetic unsigned
forwarding fixture and no external DNS workload. The fixture shares the lab
resolver network namespace and listens on 127.0.0.1:5354; the resolver forwards
only to that address, without fallback. The separate internal Docker bridge
has no external route and publishes dynamically assigned IPv4 loopback ports
for the host test client. Its broad client ACL is deliberately lab-only. Do not
run with a remote Docker context. A failure of loopback access is a failed lab
qualification, not grounds to expose the port publicly.

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
and sampled `docker stats` CPU/memory/network/I/O. A local image ID is not a
signed multiarchitecture GHCR digest. For publication-grade comparisons record
verified manifest digest, build commit, CPU allocation, Docker version, host
load and repetitions separately. Docker stats samples can miss short bursts;
empty samples mean no sample collected, not zero resource use. Do not compare
macOS VM and native Linux numbers without noting the difference. No universal
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
