#!/bin/sh
# Validate an isolated TCP DNS response; input is drill's decoded packet.
set -eu
[ "$#" -eq 4 ] || exit 2
LC_ALL=C awk -v code="$1" -v ad="$2" -v owner="$3" -v ip="$4" '
    /^;; ->>HEADER<<-/ { headers++; if (index($0,"rcode: " code ",")) success++ }
    /^;; flags:/ {
        flags++
        if ($0 ~ /[[:space:]]qr([[:space:]]|;)/ && $0 !~ /[[:space:]]tc([[:space:]]|;)/ &&
            (($0 ~ /[[:space:]]ad([[:space:]]|;)/) == (ad == "yes"))) response++
    }
    /^;; ANSWER SECTION:/ { answer=1; next }
    /^;; .*SECTION:/ { answer=0 }
    answer && NF && $0 !~ /^;/ {
        if ($4 == "A") { records++; if (NF==5 && $1==owner && $2 ~ /^[0-9]+$/ && $3=="IN" && $5==ip) matches++ }
        else if ($4 != "RRSIG" || $1 != owner || $3 != "IN" || $5 != "A") unexpected++
        total++
    }
    END {
        valid = headers==1 && success==1 && flags==1 && response==1 && !unexpected
        if (code=="SERVFAIL") valid = valid && !total
        else valid = valid && records==1 && matches==1
        exit !valid
    }
'
