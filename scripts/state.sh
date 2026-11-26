#!/bin/sh
# Operator-only state operations for the default Compose project.
set -eu
umask 077
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
compose() { docker compose -f compose.yaml "$@"; }
# Resolve the effective Compose mount, not shell guesses or a stale container.
# Output: mount type, then actual named volume name / absolute bind path.
configured_mount() {
    config=$(compose config --format json) || fail 'cannot resolve Compose configuration'
    printf '%s' "$config" | perl -MJSON::PP -e '
        local $/; my $c = decode_json(<STDIN>);
        my @m = grep { ($_->{target}//q{}) eq q{/state} } @{$c->{services}{unbound}{volumes}//[]};
        @m == 1 or die "expected exactly one configured /state mount\n";
        my ($type,$src) = @{$m[0]}{qw(type source)};
        if ($type eq q{volume}) { $src = $c->{volumes}{$src}{name} // die "missing volume name\n"; $src =~ /\A[a-zA-Z0-9_.-]+\z/ or die "invalid volume name\n"; }
        elsif ($type eq q{bind}) { $src =~ m{\A/(?:[a-zA-Z0-9_. -]+/)*[a-zA-Z0-9_. -]+\z} && $src !~ m{(?:^|/)\.{1,2}(?:/|$)} or die "invalid bind source\n"; }
        else { die "unsupported state mount type\n"; }
        print "$type\n$src\n";
    ' || fail 'invalid configured state mount'
}
# Check the actual mount even when the service is running; never switch storage implicitly.
inspect_mount() {
    case "$id" in ''|*[!a-fA-F0-9]*) fail 'expected exactly one container';; esac
    kind=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/state"}}{{.Type}}{{end}}{{end}}' "$id")
    case "$kind" in
        volume) source=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/state"}}{{.Name}}{{end}}{{end}}' "$id");
            case "$source" in ''|*[!a-zA-Z0-9_.-]*) fail 'invalid named volume';; esac
            docker volume inspect "$source" >/dev/null;;
        bind) source=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/state"}}{{.Source}}{{end}}{{end}}' "$id");;
        *) fail 'expected a volume or bind mount at /state';;
    esac
    configured=$(configured_mount) || fail 'cannot identify configured state'
    [ "$configured" = "$(printf '%s\n%s' "$kind" "$source")" ] || fail 'actual state mount differs from Compose configuration; review migration'
}
check_bind_directory() {
    configured=$(configured_mount) || fail 'cannot identify configured state'
    kind=$(printf '%s\n' "$configured" | sed -n '1p')
    if [ "$kind" = bind ]; then
        source=$(printf '%s\n' "$configured" | sed -n '2p')
        [ -d "$source" ] && [ ! -L "$source" ] || fail 'pre-create the dedicated bind directory on the local Docker host'
        # An operator must also review all parent permissions, ownership and SELinux.
        # Reject group/world writable state directories and symlink aliases.
        perl -MCwd=abs_path -e 'my $p=shift; my @s=stat($p); @s && ($s[2] & 0022)==0 && abs_path($p) eq $p or die "unsafe or noncanonical bind directory\n"' "$source" || fail 'unsafe bind directory'
    fi
}
confirm() {
    [ -t 0 ] || fail 'interactive terminal required; no unattended destructive operation'
    printf '%s Type %s to continue: ' "$1" "$2" >&2
    IFS= read -r answer || fail 'confirmation cancelled'
    [ "$answer" = "$2" ] || fail 'confirmation cancelled'
}
checksum() {
    if command -v sha512sum >/dev/null 2>&1; then
        result=$(sha512sum < "$1") || fail 'checksum failed'
    elif command -v shasum >/dev/null 2>&1; then
        result=$(shasum -a 512 < "$1") || fail 'checksum failed'
    else
        fail 'sha512sum or shasum is required'
    fi
    digest=${result%% *}
    [ "${#digest}" -eq 128 ] || fail 'invalid checksum length'
    case "$digest" in *[!0-9a-f]*) fail 'invalid checksum';; esac
    printf '%s\n' "$digest"
}
[ -f compose.yaml ] || fail 'run from the protected project directory'
[ "$#" = 1 ] || fail 'usage: state.sh check|backup|restore|purge'
case "$1" in check|backup|restore|purge) ;; *) fail 'unknown operation';; esac
mkdir .state-ops.lock 2>/dev/null || fail 'another state operation is active (or stale lock exists)'
stage=''
cleanup() {
    if [ -n "$stage" ]; then rm -f "$stage/root.key" "$stage/root.key.sha512"; rmdir "$stage"; fi
    rmdir .state-ops.lock
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
if [ "$1" = check ]; then
    check_bind_directory
    id=$(compose ps -a -q unbound)
    if [ -n "$id" ]; then inspect_mount; fi
    exit 0
fi
if [ "$1" = purge ]; then
    compose config --quiet
    compose ps -a
    configured=$(configured_mount) || fail 'cannot identify configured state'
    kind=$(printf '%s\n' "$configured" | sed -n '1p')
    id=$(compose ps -a -q unbound)
    if [ -n "$id" ]; then inspect_mount; fi
    if [ "$kind" = bind ]; then
        printf 'This removes containers and logs; bind-mounted host state and all named volumes are preserved.\n' >&2
        confirm 'Only proceed for the intended project after verifying backups.' PURGE
        compose down
    else
        printf 'This removes the containers, their logs and Compose-managed named volumes, including DNSSEC state.\n' >&2
        confirm 'Only proceed for the intended project after verifying backups.' PURGE
        compose down --volumes
    fi
    exit 0
fi
# Validate backup bytes before creating anything. Never start the resolver here.
if [ "$1" = restore ]; then
    src=${BACKUP_SET:-}
    [ -n "$src" ] || fail 'set BACKUP_SET to an approved backup directory'
    [ -f "$src/root.key" ] && [ ! -L "$src/root.key" ] && [ -s "$src/root.key" ] || fail 'missing or empty trust anchor'
    [ -f "$src/root.key.sha512" ] && [ ! -L "$src/root.key.sha512" ] || fail 'missing checksum'
    stage=$(mktemp -d "${TMPDIR:-/tmp}/unbound-restore.XXXXXXXX")
    cp "$src/root.key" "$stage/root.key"
    cp "$src/root.key.sha512" "$stage/root.key.sha512"
    [ "$(checksum "$stage/root.key")" = "$(cat "$stage/root.key.sha512")" ] || fail 'checksum mismatch'
fi
# Identify the actual service mount, never guess a project-specific volume name.
inspect_stopped() {
    id=$(compose ps -a -q unbound)
    case "$id" in ''|*[!a-fA-F0-9]*) fail 'exactly one existing unbound container is required';; esac
    status=$(docker inspect --format '{{.State.Status}}' "$id")
    case "$status" in exited|created) ;; *) fail 'stop the resolver first; never back up or restore live state';; esac
    inspect_mount
    users=$(docker ps -q --filter "volume=$source")
    [ -z "$users" ] || fail 'a running container still uses the state mount'
    image=$(docker inspect --format '{{.Image}}' "$id")
    case "$image" in sha256:*) ;; *) fail 'expected an immutable local image ID';; esac
}
id=$(compose ps -a -q unbound)
if [ -z "$id" ]; then
    [ "$1" = restore ] || fail 'existing stopped container required for backup; do not clean it first'
    compose config --quiet
    printf 'Restore %s to the selected Compose project; create a stopped container and its configured state mount if absent (pre-create bind directories).\n' "$src" >&2
    confirm 'Use only a trusted backup and a locally available approved image.' RESTORE
    check_bind_directory
    # No build, pull or start. Compose initializes a new named volume from the
    # image directory, including its numeric ownership. Reuse an existing one.
    compose create --no-build --pull never unbound
    inspect_stopped
