use v5.26;
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../benchmark";
use Profiles qw(soak_verdict profile_cases resolver_config);
my $p={case=>'udp-soak-10000',requested=>10000,sent=>9900,attempted=>9900,successes=>9900,latency_ms=>{p99=>4.99},resource_coverage=>{complete=>1},runtime_healthy=>1,cache_delta=>{'total.num.queries_ip_ratelimited'=>0}};
is(soak_verdict($p)->{status},'PASS','boundary passes');
my $low={%$p,sent=>9761,attempted=>9761,successes=>9761};
is(soak_verdict($low)->{status},'INCONCLUSIVE','clean insufficient load');
is(soak_verdict({%$low,successes=>9700})->{status},'FAIL','DNS failure takes precedence');
is(soak_verdict({%$low,attempted=>9762})->{status},'FAIL','send failure takes precedence');
is(soak_verdict({%$low,resource_coverage=>{complete=>0}})->{status},'FAIL','coverage failure takes precedence');
is(soak_verdict({%$low,runtime_healthy=>0})->{status},'FAIL','runtime failure takes precedence');
is(soak_verdict({%$low,latency_ms=>{p99=>5}})->{status},'FAIL','latency failure takes precedence');
is(soak_verdict({%$low,cache_delta=>{'total.num.queries_ip_ratelimited'=>1}})->{status},'FAIL','unexpected limiter takes precedence');
my @full=profile_cases('soak');
for my $i (0,1) {
    my $name=('soak-1000','soak-10000')[$i];
    is_deeply([profile_cases($name)],[$full[$i]],"$name identical phase");
    like(resolver_config("ip-ratelimit: 100\nratelimit: 200\n",$name),qr/ip-ratelimit: 0\nratelimit: 0/,"$name isolated config");
}
done_testing;
