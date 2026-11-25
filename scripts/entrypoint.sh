#!/bin/sh
set -eu
umask 027
# Do not reset RFC 5011 state on rebuild. Fail if the existing file is empty.
if [ ! -e /state/root.key ]; then
    tmp=$(mktemp /state/root.key.XXXXXX)
    trap 'rm -f "$tmp"' EXIT HUP INT TERM
    cp /usr/share/dns/root.key "$tmp"
    chmod 0640 "$tmp"
    mv "$tmp" /state/root.key
    trap - EXIT HUP INT TERM
fi
[ -s /state/root.key ] && [ -w /state/root.key ] && [ -w /state ] || {
    echo 'DNSSEC trust-anchor state is missing or not writable' >&2; exit 1;
}
/usr/sbin/unbound-checkconf /etc/unbound/recursive.conf
exec /usr/sbin/unbound -d -c /etc/unbound/recursive.conf
