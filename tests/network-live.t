use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use ProjectTest qw(run_command);
use lib "$FindBin::Bin/../lib";
use LocalDocker qw(require_local_docker);
use File::Temp qw(tempdir);
use Time::HiRes qw(time sleep);
plan skip_all => 'opt in with make test-network' unless ($ENV{RUN_NETWORK_LIVE}//'') eq '1';
require_local_docker();
my $dir=tempdir('unbound-acl-XXXXXXXX', TMPDIR=>1,CLEANUP=>1);
my ($name)=$dir=~m{([^/]+)\z}; $name=lc $name;
my $resolver="$name-resolver";
my $volume="$name-state";
my $image='unbound-recursive:dev';
my $net_created=0; my $volume_created=0; my $container_created=0;
sub docker { run_command(['docker',@_],'',90); }
sub checked {
    my ($label,@args)=@_;
    my $r=docker(@args);
    ok($r->{code}==0,$label) or die "$label: $r->{stderr}";
    return $r->{stdout};
}
my $success=eval {
    local $SIG{INT}=sub {die "interrupted\n"}; local $SIG{TERM}=sub {die "terminated\n"};
    checked('isolated unauthorized client network','network','create','--internal','--driver','bridge',$name); $net_created=1;
    my $network=checked('inspect isolated network','network','inspect','--format','{{range .IPAM.Config}}{{println .Subnet}}{{end}}',$name);
    # Refuse to run the experiment on an overlapping allowed network. Docker's
    # default pools may be customized; check overlap numerically, not by prefix text.
    my ($a,$b,$c,$d,$bits)=$network=~/\A(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)\s*\z/;
    defined($bits) && $bits>=1 && $bits<=32 or die "unexpected network subnet: $network";
    my $ip=unpack('N',pack('C4',$a,$b,$c,$d)); my $allowed=unpack('N',pack('C4',172,30,53,0));
    my $common=$bits<24?$bits:24; my $shift=32-$common;
    ok(($ip>>$shift)!=($allowed>>$shift),'unauthorized network does not overlap production ACL') or die 'overlapping network';
    checked('private temporary state volume','volume','create',$volume); $volume_created=1;
    my @hardening=('--user','10001:10001','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true','--memory','512m','--cpus','1','--pids-limit','64','--network',$name);
    $container_created=1;
    checked('start unmodified production configuration without published ports','run','-d','--name',$resolver,@hardening,'--tmpfs','/run/resolver:uid=10001,gid=10001,mode=0750,size=1m','--tmpfs','/tmp:uid=10001,gid=10001,mode=0700,size=16m','--mount',"type=volume,src=$volume,dst=/state",$image);
    my $deadline=time()+60; my $healthy=0;
    while (time()<$deadline) {my $r=docker('exec',$resolver,'/usr/local/bin/healthcheck.sh'); if ($r->{code}==0) {$healthy=1;last;} sleep 1;}
    ok($healthy,'loopback UDP permitted') or die 'resolver not ready';
    checked('loopback TCP permitted','exec',$resolver,'/usr/local/bin/healthcheck.sh','--tcp');
    my $status=checked('read actual PID 1 security status','exec',$resolver,'cat','/proc/1/status');
    like($status,qr/^CapEff:\s+0+\s*$/m,'effective capabilities empty');
    like($status,qr/^NoNewPrivs:\s+1\s*$/m,'no-new-privileges effective');
    like($status,qr/^Seccomp:\s+2\s*$/m,'seccomp filter effective');
    like($status,qr/^Uid:\s+10001\s+10001\s+10001\s+10001\s*$/m,'all process UIDs non-root');
    my $ports=checked('inspect actual published ports','port',$resolver); is($ports,'','no public or host port published');
    my $address=checked('inspect isolated IPv4 address','inspect','--format','{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}',$resolver); chomp $address;
    $address=~/\A(?:\d{1,3}\.){3}\d{1,3}\z/ or die 'invalid isolated address';
    for my $proto (qw(-u -t)) {
        my $reply=checked("unauthorized peer query $proto",'run','--rm',@hardening,'--entrypoint','/usr/bin/timeout','--no-healthcheck',$image,'5s','drill',$proto,'-p','5353','resolver-health.test.',"\@$address",'A');
        like($reply,qr/^;; ->>HEADER<<-.*rcode: REFUSED,/m,"ACL refuses unauthorized peer $proto");
        unlike($reply,qr/^resolver-health\.test\.\s+\d+\s+IN\s+A\s+192\.0\.2\.53/m,'no fixture answer leaked');
    }
    1;
};
my $error=$@;
if ($container_created) {my $r=docker('rm','-f',$resolver); ok(!$r->{code},'remove isolated resolver') or diag($r->{stderr});}
if ($volume_created) {my $r=docker('volume','rm',$volume); ok(!$r->{code},'remove isolated state') or diag($r->{stderr});}
if ($net_created) {my $r=docker('network','rm',$name); ok(!$r->{code},'remove isolated network') or diag($r->{stderr});}
ok($success,'network audit completed') or diag($error);
done_testing;
