package BenchmarkMetrics;
use v5.26;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK=qw(report_lines);
sub number {
    my ($v)=@_;
    defined($v) && !ref($v) && $v =~ /\A(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/ && $v>=0 && $v<=1e12
        or die "invalid benchmark metric\n";
    return sprintf('%.12g',$v);
}
sub report_lines {
    my ($r,$run)=@_;
    ref($r) eq 'HASH' && ($r->{schema}//0)==3 && ($r->{profile}//'') =~ /\A(?:quick|baseline|production|ratelimit|stress|soak|soak-day|soak-check)\z/ &&
        $run =~ /\Arun-[A-Za-z0-9_]{8}\z/ && ref($r->{phases}) eq 'ARRAY' && @{$r->{phases}}>=1 && @{$r->{phases}}<=10
        or die "invalid benchmark report\n";
    my @lines;
    for my $p (@{$r->{phases}}) {
        ref($p) eq 'HASH' && ($p->{case}//'') =~ /\A(?:udp|tcp)-[a-z0-9-]{1,30}\z/ &&
            ($p->{phase_epoch}//'') =~ /\A[0-9]{10}\z/ or die "invalid phase identity\n";
        my $tags="run=$run,profile=$r->{profile},case=$p->{case}";
        my @fields=map {"$_=".number($p->{$_})} qw(target_qps offered_qps successful_qps requested sent successes failed not_attempted);
        push @fields,'ip_limited='.number($p->{cache_delta}{'total.num.queries_ip_ratelimited'});
        for my $k (qw(p95 p99)) {push @fields,"${k}_ms=".number($p->{latency_ms}{$k}) if exists $p->{latency_ms}{$k};}
        push @lines,"unbound_benchmark_phase,$tags ".join(',',@fields)." $p->{phase_epoch}";
        ref($p->{resource_samples}) eq 'ARRAY' && @{$p->{resource_samples}}<=6000 or die "invalid resource samples\n";
        for my $s (@{$p->{resource_samples}}) {
            ($s->{role}//'') =~ /\A(?:client|resolver)\z/ or die "invalid sample role\n";
            ($s->{CPUPerc}//'') =~ /\A([0-9.]+)%\z/ or die "invalid CPU sample\n";
            my $cpu=number($1);
            ($s->{MemUsage}//'') =~ /\A([0-9.]+)(B|KiB|MiB|GiB)\s*\// or die "invalid RAM sample\n";
            my ($mem,$unit)=(number($1),$2); my %factor=(B=>1,KiB=>1024,MiB=>1048576,GiB=>1073741824);
            my $ts=$p->{phase_epoch}+int(number($s->{elapsed}));
            push @lines,"unbound_benchmark_resource,$tags,role=$s->{role} cpu_percent=$cpu,memory_bytes=".number($mem*$factor{$unit})." $ts";
        }
    }
    return join("\n",@lines)."\n";
}
1;
