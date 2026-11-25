#!/bin/sh
set -eu
answer=$(dig @127.0.0.1 -p 5353 resolver-health.test. A +short +time=2 +tries=1)
[ "$answer" = '192.0.2.53' ]
