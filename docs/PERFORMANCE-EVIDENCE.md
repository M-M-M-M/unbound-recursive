# Measured performance — dev14.2, 2026-11-26

Evidence: four operator-supplied schema-3 JSON reports, reviewed during dev15
preparation. The environment was macOS ARM64 / Docker Engine 29.9.3, with
native Linux ARM64 containers. Resolver image size 142,298,403 bytes;
resolver limited to one CPU and 512 MiB RAM. The image was a local build,
not a verified published manifest. No Internet recursion, public DNS load,
TLS or production host qualification is implied. The lab uses an insecure
synthetic forwarding fixture and an isolated network. All four recovery
probes passed.

| Profile | Requested | Sent | Valid responses | Failed attempts |
|---|---:|---:|---:|---:|
| Baseline | 50,000 | 49,377 | 49,377 | 0 |
| Production-like | 2,500 | 2,500 | 2,500 | 0 |
| Rate-limit | 5,000 | 4,012 | 3,036 | 976 |
| Stress | 280,000 | 279,887 | 279,887 | 0 |
| Total | 337,500 | 335,776 | 334,800 | 976 |

All 331,764 sends outside the rate-limit profile received valid responses.
Across profiles 1,724 planned queries were not attempted. In the rate-limit
profile the 200 q/s UDP phase sent 1,012 of 2,000 scheduled; 89 timeouts
matched 89 limiter increments. TCP sent all 2,000; 887 peer closures matched
887 limiter increments. This is aggregate correspondence, not per-packet
attribution. The old UDP generator blocked during timeouts; dev15 addresses
that limitation for rate-limit and soak profiles.

| Baseline case | Successful q/s | p99 (ms) |
|---|---:|---:|
| UDP warm | 980.89 | 2.644 |
| UDP cold | 982.25 | 2.833 |
| TCP warm | 995.17 | 1.708 |
| TCP cold | 999.65 | 1.236 |
| TCP persistent warm | 979.29 | 2.502 |

| Stress target (q/s) | Successful q/s | Valid/sent | p99 (ms) |
|---:|---:|---:|---:|
| 500 | 499.63 | 5,000/5,000 | 3.911 |
| 1,000 | 999.09 | 10,000/10,000 | 1.546 |
| 2,500 | 2,497.32 | 25,000/25,000 | 0.357 |
| 5,000 | 4,996.39 | 50,000/50,000 | 0.278 |
| 10,000 | 9,982.19 | 99,914/99,914 | 0.303 |
| 1,000 (30 s) | 999.36 | 29,991/29,991 | 2.547 |
| 1,000 (60 s) | 999.41 | 59,982/59,982 | 2.352 |

10,000 q/s is a rounded target, not an exact achieved sustained rate. The
highest tested phase lasted 10 seconds. This does not identify the maximum
capacity. Production-like p99 exceeded 5 ms in three of five scenarios
(UDP cold 8.974, TCP warm 6.053, TCP cold 5.231); do not apply a blanket claim
of sub-5-ms p99. Repeat runs, vary phase order and compare native AMD64 before
claiming general performance or attributing timing differences to CPU effects.

The operator separately reported all three dev14.2 CI workflows passed and
provided local logs showing 285 unit, 1 integration, 18 volume, 22 bind,
57 monitoring and 25 network assertions passed. After normalizing the random
Docker repository name the operator reported 48/48 smoke queries succeeded.
Successful CI logs were not supplied for independent review.

## dev15 — ARM64 endurance, 26 November 2026

Source: operator-supplied schema-3 JSON for `ratelimit` and `soak`, and local
TAP/terminal output. Both reports record ARM64, Docker Engine 29.9.3, the same
142,298,403-byte resolver image and successful recovery. The operator reported
all three GitHub workflows successful; their logs were not supplied.

| Target / duration | Planned | Sent / valid | Goodput (q/s) | p99 (ms) | Max latency (ms) |
|---|---:|---:|---:|---:|---:|
| 1,000 / 60 min | 3,600,000 | 3,586,387 / 3,586,387 | 996.22 | 3.24 | 585.64 |
| 10,000 / 10 min | 6,000,000 | 5,942,982 / 5,942,982 | 9,904.93 | 0.57 | 392.36 |

9,529,369 valid answers, zero failed sends, zero timeouts, zero unmatched UDP
replies and zero IP limiter increments. All sends were recorded as cache misses.
70,631 scheduled queries were not sent. Both phases meet the dev15 throughput,
reliability and percentile gates; they do not prove a global latency SLA.

| Target | Resolver CPU max sample | Resolver RAM max sample | Samples per role | Last sample |
|---|---:|---:|---:|---:|
| 1,000 q/s | 26.88% | 128.6 MiB | 69 | 2,205.23 s |
| 10,000 q/s | 57.90% | 131.0 MiB | 19 | 585.40 s |

Resource samples suggest a plateau but do not cover the last 23 minutes of
the first phase. The terminal progress messages continued through 3,542 s;
therefore the sampler loop was not simply stopped at 2,205 s. Its old error
handling silently ignored failed or unrecognized Docker stats responses.
The exact failure cause is not established. Do not mark the memory/endurance
resource gate as passed for that phase. No peak or absence-of-leak guarantee.
Dev16 adds a sampling watchdog and coverage evidence; repeat with the new tool.

