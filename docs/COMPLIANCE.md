# Infrastructure compliance — initial review

Basis: owner-provided infrastructure standards archive dated 2026-11-25.
Normative source: STANDARDS.md, CODEX_INIT.md sections 4–13 and specialist guides.
The private reference and audit are not redistributed. Record the actual
reference revision and private host inventory in operator documentation.
No host, adjacent repository, SSH, secret framework or deployment-hardening
repository was accessed. Source inspection is not host validation. No derogation
has been approved; any future exception needs reason, risk, compensation,
validator, date and review date.

| Rule | Status | Evidence / remaining qualification |
| --- | --- | --- |
| GEN | Proposed / verify | README, PLAN, ops docs; check actual protected layout |
| LANG | Proposed / verify | Minimal portable POSIX sh, no complex new logic; Perl/Zsh preferred where appropriate; no Perl base required |
| SEC | N/A core | No secrets; future auth uses existing 1Password/SOPS/age, inspect framework and trust boundaries |
| PRIV | Proposed / verify | Dockerfile USER, Compose hardening; confirm numeric IDs, operator rights, SELinux, parents/ACL, socket trust |
| PATH | N/A core | DNS-only, no HTTP site; future DoH uses prescribed hosting path with sites/ |
| NET | N/A HTTP core | Loopback DNS and private bridge proposed; verify actual firewall/ports, future HAProxy/Dehydrated |
| WEBPUB | N/A core | No HTTP publication; signed security.txt and other central assets required before future web publication |
| BACK | Conditional / verify | Persistent trust anchor and local approved config; operator-only anchor backup/restore with checksum; recovery/retention in deployment doc, no job installed; live qualification pending |
| SYNC | Conditional / verify | Independent live anchor state; mirror applicable approved backups, not live volume |
| CRON | N/A host core | No host cron; future job policy documented; GitHub daily build UTC |
| OPS | Proposed / verify | Health, logs, digest pull, rollback and monitoring docs; exercise on lab then target |

Priority: qualify runtime and supply-chain hardening together for 0.1.0,
including inventory, external refusal probes, privilege/SELinux checks,
backup/restore and safe telemetry. See [hardening](HARDENING.md). Only then
consider service exposure. Full hardening reference is still
needed for final review. The optional monitoring socket grants administration;
explicit approval or a statistics-only design is required before enabling it.
