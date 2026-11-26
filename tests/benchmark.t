use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../benchmark";
use DNSBench qw(packet valid_reply query summarize);
use IO::Socket::INET;
use POSIX qw(_exit);
my $q=packet(42,'warm.bench.test.');
is(unpack('H*',substr($q,0,12)),'002a01000001000000000000','query header');
like($q,qr/\x04warm\x05bench\x04test\0\x00\x01\x00\x01\z/,'encoded fixture name');
for ('example.com.','x.bench.test','bad!.bench.test.') { ok(!eval {packet(1,$_);1},'reject non-fixture name'); }
sub reply { my ($q)=@_; return substr($q,0,2).pack('n5',0x8180,1,1,0,0).substr($q,12)."\xc0\x0c".pack('nnNnC4',1,1,300,4,192,0,2,80); }
my $r=reply($q);
ok(valid_reply($r,$q),'correct answer');
ok(!valid_reply(substr($r,0,-1),$q),'truncated answer');
my $bad=$r; substr($bad,1,1)="\x2b"; ok(!valid_reply($bad,$q),'transaction mismatch');
$bad=$r; substr($bad,3,1)="\x83"; ok(!valid_reply($bad,$q),'NXDOMAIN is not successful');
$bad=$r; substr($bad,-1,1)="\x51"; ok(!valid_reply($bad,$q),'incorrect A record');
$bad=$r; substr($bad,2,1)="\x83"; ok(!valid_reply($bad,$q),'TC is not successful');
my $s=summarize([['ok',1],['ok',2],['ok',3],['ok',4],['timeout_or_io',1000]],2,6);
is($s->{requested},6,'requested count'); is($s->{attempted},5,'attempted count'); is($s->{successes},4,'success count'); is($s->{successful_qps},2,'success rate');
is($s->{latency_ms}{median},2.5,'median'); is($s->{latency_ms}{p95},4,'p95 nearest rank'); is($s->{latency_ms}{mean},2.5,'mean excludes failures');
ok(!exists summarize([['invalid_reply',1]],1,1)->{latency_ms},'no success latency for failed phase');
for my $proto (qw(udp tcp)) {
    my $server=IO::Socket::INET->new(LocalAddr=>'127.0.0.1',LocalPort=>0,Proto=>$proto,($proto eq 'tcp'?(Listen=>1):()));
    ok($server,"$proto loopback fixture socket") or next;
    my $port=$server->sockport;
    my $pid=fork(); defined $pid or die $!;
    if (!$pid) {
        alarm 5;
        if ($proto eq 'udp') { my $peer=recv($server,my $req,512,0); send($server,reply($req),0,$peer) if defined $peer; }
        else { my $c=$server->accept(); my ($len,$req); if ($c && read($c,$len,2)==2 && read($c,$req,unpack('n',$len))==unpack('n',$len)) {my $response=reply($req); print {$c} pack('n',length($response)).$response; close $c;} }
        _exit(0);
    }
    close $server;
    my ($result,$ms)=query($port,$proto,'warm.bench.test.',2);
    is($result,'ok',"$proto real socket response"); cmp_ok($ms,'>=',0,"$proto latency");
    waitpid($pid,0);
}
done_testing;
