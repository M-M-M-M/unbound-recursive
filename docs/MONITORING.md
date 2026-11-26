# Monitoring and logging

Core metrics use `extended-statistics: yes`, cumulative counters and
`unbound-control stats_noreset`. The local Unix control socket is not published.
Use `make stats` or the documented operator command for immediate inspection.
Telegraf native `inputs.unbound` is optional and needs a compatible
`unbound-control` binary on the monitoring host. Do not grant Docker access.

## Optional host Telegraf (Linux, trusted management boundary only)

The control socket grants **administrative control**, not just read-only stats;
a read-only bind mount does not make socket commands read-only. Only use this
example after explicitly approving the monitoring account for that capability.
A stats-only exporter is planned for installations with a stricter boundary.
Keep the socket inaccessible to network clients. Do not set use_sudo=true.

1. Check numeric UID/GID 10001 availability, Telegraf identity and SELinux.
   Provision a dedicated private `CONTROL_DIR` owned by the approved container
   UID/GID, mode 0750, with protected parents; do not chown existing directories.
   Grant only the approved monitor traversal and socket access (group/ACL),
   confirm effective socket mode after startup and verify untrusted-user denial.
2. Set CONTROL_DIR to the absolute local runtime path, then use
   `docker compose -f compose.yaml -f monitoring/compose.control.yaml config`
   and `... up -d --wait` (replace `...` with the same Compose prefix). This
   override replaces the default socket tmpfs with a private bind mount. Check
   effective mounts, SELinux labels and restart/stale-socket behavior. Compose
   2.24.4+ is required for the !override tag.
3. Install the client config from `monitoring/unbound-control.conf` with the
   actual socket path, and `monitoring/telegraf.conf` into the approved Telegraf
   configuration. Leave the plugin's server unset so it uses the config file.
   Test `unbound-control -c /etc/telegraf/unbound-control.conf stats_noreset`
   as the actual monitoring identity, then test the Telegraf input with the
   existing service configuration. Never print output credentials.
4. Import `monitoring/grafana-flux.json`, choose the Flux datasource and bucket.
   This is a starter dashboard for InfluxDB 2.x, not yet validated against a
   running Grafana. Check field names and tags against installed Telegraf.
   Counter rates require nonnegative differences/derivatives per host; restart
   and missing samples are not zero traffic. Don't add overlapping protocol
   counters (TCP includes TLS/HTTPS in versions that count them that way).

Recommended alerts: no data or failed external DNS probe, SERVFAIL rate,
requestlist exceeded, cache behavior, latency, CPU/memory and disk. Use existing
Telegraf host metrics and alert routing. Observe before setting thresholds.

## Logs and storage

Default query/reply logs off. Docker local driver rotates 5 x 10 MB nominal
per container, compressed by default; metadata/transient overhead can vary.
Inspect `docker compose logs --tail=100`. Avoid reading Docker log files directly.
For detailed diagnostics, use an approved short window, explicit quotas, rotation
and access controls; turn logging off again. An attack can fill an unbounded disk.

At an assumed 250 bytes per query/response transaction, 5 queries/s generates
108 MB/day per server before compression; 100 q/s yields 2.16 GB/day. Two servers
at 5 q/s each generate 216 MB/day total. Exact size must be measured. Retention
proposals: 365 days aggregate statistics, 7 days bounded source-IP aggregates,
30 days bounded security events, 24–72 h optional detailed logs (off by default).
Use separate buckets/retention and quotas; do not create permanent tags for every
source IP or query domain. No raw domain or URL secret logging by default.

## Client-level security telemetry (planned)

Unbound aggregate stats do not identify each client. Evaluate PowerDNS dnsdist in front
of the private backend, or dnstap if appropriate, after checking Debian build
features. Preserve actual source identity (NAT can hide it; trust proxy metadata
only from authorized proxies). Aggregate IP, transport, query type, count,
response codes and rate-limit events within bounded windows. Use fixed budgets,
short retention, cap distinct clients and sample/drop excess events. Avoid
collecting domain names unless explicitly necessary. Prefer observation, then
short reversible blocks with exemptions and false-positive review. Do not
assume a source IP proves identity; NAT may aggregate innocent users. Network
filtering is still the primary defense.

References: https://github.com/influxdata/telegraf/tree/master/plugins/inputs/unbound
and https://docs.docker.com/engine/logging/drivers/local/.

## Preferred stats-only file handoff (dev9, qualification pending)

An approved operator collects the local `stats_noreset` output with the
existing administrative mechanism and passes it to `monitoring/export-stats.pl`.
Telegraf reads only the atomically published Influx line-protocol file, never
Docker or the Unbound administration socket. The exporter allows a fixed list
of aggregate numerical fields, refuses malformed/missing required fields and
leaves the last snapshot unchanged on failure. It does not collect IP addresses,
queries or secrets. It publishes a source timestamp so re-reading a stale file
must not falsely indicate fresh samples. Use a dedicated protected setgid
metrics directory (operator write, Telegraf group read/traverse only; mode 2750
with the approved group). Never allow Telegraf to replace the file or directory.

Example for an authorized operator (run from the reviewed deployment directory):

```sh
# Use a protected temporary file and require successful Docker command first.
umask 077
tmp=$(mktemp)
if docker compose -f compose.yaml exec -T unbound unbound-control \
    -c /etc/unbound/recursive.conf stats_noreset > "$tmp"; then
  perl monitoring/export-stats.pl /path/to/approved/metrics/unbound.lp < "$tmp"
fi
rm -f "$tmp"
```

Use the approved job runner with locking, failure alerts and cleanup trap for
scheduled execution (suggest 30 s; measure before enabling). No scheduler or
privileged access is installed by this project. A failure of collection must be
reported; retain the prior snapshot and alert on stale/missing data. Install
`monitoring/telegraf-file.conf` with the actual local path, and import
`monitoring/grafana-snapshot-flux.json`. The separate `unbound_snapshot`
measurement avoids field type collisions with the native plugin. Fields are
exported as line-protocol floats; validate precision and counter behavior at
expected scale. Use one collection identity/host per instance. Never run both
collectors without explicit dashboard/alert separation.

Qualification: run `prove -v tests/export-stats.t`; then on a test Linux host
collect real output, inspect line protocol and verify `telegraf --test` with
an isolated config as the actual Telegraf user. Verify file mode and denied
write/socket/Docker access, field names, timestamp handling, and InfluxDB bucket
retention. Import the dashboard, generate queries, observe rates and latency,
stop/restart the resolver, test stale timestamps and alerts. No Grafana or
Telegraf daemon was available in the dev9 preparation environment.
