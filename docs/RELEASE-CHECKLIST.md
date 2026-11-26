# 0.1.0 release candidate evidence checklist

This is an operator sign-off checklist, not release approval. The production
image and security policy are unchanged in dev17. See [validation](VALIDATION.md),
[hardening](HARDENING.md), [deployment](DEPLOYMENT.md), [monitoring](MONITORING.md)
and [performance evidence](PERFORMANCE-EVIDENCE.md).

| Gate | Last known evidence | Remaining action |
|---|---|---|
| Core and state recovery | dev16 corrected 362 unit assertions passed; dev15 CI reported passed | Repeat dev17 local and CI checks; verify on representative Linux hosts |
| Network and process hardening | dev15 isolated IPv4 ACL and process checks passed | Host firewall, IPv6 exposure, NAT/source IP, SELinux and numeric ownership |
| Signed immutable deployment and rollback | dev12 operator reported two signed index deployment/rollback qualification passed | Verify current approved index, SBOM, provenance and recovery on deployment host |
| DNSSEC | Local state recovery and integration passed | Run new deterministic positive/negative/CD fixture on both platforms; anchor rollover/migration evidence |
| Endurance DNS | dev16 corrected full 70 min coverage; 1k PASS, 10k under-driven | Dev16.1 independent 10k PASS; 24 h at 100 q/s pending |
| Native comparison | Both native CI archives reviewed | Controlled-host repeat if needed; not equivalent to exact published image |
| Monitoring | dev16.1 72 operations assertions passed | Notification delivery, absence/errors, daily growth |
| CVE review | dev16.1 both reports reviewed, 25 HIGH IDs triaged | Inspect dev17 runtime audit and refreshed scans; approve risk dispositions |
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
2. Run the independent day test (dev16.1 10k passed)
   on an uninterrupted machine. Retain JSON/CSV/JSONL outside Grafana retention.
3. Run `make test-dnssec`, `make audit-runtime` and monitoring operations qualification, then the manual delivery/absence/
   storage checks. Run the native comparison workflow manually if useful.
4. Review the scan evidence, host readiness and actual rollback/recovery
   evidence. Review installation/upgrade documentation on the intended host.
5. Agree on outstanding gates before tagging a release candidate. No automatic
   production deployment or stable release is authorized by these tests.

Use the [current security review](CURRENT-SECURITY-REVIEW.md) and [Linux host
acceptance runbook](LINUX-ACCEPTANCE.md) for the remaining dev17 gates.
