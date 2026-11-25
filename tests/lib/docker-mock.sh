#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
 'compose -f') case "$4" in ps) [ "$5" != -a ] || [ "$6" != -q ] || if [ "${ABSENT:-0}" = 0 ] || [ -f "$CREATED" ]; then echo abc123; fi;; create) touch "$CREATED";; config|down) :;; esac;;
 'inspect --format') case "$3" in *State.Status*) echo "${STATUS:-exited}";; *Mounts*) echo test_state;; *Image*) echo sha256:abc;; esac;;
 'volume inspect') :;;
 'ps -q') :;;
 'run --rm') case "$*" in *target=/state,readonly*sha512sum*) if command -v sha512sum >/dev/null 2>&1; then sha512sum < "$ANCHOR"; else shasum -a 512 < "$ANCHOR"; fi;; *target=/state,readonly*) cat "$ANCHOR";; *) cat > "$ANCHOR";; esac;;
 *) exit 2;;
esac
