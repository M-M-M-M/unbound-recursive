package AsyncUDP;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
use IO::Socket::INET;
use IO::Select;
use Socket qw(AF_INET inet_pton);
use Time::HiRes qw(sleep);
use DNSBench qw(packet classify_reply now);
our @EXPORT_OK = qw(udp_worker merge_workers);

# Keep only in-flight requests, a one-second expiry queue and a fixed-resolution
# histogram. Exact counts, min/max and mean; percentile upper bounds use
# 0.01 ms below 10 ms, 0.1 ms below 100 ms, 1 ms thereafter.
sub udp_worker {
    my ($address,$port,$id,$kind,$count,$workers,$worker,$rate,$start,$duration)=@_;
    $address =~ /\A[0-9.]+\z/ && inet_pton(AF_INET,$address) or die "invalid numeric endpoint\n";
    my $sock=IO::Socket::INET->new(PeerAddr=>$address,PeerPort=>$port,Proto=>'udp') or die "UDP socket: $!\n";
    $sock->blocking(0);
    my $select=IO::Select->new($sock);
    my (%pending,@expiry,%outcomes,%hist);
    my ($sent,$sum,$min,$max,$stray)=(0,0,undef,undef,0);
    my $end=$start+$duration;
    my $i=$worker;
    my $interval=$workers/$rate;
    # No reuse of a transaction ID for a pending request; cold names are unique
    # even across wraps. Warm async phases are bounded to fewer than 65536 sends.
    my $seq=int(rand(65536));
    while (($i<$count && now()<$end) || keys %pending) {
        my $t=now();
        while (@expiry && $expiry[0][0]+1 <= $t) {
            my $e=shift @expiry;
            if (exists $pending{$e->[1]} && $pending{$e->[1]}==$e) {
                delete $pending{$e->[1]}; ++$outcomes{timeout};
            }
        }
        if ($i<$count && $t<$end && $t >= $start+$i/$rate) {
            # Skip expired emission slots rather than sending a catch-up burst.
            my $missed=int(($t-($start+$i/$rate))/$interval);
            $i += $missed*$workers if $missed>0;
            if ($i<$count && $t<$end && keys(%pending)<2048) {
                my $tx=$seq++ & 65535;
                if (!exists $pending{$tx}) {
                    my $name=$kind eq 'warm'?'warm.bench.test.':"$id-$i.bench.test.";
                    my $request=packet($tx,$name);
                    my $at=now();
                    my $n=$sock->send($request);
                    if (defined $n && $n==length($request)) {
                        ++$sent;
                        my $entry=[$at,$tx,$request];
                        $pending{$tx}=$entry; push @expiry,$entry;
                    } else {++$outcomes{write_error};}
                }
            }
            $i+=$workers;
        }
        my $wait=0.01;
        if ($i<$count && now()<$end) {my $left=$start+$i/$rate-now(); $wait=$left if $left<$wait;}
        if (@expiry) {my $left=$expiry[0][0]+1-now(); $wait=$left if $left<$wait;}
        $wait=0 if $wait<0;
        if ($select->can_read($wait)) {
            # Drain bounded batches so the emission and timeout clocks cannot starve.
            for (1..64) {
                my $peer=recv($sock,my $reply,65535,0);
                last unless defined $peer;
                if (length($reply)<12) {++$stray; next;}
                my $tx=unpack('n',$reply);
                my $entry=$pending{$tx};
                if (!$entry || substr($reply,12,length($entry->[2])-12) ne substr($entry->[2],12)) {++$stray; next;}
                delete $pending{$tx};
                my $ms=1000*(now()-$entry->[0]);
                my $status=$ms>=1000?'timeout':classify_reply($reply,$entry->[2]);
                ++$outcomes{$status};
                if ($status eq 'ok') {
                    $sum+=$ms;
                    $min=$ms if !defined($min) || $ms<$min;
                    $max=$ms if !defined($max) || $ms>$max;
                    my $step=$ms<10?1:$ms<100?10:100;
                    my $bin=(int($ms*100/$step)+1)*$step; ++$hist{$bin};
                }
            }
        }
    }
    close $sock or die "close UDP socket: $!\n";
    my $left=$end-now(); sleep $left if $left>0;
    return {sent=>$sent,outcomes=>\%outcomes,hist=>\%hist,sum=>$sum,min=>$min,max=>$max,stray=>$stray,end=>now()};
}
sub merge_workers {
    my ($results,$start,$count)=@_;
    my (%outcomes,%hist);
    my ($sent,$sum,$min,$max,$stray,$end)=(0,0,undef,undef,0,$start);
    for my $r (@$results) {
        $sent+=$r->{sent}; $sum+=$r->{sum}; $stray+=$r->{stray};
        $end=$r->{end} if $r->{end}>$end;
        $min=$r->{min} if defined($r->{min}) && (!defined($min) || $r->{min}<$min);
        $max=$r->{max} if defined($r->{max}) && (!defined($max) || $r->{max}>$max);
        $outcomes{$_}+=$r->{outcomes}{$_} for keys %{$r->{outcomes}};
        $hist{$_}+=$r->{hist}{$_} for keys %{$r->{hist}};
    }
    my $attempted=0; $attempted+=$_ for values %outcomes;
    my $n=$outcomes{ok}//0;
    my $seconds=$end-$start;
    my %r=(requested=>$count,attempted=>$attempted,sent=>$sent,not_attempted=>$count-$attempted,failed=>$attempted-$n,successes=>$n,outcomes=>\%outcomes,seconds=>$seconds,successful_qps=>$seconds>0?$n/$seconds:0,unmatched_udp_replies=>$stray,latency_resolution_ms=>0.01,latency_histogram=>'upper bounds: 0.01 ms below 10, 0.1 below 100, 1 thereafter');
    if ($n) {
        my @ranks= (int(($n+1)/2),int(($n+2)/2),int(($n*95+99)/100),int(($n*99+99)/100));
        my @v; my $seen=0;
        for my $bin (sort {$a<=>$b} keys %hist) {
            $seen+=$hist{$bin};
            push @v,$bin/100 while @v<@ranks && $seen >= $ranks[@v];
        }
        $r{latency_ms}={min=>$min,max=>$max,mean=>$sum/$n,median=>($v[0]+$v[1])/2,p95=>$v[2],p99=>$v[3]};
    }
    return \%r;
}
1;
