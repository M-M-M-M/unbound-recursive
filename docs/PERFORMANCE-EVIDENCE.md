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