At 200 q/s, async UDP sent all 2,000 scheduled queries, 1,128 succeeded and
872 timed out; TCP sent 2,000, 1,134 succeeded and 866 peers closed. The
respective IP limiter deltas were 872 and 866. At 50 q/s all 500 sends per
protocol succeeded without limiting. This supports intended limiter behavior;
individual packet attribution and a strict exact-100-q/s cap are not claimed.
The prior 50-q/s TCP p99 was 11.212 ms in this run; latency objectives are
qualified under the specific endurance workload, not assumed for every profile.

## dev16 with command-runner correction — ARM64, 26 November 2026

Source: operator-supplied complete soak JSON, resource journals and terminal
output; same synthetic internal bridge and 142,298,403-byte resolver image.
The original dev16 run aborted with `Too many open files` and the per-role
watchdog. A low-descriptor-limit regression reproduced exhaustion in the
shared Perl command runner. Using scoped File::Temp objects fixed the issue
in the operator's repeated 70-minute run; there were no sampler diagnostics.

| Target / duration | Planned | Sent / valid | Offered (q/s) | Goodput (q/s) | p99 (ms) | Max latency (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1,000 / 60 min | 3,600,000 | 3,576,323 / 3,576,323 | 993.42 | 993.42 | 3.39 | 863.31 |
| 10,000 / 10 min | 6,000,000 | 5,856,590 / 5,856,590 | 9,760.98 | 9,760.20 | 1.93 | 800.08 |

All 9,432,913 sent queries succeeded; 167,087 planned slots were not sent.
No observed timeout, send failure, unmatched UDP reply or IP limiter
increment; recovery succeeded. All observed DNS reliability and latency
criteria passed, but the second phase sent only 97.61% of the planned count,
under the unchanged 99% gate. In dev16.1 terminology the first phase passes;
the second is INCONCLUSIVE, not proof of resolver failure or of 10,000 q/s
capacity. Do not waive the gate. The generator and host scheduling causes
cannot be separated retrospectively from this report.

| Target | Samples per role | Maximum gap | Late memory median change (resolver) |
|---|---:|---:|---:|
| 1,000 q/s | 120 | 31.112 s | +0.2 MiB |
| 10,000 q/s | 20 | 30.095 s | +0.5 MiB |

Both coverage gates complete; zero sampler diagnostics and clock anomalies;
observed container health normal. The plateau is encouraging, not proof of
absence of leaks; the 24-hour test remains open. Isolated phases in dev16.1
start a new lab, not a continuation of the earlier warmed 70-minute run.

## dev16.1 native CI comparison — 2026-11-26

Operator supplied both native comparison archives, Docker 28.0.4 on Linux.
These are local CI builds, not the exact published image scanned by Trivy.
Different hosted machines and scheduling prevent a controlled CPU architecture
comparison. All eight reports recorded recovery success; both soak-check
phases passed. No failure among sent queries.

| Architecture | Requested | Sent | Valid | Failed | Resolver bytes | Client bytes |
|---|---:|---:|---:|---:|---:|---:|
| amd64 | 342,048 | 338,903 | 338,903 | 0 | 116,553,337 | 132,133,547 |
| arm64 | 342,048 | 329,917 | 329,917 | 0 | 142,289,905 | 156,299,106 |

### Baseline

| Case | AMD64 valid q/s | AMD64 p99 ms | ARM64 valid q/s | ARM64 p99 ms |
|---|---:|---:|---:|---:|
| udp-warm | 999.99 | 0.256 | 999.98 | 0.297 |
| udp-cold | 999.96 | 0.395 | 999.98 | 0.481 |
| tcp-warm | 999.81 | 0.398 | 999.98 | 0.505 |
| tcp-cold | 889.65 | 24.637 | 984.62 | 5.308 |
| tcp-persistent | 999.53 | 0.167 | 999.98 | 0.192 |

### Stress

| Case | AMD64 valid q/s | AMD64 p99 ms | ARM64 valid q/s | ARM64 p99 ms |
|---|---:|---:|---:|---:|
| udp-stress-500 | 499.30 | 0.451 | 499.53 | 0.563 |
| udp-stress-1000 | 998.39 | 0.424 | 998.84 | 0.518 |
| udp-stress-2500 | 2493.69 | 0.541 | 2497.24 | 0.582 |
| udp-stress-5000 | 4961.58 | 0.807 | 4993.83 | 0.973 |
| udp-stress-10000 | 9804.14 | 2.112 | 8772.81 | 2.708 |
| udp-stress-30 | 999.45 | 0.379 | 999.46 | 0.520 |
| udp-stress-60 | 999.81 | 0.395 | 999.82 | 0.499 |

At the 10k stress step AMD64 emitted 98,207/100,000 and ARM64
88,031/100,000. The exploratory stress gate does not require 99% offered load;
do not describe these as strict 10k soak passes. TCP cold creates a new
connection per request; the slower cases do not imply DNS losses.

## dev16.1 independent 10k soak — operator report

600 seconds on macOS ARM64, isolated synthetic cold UDP. 5,993,142 of
6,000,000 scheduled queries sent; all successful, 99.8857% emission,
9,988.5 valid q/s, 6,858 expired slots, zero pending/ID/tail omissions.
40/40 resource samples and no sampler diagnostics. PASS. The operator
also reported 72/72 monitoring operations tests and successful native
comparison and re-scan workflows. No 24-hour endurance or real Internet
capacity claim. The independent phase has a different initial cache state
from the combined 70-minute run.
