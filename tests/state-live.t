use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use ProjectTest qw(read_bytes write_bytes run_command confirm_command);
use File::Temp qw(tempdir);
use File::Basename qw(basename);
use Cwd qw(getcwd abs_path);
use File::Path qw(make_path);

plan skip_all => 'set RUN_DOCKER_TESTS=1 on a test Docker host' unless ($ENV{RUN_DOCKER_TESTS} // '') eq '1';
my $root = "$FindBin::Bin/..";
my $script = "$root/scripts/state.sh";
my $image = $ENV{TEST_IMAGE} // 'unbound-recursive:dev';
my $dir = tempdir('unbound-recovery-test-XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
$dir = abs_path($dir);
my $project = lc basename($dir);
my $mode = $ENV{TEST_STATE_MODE} // 'volume';
$mode =~ /\A(?:bind|volume)\z/ or BAIL_OUT('invalid test state mode');
my $bind = $mode eq 'bind';
my $bind_dir = "$dir/dnssec-state";
my $provisioned = 0;
my $cwd = getcwd();
END { chdir $cwd if defined $cwd; }
chdir $dir or die "chdir $dir: $!";
my $compose = read_bytes("$root/compose.yaml");
# Allocate loopback ports and a subnet automatically, never use the operator project.
$compose =~ s/\$\{DNS_PORT:-1053\}//g;
$compose =~ s/    ipam:\n      config:\n        - subnet: 172\.30\.53\.0\/24\n// or die 'unexpected Compose network layout';
write_bytes('compose.yaml', $compose);
local %ENV = %ENV;
delete @ENV{grep { /^COMPOSE_/ || $_ eq 'DNSSEC_STATE_SOURCE' } keys %ENV};
@ENV{qw(COMPOSE_PROJECT_NAME UNBOUND_IMAGE BACKUP_DIR)} = ($project, $image, "$dir/backups");
sub checked {
    my ($r, $name) = @_;
    die "$name: $r->{code}\n$r->{stdout}\n$r->{stderr}" if $r->{code};
    return $r->{stdout};
}
sub dc { return checked(run_command(['docker', 'compose', '-f', 'compose.yaml', @_]), "compose @_"); }
sub state_op {
    my ($op, %env) = @_;
    local %ENV = (%ENV, %env);
    return run_command([$script, $op]);
}
sub confirm_op {
    my ($op, $word, %env) = @_;
    local %ENV = (%ENV, %env);
    return checked(confirm_command($script, $op, $word), "confirmed $op");
}
sub volume_exists { return run_command(['docker', 'volume', 'inspect', "${project}_state"])->{code} == 0; }
sub verify_backups {
    my ($expected) = @_;
    for my $set (glob "$dir/backups/dnssec-*") {
        is(read_bytes("$set/root.key"), $expected, 'exact saved anchor bytes');
    }
}
my $ready = 0;
my $success = eval {
    checked(run_command(['docker', 'image', 'inspect', $image]), 'local image required');
    if ($bind) {
        mkdir $bind_dir, 0750 or die "mkdir state: $!";
        # CI only: explicit administrative setup of the disposable test path.
        # Do not implicitly sudo on a developer host.
        if (($ENV{TEST_BIND_PROVISION} // '') eq '1') {
            my @sudo = $< == 0 ? () : ('sudo', '-n');
            checked(run_command([@sudo, 'chown', '10001:10001', $bind_dir]), 'test-only bind ownership');
            $provisioned = 1;
        }
        $ENV{DNSSEC_STATE_SOURCE} = $bind_dir;
        checked(run_command(['docker','run','--rm','--pull','never','--network','none','--user','10001:10001','--cap-drop','ALL','--security-opt','no-new-privileges:true','--read-only','--no-healthcheck','--mount',"type=bind,source=$bind_dir,target=/state",'--entrypoint','/bin/sh',$image,'-c','test -w /state']), 'bind ownership probe (see storage documentation)');
    }
    dc('config', '--quiet');
    checked(state_op('check'), 'state preflight');
    $ready = 1;
    dc('up', '-d', '--wait', '--pull', 'never');
    isnt(state_op('backup')->{code}, 0, 'running backup refused');
    dc('stop');
    checked(state_op('backup'), 'backup');
    my ($backup) = glob "$dir/backups/dnssec-*";
    die 'backup missing' unless defined $backup;
    my $expected = read_bytes("$backup/root.key");
    dc('down');
    ok($bind ? -d $bind_dir : volume_exists(), 'clean retains state storage');
    confirm_op('restore', 'RESTORE', BACKUP_SET => $backup);
    unlike(dc('ps', '-q', 'unbound'), qr/\S/, 'restore does not start service');
    checked(state_op('backup'), 'backup after clean restore');
    verify_backups($expected);
    confirm_op('purge', 'PURGE');
    if ($bind) {
        ok(-d $bind_dir, 'purge preserves bind directory');
        # Read and remove only the known anchor in this disposable lab to simulate loss.
        my @helper = ('docker','run','--rm','--pull','never','--network','none','--user','10001:10001','--cap-drop','ALL','--security-opt','no-new-privileges:true','--read-only','--no-healthcheck','--mount',"type=bind,source=$bind_dir,target=/state",'--entrypoint','/bin/sh',$image);
        is(checked(run_command([@helper,'-c','cat /state/root.key']), 'read preserved bind anchor'), $expected, 'purge preserves exact bind anchor');
        checked(run_command([@helper,'-c','rm /state/root.key']), 'simulate loss in disposable bind fixture');
    } else { ok(!volume_exists(), 'purge removes test volume'); }
    unlike(dc('ps', '-a', '-q', 'unbound'), qr/\S/, 'purge removes test container');
    make_path("$dir/bad");
    write_bytes("$dir/bad/root.key", $expected . 'corrupt');
    write_bytes("$dir/bad/root.key.sha512", read_bytes("$backup/root.key.sha512"));
    isnt(state_op('restore', BACKUP_SET => "$dir/bad")->{code}, 0, 'corrupt backup refused');
    unlike(dc('ps', '-a', '-q', 'unbound'), qr/\S/, 'corrupt restore creates no container');
    if ($bind) { ok(-d $bind_dir, 'corrupt restore leaves bind directory'); } else { ok(!volume_exists(), 'corrupt restore creates no volume'); }
    confirm_op('restore', 'RESTORE', BACKUP_SET => $backup);
    unlike(dc('ps', '-q', 'unbound'), qr/\S/, 'recovery does not start service');
    like(dc('ps', '-a', '-q', 'unbound'), qr/\S/, 'recovery creates stopped container');
    checked(state_op('backup'), 'backup after full recovery');
    verify_backups($expected);
    dc('up', '-d', '--wait', '--pull', 'never');
    my $result = run_command(["$root/tests/integration.sh"]);
    is($result->{code}, 0, 'live DNSSEC and integration after recovery') or diag($result->{stdout}, $result->{stderr});
    1;
};
my $error = $@;
if ($ready) {
    my $clean = eval { dc('down', '--volumes'); 1 };
    ok($clean, 'disposable project cleanup') or diag($@);
}
if ($provisioned) {
    my @sudo = $< == 0 ? () : ('sudo', '-n');
    my $gid = (split / /, $()[0];
    my $r = run_command([@sudo, 'chown', '-R', "$<:$gid", $bind_dir]);
    is($r->{code}, 0, 'return ownership of disposable bind fixture') or diag($r->{stderr});
}
ok($success, 'recovery sequence completed') or diag($error);
done_testing;
