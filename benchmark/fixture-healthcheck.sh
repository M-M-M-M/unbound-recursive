#!/bin/sh
# Only query the synthetic local record; no external DNS dependency.
set -eu
case $# in
    0) set -- -u ;;
    1) [ "$1" = --tcp ] || exit 2; set -- -t ;;
    *) exit 2 ;;
esac
# Bound the probe independently of Docker's HEALTHCHECK timeout (5 seconds).
reply=$(LC_ALL=C timeout -k 1s 3s drill "$@" -p 5354 bench.test. @127.0.0.1 A) || exit 1
# drill prints a full DNS message, not dig's +short format. Only accept the
# expected IN A record in the answer section of a successful reply.
printf '%s\n' "$reply" | LC_ALL=C awk '
    /^;; ->>HEADER<<-/ { headers++; if ($0 ~ /rcode: NOERROR,/) success++ }
    /^;; flags:/ { flags++; if ($0 ~ /[[:space:]]qr([[:space:]]|;)/ && $0 !~ /[[:space:]]tc([[:space:]]|;)/) response++ }
    /^;; ANSWER SECTION:/ { answer = 1; next }
    /^;; .*SECTION:/ { answer = 0 }
    answer && NF && $0 !~ /^;/ {
        records++
        if (NF == 5 && $1 == "bench.test." && $2 ~ /^[0-9]+$/ && $3 == "IN" && $4 == "A" && $5 == "192.0.2.80") matches++
    }
    END { exit !(headers == 1 && success == 1 && flags == 1 && response == 1 && records == 1 && matches == 1) }
'
