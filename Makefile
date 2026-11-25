COMPOSE = docker compose -f compose.yaml -f compose.build.yaml
export BACKUP_DIR
export BACKUP_SET
.PHONY: build start test logs stop restart clean purge stats backup-state restore-state
build:
	$(COMPOSE) build --pull --no-cache
start:
	$(COMPOSE) up -d --wait
# Tests use the same Compose project; no host dig dependency.
test:
	./tests/integration.sh
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
	./scripts/state.sh purge
backup-state:
	./scripts/state.sh backup
restore-state:
	./scripts/state.sh restore
