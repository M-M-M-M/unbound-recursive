use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../benchmark";
use LabNetwork qw(validate_lab_network);
use ClientWorkload qw(run_phase);
use DNSBench qw(query);
use Storable qw(dclone);
use IO::Socket::INET;
use POSIX qw(_exit);
my ($nid,$rid,$cid,$fid)=map {$_ x 64} qw(a b c d);
my $network={Id=>$nid,Internal=>1,Driver=>'bridge',EnableIPv6=>0,Containers=>{
    $rid=>{IPv4Address=>'172.30.0.2/24'},$cid=>{IPv4Address=>'172.30.0.3/24'}}};
sub endpoint {
    my ($id,$ip)=@_;
    return {Id=>$id,HostConfig=>{PortBindings=>{},PublishAllPorts=>0},
        NetworkSettings=>{Ports=>{'5353/udp'=>undef},Networks=>{lab=>{NetworkID=>$nid,IPAddress=>$ip}}}};
}
my $resolver=endpoint($rid,'172.30.0.2'); my $client=endpoint($cid,'172.30.0.3');
my $fixture={Id=>$fid,HostConfig=>{NetworkMode=>"container:$rid"},NetworkSettings=>{}};
my @valid=($network,$resolver,$client,$fixture);
is(validate_lab_network(@valid),'172.30.0.2','only internal resolver address selected');
sub reject {
    my ($label,$change)=@_;
    my $a=dclone(\@valid); $change->($a);
    ok(!eval {validate_lab_network(@$a);1},$label);
}
reject('external bridge refused',sub {$_[0][0]{Internal}=0});
reject('IPv6 network refused',sub {$_[0][0]{EnableIPv6}=1});
reject('non-bridge refused',sub {$_[0][0]{Driver}='host'});
reject('unknown peer refused',sub {$_[0][0]{Containers}{'e'x64}={}});
reject('missing client membership refused',sub {delete $_[0][0]{Containers}{$cid}});
reject('host binding refused even if inactive',sub {$_[0][1]{HostConfig}{PortBindings}{'5353/udp'}=[{HostIp=>'127.0.0.1'}]});
reject('publish-all refused',sub {$_[0][2]{HostConfig}{PublishAllPorts}=1});
reject('active binding refused',sub {$_[0][1]{NetworkSettings}{Ports}{'5353/udp'}=[{HostIp=>'127.0.0.1'}]});
reject('second network refused',sub {$_[0][2]{NetworkSettings}{Networks}{extra}={}});
reject('network mismatch refused',sub {$_[0][2]{NetworkSettings}{Networks}{lab}{NetworkID}='e'x64});
reject('fixture namespace mismatch refused',sub {$_[0][3]{HostConfig}{NetworkMode}='host'});
reject('resolver address mismatch refused',sub {$_[0][1]{NetworkSettings}{Networks}{lab}{IPAddress}='172.30.0.4'});
reject('loopback resolver endpoint refused',sub {$_[0][1]{NetworkSettings}{Networks}{lab}{IPAddress}='127.0.0.1'});
reject('missing resolver address refused',sub {delete $_[0][1]{NetworkSettings}{Networks}{lab}{IPAddress}});
ok(!eval {query(5353,'udp','warm.bench.test.',1,'localhost');1},'non-numeric query endpoint refused');
ok(!eval {run_phase('127.0.0.1',5353,'udp-cold','udp','cold',4001,1);1},'unbounded count refused');
ok(!eval {run_phase('127.0.0.1',5353,'udp-cold','udp','cold',10,17);1},'unbounded workers refused');
# Exercise the moved client workload with real sockets and two workers; use an
# ephemeral loopback port (no Docker and no arbitrary network destination).
my $server=IO::Socket::INET->new(LocalAddr=>'127.0.0.1',LocalPort=>0,Proto=>'udp');
ok($server,'local fixture socket') or BAIL_OUT('socket unavailable');
my $port=$server->sockport;
my $pid=fork(); defined $pid or die $!;
if (!$pid) {
    alarm 10;
    for (1..4) {
        my $peer=recv($server,my $q,512,0); _exit(1) unless defined $peer;
        my $r=substr($q,0,2).pack('n5',0x8180,1,1,0,0).substr($q,12)."\xc0\x0c".pack('nnNnC4',1,1,300,4,192,0,2,80);
        send($server,$r,0,$peer) or _exit(1);
    }
    _exit(0);
}
close $server;
my $result=run_phase('127.0.0.1',$port,'udp-cold','udp','cold',4,2);
is($result->{requested},4,'client phase requested count');
is($result->{attempted},4,'client phase attempted count');
is($result->{successes},4,'client phase successful responses');
cmp_ok($result->{successful_qps},'>',0,'client phase measured throughput');
waitpid($pid,0); is($?,0,'fixture handled four queries');
done_testing;
