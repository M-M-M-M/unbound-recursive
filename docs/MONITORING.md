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
Prefer the stats-only exporter below for installations with a stricter boundary.
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


### Freshness check (InfluxDB 2.x / Flux)

Use the source timestamp, not the Telegraf poll time, to alert on stale data.
For a 30-second export interval, a starting threshold is 120 seconds. The
following example returns the age in seconds of the last query-counter sample
for each host; configure Grafana to alert on age > 120 and on No Data/Error.
Set the actual bucket and verify per-host alert labels. Do not aggregate across
hosts before finding the last sample: a healthy host could hide a failed one.

```flux
from(bucket: "YOUR_BUCKET")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "unbound_snapshot" and
      r._field == "total_num_queries" and r.service == "unbound-recursive")
  |> group(columns: ["host"])
  |> last()
  |> map(fn: (r) => ({r with _value: float(v: int(v: now()) - int(v: r._time)) / 1000000000.0}))
```

This query is a proposed alert recipe, not a tested Grafana alert. With a
completely missing host, a per-host series may disappear; configure an expected
host inventory or independent per-host probe as well. Dev10's disposable
signed-deployment lab exports actual stats during the update test. It does not
install Telegraf or write to any operator InfluxDB instance.

## dev13 disposable end-to-end lab

After `make build`, run `make test-monitoring` from the project root as a
non-root Docker operator with Compose v2 and curl. The lab uses fixed-version
third-party image tags (InfluxDB 2.7.12, Telegraf 1.38.4, Grafana 12.4.16);
these are test dependencies, not security-qualified production images or
immutable digest pins. The test builds on the local resolver image, generates
random disposable credentials, allocates a unique project, isolated networks
and named volumes, and publishes only an ephemeral loopback Grafana port.
No existing monitoring service, bucket, resolver port, volume or secrets are
reused. The lab uses a temporary admin token for convenience; production
must use separate bucket-scoped read/write tokens and protected secret files.
The lab destroys its own containers/networks/volumes when done. It reports
cleanup failure rather than removing unrelated resources. Pulls may require
several hundred MB; use a disposable Docker environment. Do not run against
an untrusted remote Docker context. Linux bind permissions/SELinux must be
reviewed separately. The independent **Qualify stats-only monitoring** Actions
workflow runs on AMD64 and can be launched manually.

The test checks exact source timestamps, repeated reads merging into the same
InfluxDB point, a new point after collection, positive query rate, read-only
Telegraf, provisioning and Flux execution for all dashboard panels, a real
resolver restart, and stale data after a failed collection. It does not certify
browser rendering, notification delivery, long-term retention expiry, or
production security of the lab images.

## Integrate with an existing monitoring stack

From the approved resolver deployment directory, as the authorized operator:

```sh
perl monitoring/collect-stats.pl /path/to/protected/metrics/unbound.lp
```

This helper locks each destination, rejects concurrent collection, checks
Docker exit status and passes only complete output to the atomic exporter.
Schedule it every 30 seconds using the existing approved scheduler; enforce a
job timeout, capture nonzero exits, and keep its lock file in the protected
metrics directory. Do not grant Docker access to Telegraf. Set the read-only
file path in `monitoring/telegraf-file.conf`; the parser explicitly expects ns
precision. Preserve the source timestamp. Configure a unique stable `host`
tag per resolver; do not use arbitrary query names or client IPs as tags.
Use a write-only bucket token for Telegraf and a separate read-only bucket
token for Grafana. Import `grafana-snapshot-flux.json` and select the existing
Flux datasource and bucket. See official configuration references:
https://docs.influxdata.com/telegraf/v1/data_formats/input/influx/ and
https://grafana.com/docs/grafana/latest/administration/provisioning/.

### Proposed alert rules (configure explicitly, do not auto-install)

| Signal | Initial rule | Caveat |
| --- | --- | --- |
| Availability | Independent DNS probe fails twice | A local health record is liveness only; also probe signed recursion from an authorized client |
| Freshness | Latest source age > 120 s; evaluate every 30 s | Set No Data/Error alerting and per-expected-host missing-series handling |
| SERVFAIL | Sustained nonzero rate above the observed normal baseline | DNSSEC rejection can be expected; review threshold before notifying |
| Latency | Average recursion > 0.25 s for 5 min as starting point | Not a percentile, no recursion samples is not zero latency |
| Cache | Sustained low hit ratio with sufficient query volume | No denominator means no sample, not 0%; workload dependent |

For freshness use the Flux query above with a concrete bucket, not dashboard
variables, and per-host evaluation. For latency use the dashboard average
recursion field with a fixed 5-minute range, reduce to last/mean as appropriate,
and evaluate only when recent recursive replies exist. Use a fixed expected
host inventory/independent probe: a missing series can disappear from a group.
Verify alert firing, recovery, No Data/Error and routing with a test contact
point before production. The dashboard drops negative counter deltas before
windowing and the cache ratio uses uptime to reject observable resets. A reset
followed by a larger counter or uptime before the next sample can be hidden;
exact event accounting across unobserved restarts is not guaranteed. Rate
values are sampled estimates. The average recursion time is a cumulative
Unbound statistic, not a measured latency percentile or probe duration.

At one source snapshot every 30 s, expect 2,880 points per resolver/day (one
point with multiple fixed fields), or 1,051,200 per 365 days. Identical
re-reads should overwrite, not add points. Measure line-protocol bytes per
snapshot from the lab and multiply by points for a wire-volume estimate;
InfluxDB disk footprint, indexes, WAL and compaction differ. Measure actual
bucket growth on a representative test host before choosing retention. A 24h
lab bucket is intentionally separate from any production retention proposal.

## Interactive development lab (dev14)

Run from a local Docker context as a non-root operator. `make build` first.
This lab is separate from the production Compose project and from the
one-shot integration test. It uses a generated project name and random
credentials stored in the ignored, owner-only `.monitoring-lab/` directory.
It binds Grafana to a dynamically assigned IPv4 loopback port only.

```sh
make monitoring-start   # start or resume; prints Grafana URL and lab password
make monitoring-open    # print login; open browser on macOS
make monitoring-traffic # foreground, collect and send synthetic DNS requests
# In a second terminal:
make monitoring-status
make monitoring-logs
make monitoring-usage   # InfluxDB data/config size in KiB, live snapshot
# Ctrl+C in the traffic terminal first, then:
make monitoring-stop    # keep volumes, credentials and history
make monitoring-clean   # remove ONLY this disposable lab and all its history
```

Stop traffic before stop/clean; lifecycle commands refuse concurrent mutation.
The traffic loop runs in the foreground, not in an installed daemon or cron.
Without it the last collection becomes stale, as expected. `monitoring-clean`
is explicitly destructive for the disposable lab only and is not `make purge`.
No production resolver state or monitoring credentials are used. Keep the lab
identity file intact until clean succeeds. A new version of the lab's Compose
or dashboard is copied only at first creation; clean and restart to adopt
new definitions. The 24-hour retention setting is not a verified expiry test.
`monitoring-usage` includes storage overhead and does not by itself establish
per-day growth; measure before and after a controlled interval. Do not publish
logs or credentials. Visualizing the separate benchmark workload in Grafana
requires a later integration; do not interpret synthetic liveness traffic as a
performance test.
