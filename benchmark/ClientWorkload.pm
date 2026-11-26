package ClientWorkload;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
use File::Temp qw(tempdir);
use JSON::PP qw(encode_json decode_json);
use POSIX qw(_exit);
use Time::HiRes qw(sleep);
use DNSBench qw(query summarize now);
use AsyncUDP qw(udp_worker merge_workers);
our @EXPORT_OK = qw(run_phase);

# Run in the disposable client container. Only the host orchestrator chooses
# the resolver IP; the wire client still permits only synthetic fixture names.
sub run_phase {
    my ($address,$port,$id,$proto,$kind,$count,$workers,$rate,$duration,$mode)=@_;
    my $paced=defined $rate;
    $mode //= 'new';
    my $async=$mode eq 'async' && $proto eq 'udp' && $paced;
    $id =~ /\A(?:udp|tcp)-[a-z0-9-]{1,30}\z/ &&
        $proto =~ /\A(?:udp|tcp)\z/ && $kind =~ /\A(?:warm|cold)\z/ &&
        $count =~ /\A[0-9]+\z/ && $count>=1 && $count<=($async?8640000:$paced?100000:4000) &&
        $workers =~ /\A[0-9]+\z/ && $workers>=1 && $workers<=16
        or die "invalid bounded phase\n";
    if ($paced) {
        $rate =~ /\A[0-9]+\z/ && $rate>=1 && $rate<=10000 &&
            defined($duration) && $duration =~ /\A[0-9]+\z/ && $duration>=1 && $duration<=($async?86400:60) && $count==$rate*$duration
            or die "invalid bounded schedule\n";
    }
    ($async || $mode eq 'new' || ($mode eq 'persistent' && $proto eq 'tcp')) or die "invalid TCP mode\n";
    (!$async || $kind eq 'cold' || $count<=65000) or die "warm asynchronous phase too long\n";
    my $dir=tempdir('phase-XXXXXXXX',TMPDIR=>1,CLEANUP=>1);
    my $start=now()+($paced?0.1:0); my $deadline=$start+($paced?$duration:30);
    my (%children,@files);
    my $ok=eval {
        local $SIG{INT}=sub {die "phase interrupted\n"};
        local $SIG{TERM}=sub {die "phase terminated\n"};
        for my $w (0..$workers-1) {
            my $file="$dir/$w.json"; push @files,$file;
            my $pid=fork(); defined $pid or die "fork: $!\n";
            if (!$pid) {
                local $SIG{INT}='DEFAULT'; local $SIG{TERM}='DEFAULT'; srand();
                my $worker_ok=eval {
                    if ($async) {
                        my $data=udp_worker($address,$port,$id,$kind,$count,$workers,$w,$rate,$start,$duration);
                        open my $fh,'>:raw',$file or die "open async result: $!";
                        print {$fh} encode_json($data) or die "write async result: $!";
                        close $fh or die "close async result: $!";
                        _exit(0);
                    }
                    my @rows; my $socket;
                    for (my $i=$w;$i<$count && now()<$deadline;$i+=$workers) {
                        if ($paced) {
                            my $scheduled=$start+$i/$rate;
                            my $delay=$scheduled-now();
                            sleep $delay if $delay>0;
                            # Never replay an accumulated backlog as a burst.
                            next if now()>=$scheduled+$workers/$rate;
                            last if now()>=$deadline;
                        }
                        my $name=$kind eq 'warm'?'warm.bench.test.':"$id-$i.bench.test.";
                        push @rows,[query($port,$proto,$name,1,$address,$mode eq 'persistent'?\$socket:undef)];
                    }
                    close $socket if $socket;
                    if ($paced) {my $left=$deadline-now(); sleep $left if $left>0;}
                    open my $fh,'>:raw',$file or die "open phase result: $!";
                    print {$fh} encode_json({rows=>\@rows,end=>now()}) or die "write phase result: $!";
                    close $fh or die "close phase result: $!";
                    1;
                };
                warn $@ unless $worker_ok;
                _exit($worker_ok?0:1);
            }
            $children{$pid}=1;
        }
        for my $pid (keys %children) {
            my $done=waitpid($pid,0); my $status=$?;
            delete $children{$pid} if $done==$pid;
            $done==$pid && $status==0 or die "benchmark worker failed\n";
        }
        1;
    };
    my $error=$@;
    for my $pid (keys %children) {kill 'TERM',$pid; waitpid($pid,0);}
    die $error unless $ok;
    my $end=$start; my (@rows,@aggregates);
    for my $file (@files) {
        open my $fh,'<:raw',$file or die "read phase result: $!";
        local $/; my $data=decode_json(<$fh>); close $fh;
        if ($async) {push @aggregates,$data; next;}
        push @rows,@{$data->{rows}}; $end=$data->{end} if $data->{end}>$end;
    }
    my $result=$async?merge_workers(\@aggregates,$start,$count):summarize(\@rows,$end-$start,$count);
    if ($paced) {$result->{target_qps}=$rate; $result->{emission_seconds}=$duration; $result->{tcp_mode}=$async?'new':$mode; $result->{udp_mode}=$async?'async':'sequential' if $proto eq 'udp'; $result->{offered_qps}=$result->{sent}/$duration;}
    return $result;
}
1;
