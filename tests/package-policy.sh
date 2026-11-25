#!/bin/sh
# Input: installed package inventory from dpkg-query (status abbreviation and binary package).
# Review this policy explicitly before intentionally adding an excluded library.
set -eu
LC_ALL=C awk '
    $1 == "ii" {
        pkg = $2; sub(/:.*/, "", pkg)
        if (pkg == "unbound") unbound = 1
        if (pkg == "ldnsutils") ldns = 1
        if (pkg ~ /^bind9($|-)/ || pkg ~ /^liblmdb/ || pkg ~ /^libxml2/) {
            print "FAIL: unexpected installed runtime dependency: " $2
            bad = 1
        }
    }
    END {
        if (!unbound || !ldns) { print "FAIL: expected Unbound and LDNS packages missing from inventory"; bad = 1 }
        exit (bad ? 1 : 0)
    }
'
