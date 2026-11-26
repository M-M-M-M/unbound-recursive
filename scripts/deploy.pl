#!/usr/bin/env perl
# Operator-only, default single-service profile. No remote SSH or automatic updates.
use v5.26;
use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use File::Temp qw(tempfile);
use Digest::SHA qw(sha256_hex);
use FindBin qw($RealBin);

my $repo = 'ghcr.io/m-m-m-m/unbound-recursive';
my $source = 'M-M-M-M/unbound-recursive';
my $workflow = "$source/.github/workflows/build.yaml";
my $journal = '.deployment-state.json';
my $lock = '.deployment.lock';
my $digest_re = qr/sha256:[a-f0-9]{64}/;
umask 077;
sub fail { die "ERROR: @_\n" }
sub digest {
    my ($d) = @_;
    defined($d) && $d =~ /\A$digest_re\z/ or fail('invalid SHA-256 digest');
    return $d;
}
sub run {
    my (@cmd) = @_;
    system { $cmd[0] } @cmd;
    $? == 0 or fail("command failed ($?): $cmd[0] $cmd[1]");
}
sub capture {
    my (@cmd) = @_;
    open my $fh, '-|', @cmd or fail("cannot execute $cmd[0]: $!");
    local $/;
    my $out = <$fh> // '';
    close $fh or fail("command failed: $cmd[0] $cmd[1]");
    return $out;
}
sub trim { my ($s) = @_; $s =~ s/\s+\z//; return $s; }
sub cosign_identity {
    return ('--certificate-identity', "https://github.com/$workflow\@refs/heads/main",
        '--certificate-oidc-issuer', 'https://token.actions.githubusercontent.com',
        '--check-claims=true');
}
sub attest {
    my ($ref, $predicate) = @_;
    my @policy = $predicate eq 'https://slsa.dev/provenance/v1'
        ? ('--policy', "$RealBin/../security/github-provenance.cue") : ();
    my $out = capture('cosign', 'verify-attestation', cosign_identity(),
        '--type', $predicate, @policy, $ref);
    length($out) or fail("empty verified attestation: $predicate");
    print STDERR "Verified $predicate for $ref\n";
}
sub verify_signature {
    my ($ref, $d) = @_;
    my $report = decode_json(capture('cosign', 'verify', cosign_identity(), '--output', 'json', $ref));
    ref($report) eq 'ARRAY' or fail('invalid signature report');
    # Cosign v3 can also return provenance as a verified object. Require an
    # actual container signature, not merely an attestation over the subject.
    my $matched = grep {
        ref($_) eq 'HASH' && ref($_->{critical}) eq 'HASH' &&
        ($_->{critical}{type} // '') eq 'https://sigstore.dev/cosign/sign/v1' &&
        ref($_->{critical}{image}) eq 'HASH' &&
        ($_->{critical}{image}{'docker-manifest-digest'} // '') eq $d
    } @$report;
    $matched or fail('no verified Cosign v3 image signature for the requested digest');
    print STDERR "Verified image signature: $ref\n";
}
sub verify {
    my ($d) = @_;
    if ($d eq 'latest') {
        my $metadata = decode_json(capture('docker', 'buildx', 'imagetools', 'inspect', "$repo:latest", '--format', '{{json .Manifest}}'));
        $d = $metadata->{digest};
    }
    $d = digest($d);
    my $ref = "$repo\@$d";
    # All later operations use the immutable index, never the mutable tag.
    verify_signature($ref, $d);
    attest($ref, 'https://slsa.dev/provenance/v1');
    my $idx = decode_json(capture('docker', 'buildx', 'imagetools', 'inspect', $ref, '--raw'));
    ref($idx->{manifests}) eq 'ARRAY' && @{$idx->{manifests}} == 2 or fail('expected exactly two platform manifests');
    my %platform;
    for my $m (@{$idx->{manifests}}) {
        my $p = $m->{platform};
        ref($p) eq 'HASH' && ($p->{os} // '') eq 'linux' && ($p->{architecture} // '') =~ /\A(?:amd64|arm64)\z/ or fail('unexpected platform');
        exists $platform{$p->{architecture}} and fail('duplicate architecture');
        $platform{$p->{architecture}} = digest($m->{digest});
    }
    $platform{amd64} ne $platform{arm64} or fail('duplicate platform digest');
    for my $arch (sort keys %platform) {
        attest("$repo\@$platform{$arch}", 'https://cyclonedx.org/bom');
    }
    print STDERR "Verified manifest and both platform SBOMs: $ref\n";
    return $d;
}
sub read_file {
    my ($path) = @_;
    -f $path && !-l $path or fail("expected regular file: $path");
    my @s = stat($path);
    ($s[2] & 0022) == 0 && $s[4] == $< or fail("unsafe owner or permissions: $path");
    open my $f, '<:raw', $path or fail("open $path: $!");
    local $/; my $v = <$f> // ''; close $f or fail("close $path: $!");
    return $v;
}
sub atomic_write {
    my ($path, $data) = @_;
    my ($f, $tmp) = tempfile('.deployment-tmp-XXXXXXXX', DIR => '.', UNLINK => 0);
    chmod 0600, $tmp or fail("chmod $tmp: $!");
    print {$f} $data or fail("write $tmp: $!");
    close $f or fail("close $tmp: $!");
    rename $tmp, $path or fail("rename $tmp: $!");
}
sub env_digest {
    my ($text) = @_;
    # Intentionally support only the documented, simple default profile .env.
    my %seen;
    for my $line (split /\n/, $text) {
        next if $line =~ /\A\s*(?:#.*)?\z/;
        $line =~ /\A(UNBOUND_IMAGE|DNS_PORT)=(\S+)\z/ or fail('unsupported .env line');
        my ($key, $value) = ($1, $2);
        exists $seen{$key} and fail("duplicate $key");
        $seen{$key} = $value;
    }
    my $image = $seen{UNBOUND_IMAGE} // '';
    $image =~ /\A\Q$repo\E\@($digest_re)\z/ or fail('.env must pin a previously approved digest');
    my $d = $1;
    my $port = $seen{DNS_PORT} // '1053';
    $port =~ /\A[0-9]{1,5}\z/ && $port > 0 && $port <= 65535 or fail('invalid DNS_PORT');
    return $d;
}
sub compose { return ('docker', 'compose', '-f', 'compose.yaml'); }
sub with_image {
    my ($d, $cb) = @_;
    local $ENV{UNBOUND_IMAGE} = "$repo\@$d";
    local $ENV{COMPOSE_FILE} = 'compose.yaml';
    return $cb->();
}
sub image_id {
    my ($d) = @_;
    return digest(trim(capture('docker', 'image', 'inspect', "$repo\@$d", '--format', '{{.Id}}')));
}
sub assert_running {
    my ($d) = @_;
    my $id = trim(capture(compose(), 'ps', '-q', 'unbound'));
    $id =~ /\A[a-f0-9]{12,64}\z/ or fail('expected exactly one running resolver');
    trim(capture('docker', 'inspect', '--format', '{{.Image}}', $id)) eq image_id($d) or fail('running image differs from approved digest');
    trim(capture('docker', 'inspect', '--format', '{{.State.Health.Status}}', $id)) eq 'healthy' or fail('resolver not healthy');
}
sub start_and_test {
    my ($d) = @_;
    with_image($d, sub {
        run(compose(), 'up', '-d', '--wait', '--wait-timeout', '90', '--no-build', '--pull', 'never', 'unbound');
        assert_running($d);
        run('./tests/integration.sh');
    });
}
sub update {
    my ($action, $requested) = @_;
    -f 'compose.yaml' && -x 'tests/integration.sh' && -x 'scripts/state.sh' or fail('run from approved deployment directory');
    my @dir = stat('.');
    $dir[4] == $< && ($dir[2] & 0022) == 0 or fail('deployment directory must be owned by operator and not group/world writable');
    for my $k (keys %ENV) {
        $k =~ /\A(?:COMPOSE_.*|UNBOUND_IMAGE|DNS_PORT)\z/ and fail("unset $k before deployment");
    }
    my $backup = $ENV{BACKUP_DIR} // '';
    $backup =~ m{\A/} && -d $backup && !-l $backup or fail('set BACKUP_DIR to an existing protected absolute backup directory');
    my @backup_stat = stat($backup);
    $backup_stat[4] == $< && ($backup_stat[2] & 0022) == 0 or fail('backup directory must be operator-owned and not group/world writable');
    mkdir $lock, 0700 or fail('deployment lock exists or cannot be created; inspect pending operations');
    my $ok = eval {
        my $old_env = read_file('.env');
        my $old = env_digest($old_env);
        my $config_hash = sha256_hex(read_file('compose.yaml'));
        my $previous;
        if (-e $journal || -l $journal) {
            $previous = decode_json(read_file($journal));
            ref($previous) eq 'HASH' && ($previous->{status} // '') =~ /\A(?:deployed|rolled_back)\z/ or fail('pending/failed journal: investigate manually');
            ($previous->{current} // '') eq $old or fail('journal does not match .env');
            ($previous->{compose_sha256} // '') eq $config_hash or fail('Compose file changed; use reviewed manual migration procedure');
        }
        my $new = $action eq 'rollback' ? do {
            $previous && $previous->{status} eq 'deployed' && ($previous->{compose_sha256} // '') eq $config_hash or fail('no compatible completed deployment to roll back');
            digest($previous->{previous});
        } : digest($requested);
        $old ne $new or fail('requested digest is already deployed');
        with_image($old, sub { run(compose(), 'config', '--quiet'); assert_running($old); });
        # Verify both versions and pull them before stopping the current resolver.
        verify($new); verify($old);
        run('docker', 'pull', "$repo\@$new");
        run('docker', 'pull', "$repo\@$old");
        my $record = { status => 'pending', current => $old, previous => $old, candidate => $new,
            compose_sha256 => $config_hash, backup => '', action => $action };
        atomic_write($journal, encode_json($record) . "\n");
        my $applied = eval {
            with_image($old, sub {
                run(compose(), 'stop', 'unbound');
                $record->{backup} = trim(capture('./scripts/state.sh', 'backup'));
                print STDERR "$record->{backup}\n";
                atomic_write($journal, encode_json($record) . "\n");
            });
            start_and_test($new);
            my $new_env = $old_env;
            $new_env =~ s/^UNBOUND_IMAGE=.*$/UNBOUND_IMAGE=$repo\@$new/m or fail('cannot update .env');
            atomic_write('.env', $new_env);
            $record->{status} = 'deployed'; $record->{current} = $new;
            atomic_write($journal, encode_json($record) . "\n");
            1;
        };
        unless ($applied) {
            my $error = $@ || 'unknown failure';
            warn "Deployment failed: $error; trying previous verified image (same state schema).\n";
            my $recovered = eval {
                start_and_test($old);
                atomic_write('.env', $old_env);
                $record->{status} = 'rolled_back'; $record->{current} = $old;
                atomic_write($journal, encode_json($record) . "\n");
                1;
            };
            unless ($recovered) {
                my $rollback_error = $@;
                $record->{status} = 'rollback_failed';
                eval { atomic_write($journal, encode_json($record) . "\n"); };
                fail("rollback failed: $rollback_error; preserve backup and investigate manually");
            }
            fail('candidate rejected; previous image restored and tested');
        }
        print "Deployment accepted: $repo\@$new\n";
        1;
    };
    my $error = $@;
    rmdir $lock or fail('could not release deployment lock');
    die $error unless $ok;
}
my ($action, $arg) = @ARGV;
if (defined($action) && $action eq 'verify' && @ARGV == 2) {
    print "$repo\@" . verify($arg) . "\n";
} elsif (defined($action) && (($action eq 'update' && @ARGV == 2) || ($action eq 'rollback' && @ARGV == 1))) {
    update($action, $arg);
} else {
    fail('usage: deploy.pl verify latest|sha256:<digest> | update sha256:<approved digest> | rollback');
}
