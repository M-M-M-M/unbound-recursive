use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../benchmark";
use Profiles qw(profile_cases resolver_config);
use ClientWorkload qw(run_phase);
use DNSBench qw(query summarize);
use IO::Socket::INET;
use POSIX qw(_exit);
my $base="    ip-ratelimit: 100\n    ratelimit: 200\n";
like(resolver_config($base,'baseline'),qr/ip-ratelimit: 0\n    ratelimit: 0/,'baseline disables both limits');
is(resolver_config($base,'production'),$base,'production-like limits unchanged');
is(resolver_config($base,'ratelimit'),$base,'rate-limit profile preserves limits');
like(resolver_config($base,'stress'),qr/ip-ratelimit: 0/,'stress lab disables limits');
ok(!eval {resolver_config('', 'baseline');1},'missing limits fail closed');
ok(!eval {profile_cases('invalid');1},'unknown profile refused');
my @quick=profile_cases('quick'); is(scalar @quick,4,'four quick cases');
my @rate=profile_cases('ratelimit'); is_deeply([map {$_->[5]} @rate],[50,200,50,200],'below/above threshold for both protocols');
my @stress=profile_cases('stress'); ok(grep($_->[6]==60,@stress),'sustained 60-second phase');
ok(grep($_->[7] eq 'persistent',profile_cases('baseline')),'persistent TCP scenario');
my $sum=summarize([['ok',1,1],['connect_error',2,0],['timeout',3,1]],2,5);
is($sum->{sent},2,'complete wire sends'); is($sum->{not_attempted},2,'unscheduled requests'); is($sum->{failed},2,'failed attempts');
# Exercise paced persistent TCP on a single accepted connection.
my $server=IO::Socket::INET->new(LocalAddr=>'127.0.0.1',LocalPort=>0,Proto=>'tcp',Listen=>1) or BAIL_OUT($!);
my $port=$server->sockport;
my $pid=fork(); defined $pid or die $!;
if (!$pid) {
    alarm 8;
    my $c=$server->accept() or _exit(1);
    for (1..3) {
        read($c,my $len,2)==2 or _exit(2);
        my $n=unpack('n',$len); read($c,my $q,$n)==$n or _exit(3);
        my $r=substr($q,0,2).pack('n5',0x8180,1,1,0,0).substr($q,12)."\xc0\x0c".pack('nnNnC4',1,1,300,4,192,0,2,80);
        print {$c} pack('n',length($r)).$r or _exit(4);
    }
    close $c; _exit(0);
}
close $server;
my $r=run_phase('127.0.0.1',$port,'tcp-warm','tcp','warm',3,1,3,1,'persistent');
is($r->{successes},3,'three responses over persistent socket');
cmp_ok($r->{seconds},'>=',1,'full emission window measured');
is($r->{sent},3,'three fully transmitted queries');
waitpid($pid,0); is($?,0,'fixture accepted one TCP connection');
ok(!eval {run_phase('127.0.0.1',5353,'tcp-warm','tcp','warm',4,1,3,1,'persistent');1},'inconsistent schedule refused');
done_testing;
