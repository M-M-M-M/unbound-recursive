# Supply-chain security

Development snapshot only; live CI qualification and operator approval are
required before a release. No new scanner or signing tool runs inside Unbound.

## CI policy

Both native architectures are built and tested before scanning. Trivy 0.70.0
produces a JSON vulnerability report and a CycloneDX SBOM for each local image.
Dev7 applies the [reviewed vulnerability policy](../security/README.md).
HIGH/CRITICAL with an available fix block; unfixed CRITICAL blocks unless an
exact, time-limited, reviewed exception applies. Unfixed HIGH warns by default
(configurable to block). No exceptions are approved in this snapshot. Missing
or invalid reports/policies block; LOW/MEDIUM remain informational and UNKNOWN
warns. Do not treat an accepted scan as a production release approval. The
Dockerfile upgrades installed Debian packages before installing dependencies.
The full Trivy JSON, SBOM, dpkg package inventory and uncompressed image size
(in bytes, per architecture) are retained as evidence;
the gate adds a GitHub step summary. The re-scan uses the same policy.
The evidence artifacts expire after 30 days; retain approved release evidence
in the protected operator archive. Tool and database availability failures are
build failures. The database is refreshed normally; CI cache is disabled.

Only the main-branch publish job has attestation and OIDC permissions;
the separate promotion job has package-write permission. It receives tested image archives, verifies their checksums and
image IDs, pushes platform candidates and checks their remote config digests.
Platform manifests receive GitHub CycloneDX attestations. The multi-platform
candidate receives GitHub build provenance and a keyless Cosign signature;
its signature is checked. A separate read-only consumer job with fresh
registry configuration verifies the signature, provenance and both platform
SBOMs through Cosign before the promotion job can update `latest` and the
numbered build tag. No registry login is used in the consumer job. Candidate/platform tags are not qualified releases. A failed gate leaves
previous `latest` unchanged (except a failure during the final promotion itself,
which requires checking the resulting tag). PRs cannot publish. No permanent
signing key or external registry credential is necessary.

The separate daily re-scan workflow resolves the current public `latest` once
and scans that immutable digest on both platforms without pushing anything.
Manual workflow dispatch optionally accepts an exact deployed manifest digest. A failed scan is an alert,
not automatic removal or rollback. Configure GitHub notifications and monitor
actual deployed digests separately; `latest` is not necessarily what runs in
production. Each report records the image ID and registry digest inspected.

## Verify before pull

Install trusted Cosign 3.1.4 (or a reviewed compatible newer version), Docker
with Buildx and Perl on the operator machine, not in the resolver. The public
GHCR package requires neither GitHub CLI nor a GitHub account/token. Cosign
retrieves the OCI-attached attestations already produced by `actions/attest`.
No permanent private signing key is needed. The verifier requires the exact
Fulcio certificate identity for the project build workflow on `main`, GitHub
OIDC issuer and the requested digest; normal Sigstore trust and transparency
checks remain enabled. The SLSA CUE policy checks the signed source workflow,
ref and `github-hosted` runner environment. This predicate check is not the
same as independently checking the runner certificate extension; SBOMs are
checked for the exact signer and platform digest, not for that extension.
Only the reviewed hosted-runner workflow may publish. Do not loosen identity,
claim or transparency verification to make an old image pass.

```sh
./scripts/deploy.pl verify latest
# Or an exact approved manifest digest:
./scripts/deploy.pl verify sha256:REPLACE_WITH_APPROVED_DIGEST
```

The helper resolves a tag once, verifies an actual v3 container signature
(not merely a signed provenance object), checks SLSA provenance for the index,
and verifies the CycloneDX attestations for its two immutable platform digests.
The CUE policy is evaluated by Cosign itself; no standalone CUE tool is needed.
Use the returned immutable reference for the pull. Check the CI reports, actual
SBOM content, risk review and release approval independently. If any check
fails, stop. Earlier unsigned or incompatible snapshots are not accepted.
The dev8 digest is a candidate for migration testing; full anonymous attestation
verification against that existing digest has not yet been demonstrated.

See [Cosign v3.1.4 verify-attestation](https://github.com/sigstore/cosign/blob/v3.1.4/doc/cosign_verify-attestation.md)
and [GitHub attest](https://github.com/actions/attest) for the upstream interfaces.

## Dependencies and limitations

Direct workflow actions are pinned to full commits from upstream releases, with
version comments for Dependabot. Review its PRs before merging; pins do not
prove the absence of malicious code or secure all transitive downloads. Trivy
and Cosign are installed by their pinned upstream actions at explicit versions;
review installer verification and future security advisories. References:
[Trivy action](https://github.com/aquasecurity/trivy-action/releases/tag/v0.36.0),
[Cosign installer](https://github.com/sigstore/cosign-installer/releases/tag/v4.1.3),
[GitHub attest](https://github.com/actions/attest/releases/tag/v4.2.2).
The Dockerfile pins `debian:trixie-slim` to the shared index digest
`sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0`,
observed in both successful dev8 build logs. Dependabot Docker checks weekly;
review digest-update PRs, upstream changes, both native builds and CVE reports
before merging. Daily no-cache builds still upgrade/install current signed
Debian packages; this is not a fully reproducible package snapshot. Do not
automatically replace an approved base pin. Provenance
records the workflow and commit; it does not establish bit-for-bit reproducibility
or certify source safety. Dev8 end-to-end signing and promotion passed in CI; the operator independently
verified Cosign from macOS. Dev10 replaces the dev9 GitHub CLI path with
Cosign-only provenance and both platform SBOM checks. The new independent
consumer gate and revised re-scan still need live qualification. See [verified upgrades](UPGRADING.md)
and [vulnerability triage](VULNERABILITY-REVIEW.md).