else
    inspect_stopped
    if [ "$1" = restore ]; then
        printf 'Restore %s to state mount %s; use only a trusted backup from this resolver.\n' "$src" "$source" >&2
        confirm 'This replaces the current trust anchor; preserve its backup first.' RESTORE
        inspect_stopped
    fi
fi
# Reuse the exact local image and only the inspected state mount. No pull or network.
helper() {
    docker run --rm -i --pull never --network none --user 10001:10001 \
        --read-only --cap-drop ALL --security-opt no-new-privileges:true \
        --memory 128m --cpus 0.5 --pids-limit 32 --no-healthcheck \
        --log-driver none --mount "type=$kind,source=$source,target=/state$1" \
        --entrypoint /bin/sh "$image" -eu -c "$2"
}
if [ "$1" = backup ]; then
    dest=${BACKUP_DIR:-backups}
    mkdir -p "$dest"
    stage=$(mktemp -d "$dest/.dnssec.XXXXXXXX")
    helper ',readonly' '[ -f /state/root.key ] && [ ! -L /state/root.key ] && [ -s /state/root.key ] || exit 1; cat /state/root.key' > "$stage/root.key"
    [ -s "$stage/root.key" ] || fail 'empty trust anchor'
    checksum "$stage/root.key" > "$stage/root.key.sha512"
    suffix=${stage##*.}
    final="$dest/dnssec-$(date -u +%Y%m%dT%H%M%SZ)-$suffix"
    [ ! -e "$final" ] || fail 'backup destination already exists'
    mv "$stage" "$final"
    stage=''
    printf 'DNSSEC backup: %s (state: %s)\n' "$final" "$source"
else
    helper '' 'umask 027; [ ! -L /state/root.key ] && [ ! -d /state/root.key ] || exit 1; tmp=$(mktemp /state/root.key.restore.XXXXXXXX); trap '\''rm -f "$tmp"'\'' EXIT HUP INT TERM; cat > "$tmp"; [ -s "$tmp" ]; chmod 0640 "$tmp"; mv -f "$tmp" /state/root.key' < "$stage/root.key"
    # Verify the persisted bytes before permitting the operator to start it.
    expected=$(checksum "$stage/root.key")
    actual=$(helper ',readonly' 'sha512sum < /state/root.key')
    [ "${actual%% *}" = "$expected" ] || fail 'restored trust anchor checksum mismatch'
    printf 'Trust anchor restored and SHA-512 verified. Start the resolver explicitly and verify DNSSEC.\n'
fi
