# Vulnerability policy and exceptions

The gate evaluates the full Trivy JSON report for each native architecture. No
`--ignore-unfixed` filtering is used. `policy.json` sets whether unfixed HIGH
findings warn or block. The shipped setting is `warn`; change it to `block` for
a stricter deployment policy. HIGH/CRITICAL with a reported fixed version always
block, regardless of exceptions. Unfixed CRITICAL blocks unless a reviewed,
exact exception matches. LOW/MEDIUM are informational; UNKNOWN warns. Scanner,
report, policy, or exception validation failures block. Review all warnings
before approving a production digest; a green CI run is not that approval.

`exceptions.json` initially has no approved exceptions. Each exception must
identify one CVE, Debian binary package, exact installed package version and
severity, with a nonempty justification, Debian tracker URL, approver, approval
and expiry dates (UTC), and mitigations. Expiry is exclusive: an exception stops
being valid at 00:00 UTC on `expires_on`. Lifetime is at most 90 days (or a
shorter policy limit). Expired entries block even when unused; remove or review
them explicitly. An exception never waives a reported available fix or a
non-OS-package finding. Changes require review by a human with authority to
accept the risk; the `approved_by` field is an audit record, not authentication.
Use protected branches and reviewed PRs for security policy changes. Never
commit secrets in this file.

Example **illustrative only**, not an approved exception (replace every value
with reviewed evidence; the sample dates and package are not deployable):

```json
{
  "schema_version": 1,
  "exceptions": [
    {
      "cve": "CVE-2099-1234",
      "package": "libexample",
      "installed_version": "1.2.3-1",
      "severity": "CRITICAL",
      "justification": "Document verified reachability and residual risk.",
      "advisory": "https://security-tracker.debian.org/tracker/CVE-2099-1234",
      "approved_by": "reviewer identity",
      "approved_on": "2099-01-01",
      "expires_on": "2099-01-15",
      "mitigations": "Document verified compensating controls."
    }
  ]
}
```

Run locally from any directory with core Perl (5.26+):

```sh
perl scripts/vulnerability-gate.pl --summary security-summary.md vulnerabilities.json
prove -v tests/vulnerability-gate.t
```

The default policy and exception paths are relative to the gate script. Optional
`--policy` and `--exceptions` arguments support offline review and fixtures.
GitHub Actions writes a summary automatically via `GITHUB_STEP_SUMMARY`.
Counts distinguish unique vulnerability IDs from package-level findings.
Keep complete JSON, package inventory and SBOM as review evidence. For every
critical finding, consult the Debian tracker, inspect installed version, assess
reachability and mitigations, and choose patch, package removal, or documented
risk acceptance. A low Debian priority alone does not prove non-exploitability.
