// Validate signed SLSA predicate, in addition to Cosign certificate and subject checks.
// Required fields must be present, not inferred from missing input.
predicate!: {
    buildDefinition!: {
        externalParameters!: workflow!: {
            repository!: "https://github.com/M-M-M-M/unbound-recursive"
            path!: ".github/workflows/build.yaml"
            ref!: "refs/heads/main"
        }
        internalParameters!: github!: {
            runner_environment!: "github-hosted"
        }
    }
}
