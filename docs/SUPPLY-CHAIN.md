# Supply-chain security

Development snapshot only; live CI qualification and operator approval are
required before a release. No new scanner or signing tool runs inside Unbound.

## CI policy

Both native architectures are built and tested before scanning. Trivy 0.70.0
produces a JSON vulnerability report and a CycloneDX SBOM for each local image.
The initial conservative gate blocks **all HIGH and CRITICAL** findings,
including unfixed findings, and rejects missing/invalid reports. Do not bypass
this policy to get a green build. Review Debian advisories and scanner false
positives; any future exception must be narrowly scoped, justified, approved,
time-limited and recorded. MEDIUM and LOW findings remain in the full report.
The evidence artifacts expire after 30 days; retain approved release evidence
in the protected operator archive. Tool and database availability failures are
build failures. The database is refreshed normally; CI cache is disabled.

Only the main-branch publish job has package-write, attestation and OIDC
permissions. It receives tested image archives, verifies their checksums and
image IDs, pushes platform candidates and checks their remote config digests.
Platform manifests receive GitHub CycloneDX attestations. The multi-platform
candidate receives GitHub build provenance and a keyless Cosign signature;
its signature is checked before promotion to `latest` and the numbered build
tag. Candidate/platform tags are not qualified releases. A failed gate leaves
previous `latest` unchanged (except a failure during the final promotion itself,
which requires checking the resulting tag). PRs cannot publish. No permanent
signing key or external registry credential is necessary.

The separate daily re-scan workflow checks the currently published public
`latest` on each platform without pushing anything. A failed scan is an alert,
not automatic removal or rollback. Configure GitHub notifications and monitor
actual deployed digests separately; `latest` is not necessarily what runs in
production. Each report records the image ID and registry digest inspected.

## Verify before pull

Install trusted Cosign 3.1.4 (or a reviewed newer version) and GitHub CLI on the
operator machine, not in the resolver. Replace the placeholder below with the
approved immutable multi-platform digest from a successful CI run. Do not
verify one tag and pull another. No `--insecure-ignore-tlog` or broad identity
regex is acceptable.

```sh
IMAGE='ghcr.io/m-m-m-m/unbound-recursive@sha256:REPLACE_WITH_APPROVED_DIGEST'
cosign verify \
  --certificate-identity 'https://github.com/M-M-M-M/unbound-recursive/.github/workflows/build.yaml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$IMAGE"
gh attestation verify "oci://$IMAGE" --repo M-M-M-M/unbound-recursive \
  --signer-workflow M-M-M-M/unbound-recursive/.github/workflows/build.yaml \
  --source-ref refs/heads/main
```

Inspect the manifest with `docker buildx imagetools inspect "$IMAGE"`. To verify
a platform SBOM, substitute that platform's manifest digest (not the index) and
run `gh attestation verify "oci://$PLATFORM_IMAGE" --repo M-M-M-M/unbound-recursive
--predicate-type https://cyclonedx.org/bom --signer-workflow
M-M-M-M/unbound-recursive/.github/workflows/build.yaml --source-ref refs/heads/main`
(on one line). Check the predicate, image digest and expected inventory. If any
verification fails, stop. Set the exact verified `UNBOUND_IMAGE` in the protected
`.env`; follow [deployment](DEPLOYMENT.md). Earlier unsigned snapshots will
fail verification and must not be accepted as signed releases.

## Dependencies and limitations

Direct workflow actions are pinned to full commits from upstream releases, with
version comments for Dependabot. Review its PRs before merging; pins do not
prove the absence of malicious code or secure all transitive downloads. Trivy
and Cosign are installed by their pinned upstream actions at explicit versions;
review installer verification and future security advisories. References:
[Trivy action](https://github.com/aquasecurity/trivy-action/releases/tag/v0.36.0),
[Cosign installer](https://github.com/sigstore/cosign-installer/releases/tag/v4.1.3),
[GitHub attest](https://github.com/actions/attest/releases/tag/v4.2.2).
The base image tag `debian:trixie-slim` and current Debian package repositories
remain intentionally refreshed in this development build. A reviewed base digest
and controlled refresh procedure are still mandatory release gates. Provenance
records the workflow and commit; it does not establish bit-for-bit reproducibility
or certify source safety. End-to-end signing, registry attestation discovery and
verification have not been exercised in the archive preparation environment.
