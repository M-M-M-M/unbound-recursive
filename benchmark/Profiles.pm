package Profiles;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK=qw(profile_cases resolver_config);

# Each case: id, protocol, cache, requested, workers, target qps, seconds, TCP mode.
sub profile_cases {
    my ($profile)=@_;
    my @cases;
    my $add=sub {
        my ($id,$proto,$cache,$rate,$duration,$workers,$mode)=@_;
        push @cases,[$id,$proto,$cache,$rate*$duration,$workers,$rate,$duration,$mode];
    };
    if ($profile eq 'quick') {
        for my $p (qw(udp tcp)) { for my $c (qw(warm cold)) {$add->("$p-$c",$p,$c,12,1,1,'new');} }
    } elsif ($profile eq 'baseline' || $profile eq 'production') {
        my $rate=$profile eq 'baseline'?1000:50;
        for my $p (qw(udp tcp)) { for my $c (qw(warm cold)) {$add->("$p-$c",$p,$c,$rate,10,4,'new');} }
        $add->('tcp-persistent','tcp','warm',$rate,10,4,'persistent');
    } elsif ($profile eq 'ratelimit') {
        for my $p (qw(udp tcp)) { for my $rate (50,200) {$add->("$p-rate-$rate",$p,'warm',$rate,10,16,'new');} }
    } elsif ($profile eq 'stress') {
        for my $rate (500,1000,2500,5000,10000) {$add->("udp-stress-$rate",'udp','cold',$rate,10,16,'new');}
        $add->('udp-stress-30','udp','cold',1000,30,16,'new');
        $add->('udp-stress-60','udp','cold',1000,60,16,'new');
    } else {die "unknown benchmark profile\n";}
    return @cases;
}
sub resolver_config {
    my ($text,$profile)=@_;
    profile_cases($profile);
    for my $pair (['ip-ratelimit',100],['ratelimit',200]) {
        my ($key,$value)=@$pair;
        my $replacement=($profile eq 'baseline' || $profile eq 'stress')?0:$value;
        my $n=($text =~ s/^([ \t]*\Q$key\E:[ \t]*)\Q$value\E[ \t]*$/$1$replacement/mg);
        $n==1 or die "unexpected lab $key configuration\n";
    }
    return $text;
}
1;
