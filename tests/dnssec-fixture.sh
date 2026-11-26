#!/bin/sh
# Run only in a disposable, network-none container with a private /tmp tmpfs.
set -eu
export LC_ALL=C
umask 077
cd /tmp
mkdir dnssec-fixture
cd dnssec-fixture
cat > unsigned.zone <<'ZONE'
$ORIGIN validation.test.
$TTL 60
@ IN SOA ns.validation.test. hostmaster.validation.test. 1 3600 600 86400 60
@ IN NS ns.validation.test.
ns IN A 192.0.2.53
good IN A 192.0.2.80
bad IN A 192.0.2.81
ZONE
# Separate KSK/ZSK avoid implementation-specific single-key signing behavior.
ksk=$(ldns-keygen -k -a RSASHA256 -b 2048 validation.test.)
zsk=$(ldns-keygen -a RSASHA256 -b 2048 validation.test.)
ldns-signzone -o validation.test. -f signed.zone unsigned.zone "$ksk" "$zsk"
ldns-verify-zone signed.zone
cp "$ksk.key" trust.key
# Alter exactly one A RR, preserving its original RRSIG and all other RRs.
awk 'BEGIN { OFS="\t" } $1=="bad.validation.test." && $3=="IN" && $4=="A" && $5=="192.0.2.81" { $5="192.0.2.82"; changed++ } { print } END { exit changed!=1 }' signed.zone > altered.zone
if ldns-verify-zone altered.zone; then echo 'altered fixture unexpectedly validates' >&2; exit 1; fi
rm -f -- "$ksk.private" "$zsk.private"
cat > resolver.conf <<'CONF'
server:
    interface: 127.0.0.1
    port: 5353
    do-ip4: yes
    do-ip6: no
    access-control: 127.0.0.0/8 allow
    username: ""
    chroot: ""
    directory: "/tmp/dnssec-fixture"
    pidfile: ""
    use-syslog: no
    do-daemonize: no
    module-config: "validator iterator"
    val-permissive-mode: no
    harden-dnssec-stripped: yes
    local-zone: "test." nodefault
    trust-anchor-file: "/tmp/dnssec-fixture/trust.key"
auth-zone:
    name: "validation.test."
    zonefile: "/tmp/dnssec-fixture/altered.zone"
    for-downstream: no
    for-upstream: yes
    fallback-enabled: no
CONF
unbound-checkconf resolver.conf
unbound -d -c resolver.conf > resolver.log 2>&1 &
pid=$!
cleanup() { kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; cat resolver.log >&2; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
probe() { timeout -k 1s 3s drill -t -D -p 5353 "$@"; }
ready=no
for attempt in $(seq 1 20); do
    if probe good.validation.test. @127.0.0.1 A > good.reply 2>/dev/null; then
        ready=yes; break
    fi
    sleep 1
done
[ "$ready" = yes ]
cat good.reply
/bin/sh /dnssec-reply.sh NOERROR yes good.validation.test. 192.0.2.80 < good.reply
printf '%s\n' 'DNSSEC positive: PASS'
# Do not infer the result from drill's exit status: require an actual SERVFAIL.
probe bad.validation.test. @127.0.0.1 A > bad.reply || :
cat bad.reply
/bin/sh /dnssec-reply.sh SERVFAIL no bad.validation.test. - < bad.reply
printf '%s\n' 'DNSSEC negative: PASS'
# Positive control for the altered RR: with CD the same data must be retrievable.
probe -o CD bad.validation.test. @127.0.0.1 A > cd.reply
cat cd.reply
/bin/sh /dnssec-reply.sh NOERROR no bad.validation.test. 192.0.2.82 < cd.reply
printf '%s\n' 'DNSSEC checking-disabled control: PASS'
