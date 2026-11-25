COMPOSE = docker compose -f compose.yaml -f compose.build.yaml
export BACKUP_DIR
export BACKUP_SET
.PHONY: build start test logs stop restart clean purge stats backup-state restore-state test-state test-unit test-all
build:
	$(COMPOSE) build --pull --no-cache
start:
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
	RUN_DOCKER_TESTS=0 prove -v tests/vulnerability-gate.t tests/state-mock.t
test-state:
	RUN_DOCKER_TESTS=1 prove -v tests/state-live.t
test-all:
	RUN_DOCKER_TESTS=1 prove -v tests/*.t
