# 0.1.0 release candidate evidence checklist

This is an operator sign-off checklist, not release approval. The production
image and security policy are unchanged in dev16. See [validation](VALIDATION.md),
[hardening](HARDENING.md), [deployment](DEPLOYMENT.md), [monitoring](MONITORING.md)
and [performance evidence](PERFORMANCE-EVIDENCE.md).

| Gate | Last known evidence | Remaining action |
|---|---|---|
| Core and state recovery | dev15 local TAP passed; operator reported all three CI workflows passed | Repeat dev16 local and CI checks; verify on representative Linux hosts |
| Network and process hardening | dev15 isolated IPv4 ACL and process checks passed | Host firewall, IPv6 exposure, NAT/source IP, SELinux and numeric ownership |
| Signed immutable deployment and rollback | dev12 operator reported two signed index deployment/rollback qualification passed | Verify current approved index, SBOM, provenance and recovery on deployment host |
| DNSSEC | Local state recovery and integration passed | Deterministic negative validation and anchor rollover/migration evidence |
| Endurance DNS | dev15 60 min / 10 min DNS gates passed | Repeat with full resource coverage; 24 h at 100 q/s pending |
| Native comparison | ARM64 measurements recorded | Manual comparison on native AMD64 and ARM64, repeat on controlled hosts |
| Monitoring | dev15 57 assertions passed, dashboard shown | dev16 opt-in alert state and retention test; notification delivery, absence/errors, daily growth |
| CVE review | Historical dev8 review; no current raw scan reports | Obtain current immutable-index scans; review all HIGH findings and reachable code |
| Documentation | Existing runbooks and dev16 checklist | Review all operator commands, deployment paths and evidence before approval |

## Current vulnerability evidence

In GitHub Actions, dispatch **Re-scan published snapshot** with the explicitly
approved manifest digest (or resolve `latest` once, then verify the reported
digest). Download both `rescan-amd64` and `rescan-arm64` artifacts. Retain the
`scanned-image.txt` and `vulnerabilities.json` in each architecture's separate
folder; record the run ID/date and verify identical manifest selection.
Use `perl scripts/vulnerability-gate.pl <report>` for the existing gate; a
successful gate does not close the individual HIGH risk review. Consult Debian
security advisories and upstream reachability for the exact installed versions.
Do not add exceptions just to clear a workflow. Never publish host-specific
configuration, credentials or raw private operational logs.

## Qualification order

1. Review the source diff and local/CI regression results; inspect the new
   two-minute sampling check. Stop if resource evidence is incomplete.
2. Repeat the 70-minute soak with the watchdog, then the independent day test
   on an uninterrupted machine. Retain JSON/CSV/JSONL outside Grafana retention.
3. Run monitoring operations qualification and the manual delivery/absence/
   storage checks. Run the native comparison workflow manually if useful.
4. Review the scan evidence, host readiness and actual rollback/recovery
   evidence. Review installation/upgrade documentation on the intended host.
5. Agree on outstanding gates before tagging a release candidate. No automatic
   production deployment or stable release is authorized by these tests.
