#!/usr/bin/env perl
# Disposable bounded load experiment; only loopback and synthetic fixture names.
use v5.26;
use strict;
use warnings;
use FindBin qw($RealBin);
use lib $RealBin, "$RealBin/../tests/lib";
use DNSBench qw(query summarize now);
use lib "$RealBin/../lib";
use LocalDocker qw(require_local_docker);
use ProjectTest qw(run_command read_bytes write_bytes);
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use Cwd qw(abs_path);
use JSON::PP qw(encode_json decode_json);
use POSIX qw(:sys_wait_h _exit uname strftime);
use Time::HiRes qw(sleep);
my $quick = @ARGV==1 && $ARGV[0] eq '--quick';
@ARGV==0 || $quick or die "usage: run.pl [--quick]\n";
require_local_docker();
my $root=abs_path("$RealBin/..");
my $dir=tempdir('unbound-bench-XXXXXXXX',TMPDIR=>1,CLEANUP=>0);
my ($project)=$dir=~m{([^/]+)\z}; $project=lc $project;
my @compose=('docker','compose','--env-file','/dev/null','-p',$project,'-f',"$dir/compose.yaml");
local @ENV{qw(COMPOSE_PROJECT_NAME COMPOSE_DISABLE_ENV_FILE COMPOSE_ENV_FILES COMPOSE_PROFILES)}=($project,1,'','');
my %children;
my $started=0;
my $report;
sub cmd {
    my ($argv,$limit)=@_;
    my $r=run_command($argv,'',$limit//60);
    die "command failed: @$argv\n$r->{stderr}\n" if $r->{code};
    return $r->{stdout};
}
sub compose { cmd([@compose,@_],120); }
sub port {
    my ($proto)=@_;
    my $binding=compose('port','--protocol',$proto,'unbound','5353');
    $binding=~/\A127\.0\.0\.1:(\d+)\s*\z/ or die "unsafe benchmark binding\n";
    return $1;
}
sub counters {
    my $stats=compose('exec','-T','unbound','unbound-control','-c','/etc/unbound/recursive.conf','stats_noreset');
    my %v;
    for (split /\n/,$stats) { if (/\A(total\.num\.(?:queries|cachehits|cachemiss|queries_ip_ratelimited)|time\.up)=([\d.]+)\z/) { $v{$1}=0+$2; } }
    exists $v{'total.num.cachehits'} && exists $v{'total.num.cachemiss'} or die "cache counters unavailable\n";
    return \%v;
}
sub probe {
    my ($port,$proto,$name)=@_;
    my $end=now()+15;
    while (now()<$end) { my ($result)=query($port,$proto,$name,1); return 1 if $result eq 'ok'; sleep 0.5; }
    die "fixture/recovery probe failed for $proto\n";
}
sub phase {
    my ($id,$port,$proto,$kind,$count,$workers,$container)=@_;
    sleep 1.1; # separate phases across limiter windows
    my $before=counters();
    my $start=now(); my $deadline=$start+30;
    my @files;
    for my $w (0..$workers-1) {
        my $file="$dir/$id-$w.json"; push @files,$file;
        my $pid=fork(); defined $pid or die "fork: $!\n";
        if (!$pid) {
            local $SIG{INT}='DEFAULT'; local $SIG{TERM}='DEFAULT'; srand();
            my @rows;
            for (my $i=$w;$i<$count && now()<$deadline;$i+=$workers) {
                my $name=$kind eq 'warm'?'warm.bench.test.':"$id-$i.bench.test.";
                push @rows,[query($port,$proto,$name,1)];
            }
            write_bytes($file,encode_json({rows=>\@rows, end=>now()})); _exit(0);
        }
        $children{$pid}=1;
    }
    my @samples; my $last=0;
    while (%children) {
        for my $pid (keys %children) {
            my $done=waitpid($pid,WNOHANG);
            if ($done==$pid) { delete $children{$pid}; $?==0 or die "benchmark worker failed\n"; }
            elsif ($done<0) { delete $children{$pid}; die "waitpid failed\n"; }
        }
        last unless %children;
        if (!$quick && now()-$last>=2) {
            $last=now();
            my $raw=eval { cmd(['docker','stats','--no-stream','--format','{{json .}}',$container],8) };
            if (defined $raw) { my $s=eval { decode_json($raw) }; if ($s) { delete @$s{qw(Name ID Container)}; push @samples,{elapsed=>now()-$start,%$s}; } }
        }
        sleep 0.02;
    }
    my $end=$start;
    my @rows; for my $file (@files) { my $data=decode_json(read_bytes($file)); push @rows,@{$data->{rows}}; $end=$data->{end} if $data->{end}>$end; }
    my $seconds=$end-$start;
    my $result=summarize(\@rows,$seconds,$count);
    my $after=counters();
    $result->{cache_delta}={map {$_=>$after->{$_}-$before->{$_}} grep {exists $before->{$_}} keys %$after};
    @$result{qw(case protocol cache workers resource_samples)}=($id,$proto,$kind,$workers,\@samples);
    printf "%s: %d/%d successful, %.1f successful qps\n",$id,$result->{successes},$count,$result->{successful_qps};
    return $result;
}
my $ok=eval {
    local $SIG{INT}=sub {die "interrupted\n"}; local $SIG{TERM}=sub {die "terminated\n"};
    for (qw(compose.yaml resolver.conf fixture.conf)) {copy("$RealBin/$_","$dir/$_") or die $!; chmod 0644,"$dir/$_" or die $!;}
    my $image=decode_json(cmd(['docker','image','inspect','unbound-recursive:dev']))->[0];
    compose('config','--quiet'); $started=1;
    compose('up','-d','--wait','--wait-timeout','90');
    my $udp=port('udp'); my $tcp=port('tcp');
    my $container=compose('ps','-q','unbound'); chomp $container;
    $container=~/\A[0-9a-f]{12,64}\z/ or die "invalid lab container\n";
    probe($udp,'udp','warm.bench.test.'); probe($tcp,'tcp','warm.bench.test.');
    my @phases;
    my $n=$quick?12:1000;
    for my $proto (qw(udp tcp)) {
        for my $kind (qw(warm cold)) {
            push @phases,phase("$proto-$kind",$proto eq 'udp'?$udp:$tcp,$proto,$kind,$n,$quick?1:4,$container);
        }
    }
    push @phases,phase('udp-concurrent',$udp,'udp','cold',4000,16,$container) unless $quick;
    sleep 2;
    probe($udp,'udp','recovery.bench.test.'); probe($tcp,'tcp','recovery.bench.test.');
    my @os=uname();
    $report={schema=>1,utc=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime),os=>$os[0],architecture=>$os[4],image_id=>$image->{Id},image_bytes=>$image->{Size},image_architecture=>$image->{Architecture},docker_version=>cmd(['docker','version','--format','{{.Server.Version}}']),profile=>$quick?'quick':'bounded',recovery=>JSON::PP::true,phases=>\@phases};
    my $out="$root/benchmark-results"; -l $out and die "unsafe reports directory\n"; make_path($out,{mode=>0700});
    my $dest=tempdir('run-XXXXXXXX',DIR=>$out,CLEANUP=>0);
    write_bytes("$dest/report.json",JSON::PP->new->canonical->pretty->encode($report));
    my $header="case,protocol,cache,workers,requested,attempted,successes,seconds,successful_qps,min_ms,mean_ms,median_ms,p95_ms,p99_ms,max_ms\n";
    my $csv=$header;
    my $md="# Synthetic DNS benchmark\n\nImage ID: `$report->{image_id}`\n\n| Case | Successes / requested | Successful qps | p95 ms | p99 ms |\n|---|---:|---:|---:|---:|\n";
    for my $p (@phases) {
        my $lat=$p->{latency_ms}//{};
        $csv.=join(',',@$p{qw(case protocol cache workers requested attempted successes seconds successful_qps)},map {$lat->{$_}//''} qw(min mean median p95 p99 max))."\n";
        $md.=sprintf("| %s | %d / %d | %.1f | %s | %s |\n",@$p{qw(case successes requested successful_qps)},map {defined($_)?sprintf('%.3f',$_):'n/a'} @$lat{qw(p95 p99)});
    }
    $md.="\nLoopback forwarding fixture only; not Internet recursion capacity. TCP includes new connections. Resources are sampled, not peaks.\n";
    write_bytes("$dest/report.csv",$csv); write_bytes("$dest/report.md",$md);
    print "Reports: $dest\n";
    if ($quick) {
        for (@phases) { $_->{successes}==$_->{requested} or die "smoke test failed: $_->{case}\n"; }
        for (@phases) { my $key=$_->{cache} eq 'warm'?'total.num.cachehits':'total.num.cachemiss'; $_->{cache_delta}{$key}>0 or die "cache path not observed: $_->{case}\n"; }
    }
    1;
};
my $error=$@;
for my $pid (keys %children) {kill 'TERM',$pid; waitpid($pid,0);}
if ($started) { eval {compose('down','--volumes','--remove-orphans')}; if ($@) {warn "cleanup failed; lab retained at $dir: $@"; exit 1;} }
remove_tree($dir,{safe=>1});
die $error unless $ok;
