#!/bin/sh
# Read-only dependency and feature evidence inside the exact local image.
set -eu
export LC_ALL=C
printf '\n== Installed package dependencies (TSV) ==\n'
dpkg-query -W -f='${db:Status-Abbrev}\t${binary:Package}\t${Version}\t${source:Package}\t${Pre-Depends}\t${Depends}\t${Recommends}\n'
printf '\n== Actual dynamic linkage ==\n'
for binary in unbound unbound-control drill; do
    path=$(command -v "$binary")
    printf '\n-- %s --\n' "$path"
    dependencies=$(ldd "$path")
    printf '%s\n' "$dependencies"
    case $dependencies in *'not found'*) exit 1 ;; esac
done
printf '\n== Unbound build and effective configuration ==\n'
unbound -V 2>&1
cp /usr/share/dns/root.key /state/root.key
for option in module-config do-ip6 do-udp do-tcp val-permissive-mode harden-dnssec-stripped; do
    printf '%s: ' "$option"
    unbound-checkconf -o "$option" /etc/unbound/recursive.conf
done
printf '\n== Optional executable presence ==\n'
for binary in dig drill ldns-keygen ldns-signzone ldns-verify-zone python3 perl tcpdump mount nsenter systemd-homed; do
    if path=$(command -v "$binary"); then printf '%s: %s\n' "$binary" "$path"; else printf '%s: absent from PATH\n' "$binary"; fi
done
printf '\n== Archive::Tar installed in perl-base package ==\n'
files=$(dpkg-query -L perl-base)
if printf '%s\n' "$files" | grep '/Archive/Tar\(\.pm\|/\)' ; then :; else printf '%s\n' 'No matching file in perl-base inventory'; fi
printf '\n== Advisory only: simulated removal of LDNS tools and auto dependencies ==\n'
if apt-get -s purge --autoremove ldnsutils; then :; else printf '%s\n' 'Simulation unavailable; inspect installed Depends/Pre-Depends manually'; fi
