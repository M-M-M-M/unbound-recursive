COMPOSE = docker compose -f compose.yaml -f compose.build.yaml
export BACKUP_DIR
export BACKUP_SET
.PHONY: build start test logs stop restart clean purge stats backup-state restore-state test-state test-state-bind test-unit test-all digest test-monitoring
build:
	$(COMPOSE) build --pull --no-cache
start:
	UNBOUND_IMAGE=unbound-recursive:dev ./scripts/state.sh check
	$(COMPOSE) up -d --wait
# Tests use the same Compose project; no host dig dependency.
test:
	RUN_DOCKER_TESTS=1 prove -v tests/integration.t
logs:
	$(COMPOSE) logs --tail=100 unbound
stats:
	$(COMPOSE) exec -T unbound unbound-control -c /etc/unbound/recursive.conf stats_noreset
stop:
	$(COMPOSE) stop
restart:
	UNBOUND_IMAGE=unbound-recursive:dev ./scripts/state.sh check
	$(COMPOSE) restart unbound
clean:
	$(COMPOSE) down
purge:
	UNBOUND_IMAGE=unbound-recursive:dev ./scripts/state.sh purge
backup-state:
	UNBOUND_IMAGE=unbound-recursive:dev ./scripts/state.sh backup
restore-state:
	UNBOUND_IMAGE=unbound-recursive:dev ./scripts/state.sh restore
test-unit:
	RUN_DOCKER_TESTS=0 prove -v tests/vulnerability-gate.t tests/state-mock.t tests/confirmation.t tests/healthcheck.t tests/package-policy.t tests/deploy.t tests/export-stats.t tests/collect-stats.t tests/benchmark.t tests/benchmark-lab.t tests/benchmark-profiles.t tests/benchmark-identity.t tests/benchmark-async.t tests/benchmark-resources.t tests/monitoring-alert-config.t tests/benchmark-metrics.t tests/fixture-healthcheck.t tests/local-docker.t tests/command-runner.t tests/soak-verdict.t
test-state:
	RUN_DOCKER_TESTS=1 prove -v tests/state-live.t
test-state-bind:
	RUN_DOCKER_TESTS=1 TEST_STATE_MODE=bind prove -v tests/state-live.t
test-all:
	RUN_DOCKER_TESTS=1 prove -v tests/*.t

# Discovery only; deploy.pl verify is still required for approval.
digest:
	@perl scripts/deploy.pl digest latest

test-monitoring:
	RUN_MONITORING_LIVE=1 prove -v tests/monitoring-live.t

.PHONY: monitoring-start monitoring-open monitoring-traffic monitoring-status monitoring-logs monitoring-usage monitoring-retention monitoring-alerts monitoring-stop monitoring-clean
monitoring-start monitoring-open monitoring-traffic monitoring-status monitoring-logs monitoring-usage monitoring-retention monitoring-alerts monitoring-stop monitoring-clean:
	perl monitoring/labctl.pl $(@:monitoring-%=%)

.PHONY: benchmark test-benchmark
benchmark:
	perl benchmark/run.pl
test-benchmark:
	perl benchmark/run.pl --quick

.PHONY: test-network
test-network:
	RUN_NETWORK_LIVE=1 prove -v tests/network-live.t

.PHONY: benchmark-production benchmark-ratelimit benchmark-stress benchmark-soak benchmark-soak-day benchmark-soak-check benchmark-soak-1000 benchmark-soak-10000
benchmark-production benchmark-ratelimit benchmark-stress benchmark-soak benchmark-soak-day benchmark-soak-check benchmark-soak-1000 benchmark-soak-10000:
	perl benchmark/run.pl --profile $(@:benchmark-%=%)

.PHONY: benchmark-monitoring
export REPORT
benchmark-monitoring:
	perl monitoring/labctl.pl benchmark-import "$$REPORT"

.PHONY: test-monitoring-operations
test-monitoring-operations:
	RUN_MONITORING_LIVE=1 RUN_MONITORING_OPERATIONS=1 prove -v tests/monitoring-live.t

.PHONY: test-monitoring-retention
test-monitoring-retention:
	RUN_MONITORING_LIVE=1 RUN_MONITORING_OPERATIONS=retention prove -v tests/monitoring-live.t
