#!/bin/sh
# Requires a running Compose service and outbound UDP/TCP 53.
set -eu
# POSIX sh for portability on macOS, Debian and CI.
ctl() { docker compose exec -T unbound unbound-control -c /etc/unbound/recursive.conf "$@"; }
dns() { docker compose exec -T unbound timeout -k 2s 25s drill -p 5353 "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
id=$(docker compose ps -q unbound)
[ -n "$id" ] || fail 'service not running'
[ "$(docker compose exec -T unbound id -u)" = 10001 ] || fail 'unexpected UID'
[ "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$id")" = true ] || fail 'root filesystem writable'
[ "$(docker inspect -f '{{.HostConfig.Privileged}}' "$id")" = false ] || fail 'privileged container'
docker inspect -f '{{json .HostConfig.CapDrop}}' "$id" | grep -q 'ALL' || fail 'capabilities'
docker inspect -f '{{json .HostConfig.SecurityOpt}}' "$id" | grep -q 'no-new-privileges' || fail 'no-new-privileges'
# Verify effective container settings, not merely Compose source declarations.
[ "$(docker compose exec -T unbound id -g)" = 10001 ] || fail 'unexpected GID'
[ "$(docker inspect -f '{{.HostConfig.Memory}}' "$id")" = 536870912 ] || fail 'memory limit'
[ "$(docker inspect -f '{{.HostConfig.NanoCpus}}' "$id")" = 1000000000 ] || fail 'CPU limit'
[ "$(docker inspect -f '{{.HostConfig.PidsLimit}}' "$id")" = 64 ] || fail 'PID limit'
[ "$(docker inspect -f '{{.HostConfig.LogConfig.Type}}' "$id")" = local ] || fail 'log driver'
[ "$(docker inspect -f '{{index .HostConfig.LogConfig.Config "max-size"}}' "$id")" = 10m ] || fail 'log rotation size'
[ "$(docker inspect -f '{{index .HostConfig.LogConfig.Config "max-file"}}' "$id")" = 5 ] || fail 'log rotation count'
[ "$(docker inspect -f '{{len .HostConfig.CapAdd}}' "$id")" = 0 ] || fail 'added capabilities'
[ "$(docker inspect -f '{{len .HostConfig.Devices}}' "$id")" = 0 ] || fail 'host devices'
[ "$(docker inspect -f '{{.HostConfig.PidMode}}' "$id")" != host ] || fail 'host PID namespace'
[ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$id")" != host ] || fail 'host network namespace'
[ "$(docker inspect -f '{{.HostConfig.IpcMode}}' "$id")" != host ] || fail 'host IPC namespace'
# Default profile must have no bind mounts (including Docker or control sockets).
# The optional monitoring override requires its own explicit security review.
mount_types=$(docker inspect -f '{{range .Mounts}}{{println .Type}}{{end}}' "$id")
if printf '%s\n' "$mount_types" | grep -qx bind; then fail 'unexpected bind mount in default profile'; fi
# Both bindings must be loopback, without public IPv4/IPv6 publication.
for proto in udp tcp; do
    binding=$(docker port "$id" "5353/$proto")
    case "$binding" in 127.0.0.1:*) ;; *) fail "unsafe $proto publication: $binding";; esac
    [ "$(printf '%s\n' "$binding" | wc -l | tr -d ' ')" = 1 ] || fail 'multiple bindings'
done
docker compose exec -T unbound /usr/local/bin/healthcheck.sh || fail "local UDP health"
docker compose exec -T unbound /usr/local/bin/healthcheck.sh --tcp || fail "local TCP health"
# Reject unexpected BIND, LMDB or XML packages in the actual image.
packages=$(docker compose exec -T unbound dpkg-query -W -f '${db:Status-Abbrev}\t${binary:Package}\n') || fail "package inventory"
printf '%s\n' "$packages" | "$(dirname "$0")/package-policy.sh" || fail "runtime dependency policy"
# Signed root DNSKEY: verifies recursion and validation without a third-party test zone.
valid=$(dns -t -D . @127.0.0.1 DNSKEY)
printf '%s\n' "$valid" | grep -q '^;; ->>HEADER<<-.*rcode: NOERROR,' || fail 'root resolution'
printf '%s\n' "$valid" | grep -E '^;; flags:.*[[:space:]]ad([[:space:]]|;)' >/dev/null || fail 'DNSSEC AD flag'
# Public deliberately broken domain, an external dependency of the test only.
bogus=$(dns -D dnssec-failed.org. @127.0.0.1 A)
printf '%s\n' "$bogus" | grep -q '^;; ->>HEADER<<-.*rcode: SERVFAIL,' || fail 'bogus DNSSEC not rejected'
# Ensure SERVFAIL really reflects validation rather than missing network/domain.
cd_reply=$(dns -D -o CD dnssec-failed.org. @127.0.0.1 A)
printf '%s\n' "$cd_reply" | grep -q '^;; ->>HEADER<<-.*rcode: NOERROR,' || fail 'bogus fixture unavailable with CD'
ctl status >/dev/null
before=$(ctl stats_noreset | sed -n 's/^total.num.cachehits=//p')
[ -n "$before" ] || fail 'cache counter unavailable'
dns -t -D . @127.0.0.1 DNSKEY >/dev/null
dns -t -D . @127.0.0.1 DNSKEY >/dev/null
after=$(ctl stats_noreset | sed -n 's/^total.num.cachehits=//p')
[ "$after" -gt "$before" ] || fail 'cache hits did not increase'
echo 'PASS: local UDP/TCP, DNSSEC, cache, control, dependency policy, container settings and published ports'
