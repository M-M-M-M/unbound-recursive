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
my $source = abs_path("$FindBin::Bin/../scripts/deploy.pl");
my $root = tempdir(CLEANUP => 1);
my $cwd = getcwd();
chdir $root or die $!;
make_path(qw(bin scripts tests backups));
my $repo = 'ghcr.io/m-m-m-m/unbound-recursive';
my $old = 'sha256:' . 'a' x 64;
my $new = 'sha256:' . 'b' x 64;
my $env = "UNBOUND_IMAGE=$repo\@$old\nDNS_PORT=1053\n";
write_bytes('.env', $env);
write_bytes('compose.yaml', "services: {}\n");
write_bytes('current', $old);
write_bytes('scripts/state.sh', "#!/bin/sh\necho DNSSEC backup: mocked\n");
write_bytes('tests/integration.sh', "#!/bin/sh\n[ \"\${FAIL_TEST:-}\" != \"\$(cat current)\" ]\n");
chmod 0755, 'scripts/state.sh', 'tests/integration.sh';
write_bytes('bin/mock', <<'MOCK');
#!/usr/bin/env perl
use strict; use warnings; use JSON::PP qw(encode_json);
my ($tool) = $0 =~ m{([^/]+)$};
my $args = join(' ', @ARGV);
open my $log, '>>', 'commands' or die $!; print {$log} "$tool $args\n"; close $log;
my $old = 'sha256:' . 'a' x 64; my $new = 'sha256:' . 'b' x 64;
if ($tool eq 'cosign') {
    exit 1 if ($ENV{FAIL_VERIFY}//'') && $args =~ /\Q$new\E/;
    if ($ARGV[0] eq 'verify-attestation') {
        exit 1 if ($ENV{FAIL_ATTEST}//'') && $args =~ /cyclonedx/;
        exit 1 if ($ENV{FAIL_PROVENANCE}//'') && $args =~ /slsa.dev/;
        print "verified envelope\n" unless $ENV{EMPTY_ATTEST};
        exit 0;
    }
    my ($d) = $args =~ /\@(sha256:[a-f0-9]{64})/;
    my $type = $ENV{ONLY_PROVENANCE} ? 'https://slsa.dev/provenance/v1' : 'https://sigstore.dev/cosign/sign/v1';
    $d = $old if $ENV{WRONG_DIGEST};
    print encode_json([{critical=>{type=>$type,image=>{'docker-manifest-digest'=>$d}}}]);
    exit 0;
}
if ($args =~ /imagetools inspect .*:latest/) { print encode_json({digest=>$new}); }
elsif ($args =~ /imagetools inspect .*--raw/) { print encode_json({manifests=>[map {{digest=>'sha256:'.($_ eq 'amd64'?'c':'d') x 64,platform=>{os=>'linux',architecture=>$_}}} qw(amd64 arm64)]}); }
elsif ($args =~ /compose -f compose.yaml ps -q/) { print "abcdef123456\n"; }
elsif ($args =~ /inspect --format .*State.Health.Status/) { print "healthy\n"; }
elsif ($args =~ /inspect --format .*\.Image/) { open my $f,'<','current' or die $!; print <$f>; }
elsif ($args =~ /image inspect .*\@(sha256:[a-f0-9]{64})/) { print "$1\n"; }
elsif ($args =~ /compose -f compose.yaml up /) { my ($d) = $ENV{UNBOUND_IMAGE} =~ /\@(sha256:[a-f0-9]{64})/; open my $f,'>','current' or die $!; print {$f} $d; }
exit 0;
MOCK
chmod 0755, 'bin/mock';
for my $tool (qw(docker cosign)) { symlink 'mock', "bin/$tool" or die $!; }
local $ENV{PATH} = "$root/bin:$ENV{PATH}";
local $ENV{BACKUP_DIR} = "$root/backups";
sub invoke { return run_command([$^X, $source, @_], '', 30); }
my $r = invoke('verify', 'latest');
is($r->{code}, 0, 'verify latest succeeds');
is($r->{stdout}, "$repo\@$new\n", 'immutable reference returned');
my $commands = read_bytes('commands');
like($commands, qr/cosign verify-attestation .*slsa\.dev.*--policy .*github-provenance\.cue/, 'provenance and hosted-runner policy checked');
for my $arch_digest ('c' x 64, 'd' x 64) {
    like($commands, qr/cosign verify-attestation .*cyclonedx.*\@sha256:$arch_digest/, 'platform SBOM bound to exact digest');
}
like($commands, qr/--certificate-identity https:\/\/github\.com\/M-M-M-M\/unbound-recursive\/\.github\/workflows\/build\.yaml\@refs\/heads\/main/, 'exact certificate identity');
unlike($commands, qr/^gh /m, 'no GitHub CLI');
{ local $ENV{ONLY_PROVENANCE}=1; isnt(invoke('verify',$new)->{code},0,'provenance alone is not an image signature'); }
{ local $ENV{WRONG_DIGEST}=1; isnt(invoke('verify',$new)->{code},0,'signature for wrong digest rejected'); }
{ local $ENV{EMPTY_ATTEST}=1; isnt(invoke('verify',$new)->{code},0,'empty attestation output rejected'); }
isnt(invoke('update', 'latest')->{code}, 0, 'mutable tag refused for update');
write_bytes('commands','');
{ local $ENV{FAIL_VERIFY}=1; isnt(invoke('update',$new)->{code},0,'bad signature refused'); }
unlike(read_bytes('commands'), qr/compose .* stop /, 'verification failure causes no stop');
{ local $ENV{FAIL_ATTEST}=1; isnt(invoke('update',$new)->{code},0,'bad SBOM refused'); }
unlike(read_bytes('commands'), qr/compose .* stop /, 'attestation failure causes no stop');
{ local $ENV{FAIL_PROVENANCE}=1; isnt(invoke('update',$new)->{code},0,'bad provenance refused'); }
unlike(read_bytes('commands'), qr/compose .* stop /, 'provenance failure causes no stop');
{ local $ENV{FAIL_TEST}=$new; isnt(invoke('update',$new)->{code},0,'failed candidate returns failure'); }
is(read_bytes('current'),$old,'automatic rollback restored old running digest');
is(read_bytes('.env'),$env,'old .env retained');
is(decode_json(read_bytes('.deployment-state.json'))->{status},'rolled_back','rollback recorded');
is(invoke('update',$new)->{code},0,'successful update');
like(read_bytes('.env'),qr/\Q$new\E/,'new digest persisted');
is(decode_json(read_bytes('.deployment-state.json'))->{previous},$old,'previous digest recorded');
is(invoke('rollback')->{code},0,'explicit rollback');
is(read_bytes('current'),$old,'old digest running');
is(read_bytes('.env'),$env,'old digest persisted');
ok(!-e '.deployment.lock','lock released');
mkdir '.deployment.lock' or die $!;
isnt(invoke('update',$new)->{code},0,'concurrent/stale lock refuses update');
rmdir '.deployment.lock';
my $j=decode_json(read_bytes('.deployment-state.json')); $j->{status}='pending';
write_bytes('.deployment-state.json',JSON::PP::encode_json($j));
isnt(invoke('update',$new)->{code},0,'pending journal refuses update');
chdir $cwd or die $!;
done_testing;
