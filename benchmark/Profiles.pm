package Profiles;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK=qw(profile_cases resolver_config validate_soak soak_verdict is_soak);

# Each case: id, protocol, cache, requested, workers, target qps, seconds, transport mode.
sub profile_cases {
    my ($profile)=@_;
    my @cases;
    my $add=sub {
        my ($id,$proto,$cache,$rate,$duration,$workers,$mode)=@_;
        push @cases,[$id,$proto,$cache,$rate*$duration,$workers,$rate,$duration,$mode];
    };
    if ($profile eq 'quick') {
        for my $p (qw(udp tcp)) { for my $c (qw(warm cold)) {$add->("$p-$c",$p,$c,12,1,1,$p eq 'udp'?'async':'new');} }
    } elsif ($profile eq 'baseline' || $profile eq 'production') {
        my $rate=$profile eq 'baseline'?1000:50;
        for my $p (qw(udp tcp)) { for my $c (qw(warm cold)) {$add->("$p-$c",$p,$c,$rate,10,4,'new');} }
        $add->('tcp-persistent','tcp','warm',$rate,10,4,'persistent');
    } elsif ($profile eq 'ratelimit') {
        for my $p (qw(udp tcp)) { for my $rate (50,200) {$add->("$p-rate-$rate",$p,'warm',$rate,10,16,$p eq 'udp'?'async':'new');} }
    } elsif ($profile eq 'stress') {
        for my $rate (500,1000,2500,5000,10000) {$add->("udp-stress-$rate",'udp','cold',$rate,10,16,'new');}
        $add->('udp-stress-30','udp','cold',1000,30,16,'new');
        $add->('udp-stress-60','udp','cold',1000,60,16,'new');
    } elsif (is_soak($profile)) {
        if ($profile =~ /\Asoak(?:-1000|-10000)?\z/) {
            $add->('udp-soak-1000','udp','cold',1000,3600,16,'async') unless $profile eq 'soak-10000';
            $add->('udp-soak-10000','udp','cold',10000,600,16,'async') unless $profile eq 'soak-1000';
        } elsif ($profile eq 'soak-check') {
            $add->('udp-soak-check','udp','cold',100,120,4,'async');
        } else {
            $add->('udp-soak-day','udp','cold',100,86400,4,'async');
        }
    } else {die "unknown benchmark profile\n";}
    return @cases;
}
sub resolver_config {
    my ($text,$profile)=@_;
    profile_cases($profile);
    for my $pair (['ip-ratelimit',100],['ratelimit',200]) {
        my ($key,$value)=@$pair;
        my $replacement=($profile =~ /\A(?:baseline|stress|soak|soak-day|soak-check|soak-1000|soak-10000)\z/)?0:$value;
        my $n=($text =~ s/^([ \t]*\Q$key\E:[ \t]*)\Q$value\E[ \t]*$/$1$replacement/mg);
        $n==1 or die "unexpected lab $key configuration\n";
    }
    return $text;
}
sub is_soak { return $_[0] =~ /\Asoak(?:-day|-check|-1000|-10000)?\z/; }
# A deficient generator is inconclusive only when every other observed gate
# passes. Missing evidence and failures must never be masked by low load.
sub soak_verdict {
    my ($p,$smoke)=@_;
    my @fail;
    push @fail,'invalid counts or send failures' unless $p->{requested}>0 && $p->{sent}>0 && $p->{sent}==$p->{attempted} && $p->{sent}<=$p->{requested} && $p->{successes}<=$p->{sent};
    push @fail,'DNS reliability' unless $p->{successes} >= ($smoke?1:0.9999)*$p->{sent};
    push @fail,'latency p99' if !$smoke && ($p->{latency_ms}{p99}//1e9)>=5;
    push @fail,'resource coverage' unless $p->{resource_coverage}{complete};
    push @fail,'container health' unless $p->{runtime_healthy};
    push @fail,'unexpected or unknown IP limiter activity' unless ($p->{cache_delta}{'total.num.queries_ip_ratelimited'}//-1)==0;
    return {status=>'FAIL',reasons=>\@fail} if @fail;
    return {status=>'INCONCLUSIVE',reasons=>['load generator missed target']} if !$smoke && $p->{sent}<0.99*$p->{requested};
    return {status=>'PASS',reasons=>[]};
}
sub validate_soak {
    my ($p)=@_;
    $p->{sent} >= 0.99*$p->{requested} or die "load generator missed target: $p->{case}\n";
    $p->{successes} >= 0.9999*$p->{sent} && $p->{sent}==$p->{attempted}
        && ($p->{latency_ms}{p99}//1e9)<5 or die "soak acceptance failed: $p->{case}\n";
    return 1;
}
1;
