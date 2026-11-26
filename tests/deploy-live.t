use v5.26;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use Cwd qw(getcwd abs_path);
use FindBin;
use lib "$FindBin::Bin/lib";
use ProjectTest qw(run_command read_bytes write_bytes);
use JSON::PP qw(decode_json);
use Digest::SHA qw(sha512_hex);

plan skip_all => 'explicit RUN_DEPLOY_LIVE=1 and two signed digests required (disposable Docker host only)'
    unless ($ENV{RUN_DEPLOY_LIVE} // '') eq '1';
my ($old, $new) = @ENV{qw(PREVIOUS_DIGEST CANDIDATE_DIGEST)};
for ($old, $new) { defined && /\Asha256:[a-f0-9]{64}\z/ or BAIL_OUT('invalid digest input'); }
$old ne $new or BAIL_OUT('two distinct digests required');
for (keys %ENV) { /\A(?:COMPOSE_.*|UNBOUND_IMAGE|DNS_PORT|DNSSEC_STATE_SOURCE)\z/ and BAIL_OUT("unset $_ before lab test"); }
my $source = abs_path("$FindBin::Bin/..");
my $cwd = getcwd();
# Random Compose project name from directory basename. Fixed subnet/port in the
# unchanged production Compose example must be unused on this disposable host.
my $dir = tempdir('unbound-live-XXXXXXXX', TMPDIR => 1, CLEANUP => 0);
# Compose requires lowercase project names. File::Temp may produce uppercase.
my $lower;
# Do not lowercase parent path (macOS temp paths can be case-sensitive).
my ($parent, $base) = $dir =~ m{\A(.*/)([^/]+)\z};
$lower = $parent . lc $base;
if ($lower ne $dir) {
    !-e $lower && rename($dir, $lower) or BAIL_OUT('cannot allocate lowercase lab directory');
    $dir = $lower;
}
chdir $dir or BAIL_OUT("chdir: $!");
make_path(qw(scripts tests security monitoring backups), {mode => 0700});
for my $file (qw(compose.yaml scripts/deploy.pl scripts/state.sh tests/integration.sh tests/package-policy.sh security/github-provenance.cue monitoring/export-stats.pl)) {
    copy("$source/$file", $file) or BAIL_OUT("copy $file: $!");
    chmod((stat("$source/$file"))[2] & 0777, $file) or BAIL_OUT("chmod $file: $!");
}
my $repo = 'ghcr.io/m-m-m-m/unbound-recursive';
my $old_env = "UNBOUND_IMAGE=$repo\@$old\nDNS_PORT=1053\n";
write_bytes('.env', $old_env); chmod 0600, '.env' or BAIL_OUT("chmod: $!");
local $ENV{BACKUP_DIR} = "$dir/backups";
my @compose = qw(docker compose -f compose.yaml);
my $created = 0;
sub cmd {
    my ($argv, $description, $expected_failure) = @_;
    my $r = run_command($argv, '', 420);
    my $ok = $expected_failure ? $r->{code} != 0 : $r->{code} == 0;
    ok($ok, $description) or diag($r->{stdout}, $r->{stderr});
    return ($ok, $r);
}
sub require_cmd {
    my ($argv, $description) = @_;
    my ($ok, $r) = cmd($argv, $description, 0);
    die "failed: $description\n" unless $ok;
    return $r->{stdout};
}
my $success = eval {
    require_cmd([$^X, 'scripts/deploy.pl', 'verify', $old], 'previous verified without GitHub CLI');
    require_cmd([$^X, 'scripts/deploy.pl', 'verify', $new], 'candidate verified without GitHub CLI');
    require_cmd([@compose, 'config', '--quiet'], 'unchanged lab profile validated');
    require_cmd([@compose, 'pull'], 'pull previous digest');
    $created = 1;
    require_cmd([@compose, 'up', '-d', '--wait', '--no-build', '--pull', 'never'], 'start signed previous image');
    require_cmd(['./tests/integration.sh'], 'previous image integration');
    # A deliberate acceptance-test failure is confined to this disposable copy.
    my $original = read_bytes('tests/integration.sh');
    write_bytes('tests/integration.sh', "#!/bin/sh\ncase \"\${UNBOUND_IMAGE:-}\" in *$new) echo 'intentional lab failure' >&2; exit 42;; esac\n" . $original);
    my ($failed, $failure) = cmd([$^X, 'scripts/deploy.pl', 'update', $new], 'deliberate failed update returns nonzero', 1);
    die "failure injection did not fail\n" unless $failed;
    write_bytes('tests/integration.sh', $original);
    like($failure->{stderr}, qr/previous image restored and tested/, 'automatic rollback completed');
    is(read_bytes('.env'), $old_env, 'previous digest remains pinned');
    is(decode_json(read_bytes('.deployment-state.json'))->{status}, 'rolled_back', 'automatic rollback recorded');
    require_cmd(['./tests/integration.sh'], 'resolver still works after automatic rollback');
    require_cmd([$^X, 'scripts/deploy.pl', 'update', $new], 'signed update accepted');
    like(read_bytes('.env'), qr/\Q$new\E/, 'candidate digest pinned');
    my $j = decode_json(read_bytes('.deployment-state.json'));
    is($j->{previous}, $old, 'previous digest in journal');
    is($j->{status}, 'deployed', 'successful update recorded');
    my @sets = glob('backups/dnssec-*');
    ok(@sets >= 2, 'backup sets retained');
    for my $set (@sets) {
        my $sum = read_bytes("$set/root.key.sha512"); chomp $sum;
        is(sha512_hex(read_bytes("$set/root.key")), $sum, 'backup SHA-512 verified');
    }
    my $stats = require_cmd([@compose, 'exec', '-T', 'unbound', 'unbound-control', '-c', '/etc/unbound/recursive.conf', 'stats_noreset'], 'real stats collected');
    my $r = run_command([$^X, 'monitoring/export-stats.pl', "$dir/unbound.lp"], $stats, 10);
    is($r->{code}, 0, 'real stats converted to line protocol') or diag($r->{stderr});
    like(read_bytes('unbound.lp'), qr/^unbound_snapshot,service=unbound-recursive .*total_num_queries=/, 'query count in snapshot');
    is((stat('unbound.lp'))[2] & 0777, 0640, 'snapshot mode');
    require_cmd([$^X, 'scripts/deploy.pl', 'rollback'], 'explicit signed rollback accepted');
    is(read_bytes('.env'), $old_env, 'old digest pinned again');
    require_cmd(['./tests/integration.sh'], 'final resolver integration');
    1;
};
my $error = $@;
if ($created) { eval { cmd([@compose, 'down', '--volumes'], 'dispose only random lab project', 0); }; diag($@) if $@; }
chdir $cwd or die $!;
# Keep the lab evidence and backup files locally on failure or success. On CI
# the entire runner is disposable; never recursively delete unknown paths.
diag("Lab evidence: $dir");
ok($success, 'signed deployment qualification completed') or diag($error);
done_testing;
