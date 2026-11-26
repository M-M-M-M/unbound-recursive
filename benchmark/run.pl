#!/usr/bin/env perl
# Disposable bounded load experiment; internal bridge only and synthetic fixture names.
use v5.26;
use strict;
use warnings;
use FindBin qw($RealBin);
use lib $RealBin, "$RealBin/../tests/lib";
use DNSBench qw(now);
use LabNetwork qw(validate_lab_network);
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
my $client_image="$project-client:local";
local $ENV{BENCH_CLIENT_IMAGE}=$client_image;
my $sampler;
my $built=0;
my $started=0;
my $report;
sub cmd {
    my ($argv,$limit)=@_;
    my $r=run_command($argv,'',$limit//60);
    die "command failed: @$argv\n$r->{stdout}\n$r->{stderr}\n" if $r->{code};
    return $r->{stdout};
}
sub compose { cmd([@compose,@_],120); }
sub inspect_object {
    my ($type,$id)=@_;
    my $objects=decode_json(cmd(['docker',$type,'inspect',$id]));
    ref($objects) eq 'ARRAY' && @$objects==1 or die "invalid Docker inspection for $id\n";
    return $objects->[0];
}
sub container_id {
    my ($service)=@_;
    my $id=compose('ps','-q',$service); chomp $id;
    $id =~ /\A[0-9a-f]{64}\z/ or die "invalid lab container for $service\n";
    return $id;
}
sub client {
    my (@args)=@_;
    return cmd([@compose,'exec','-T','client','perl','/bench/client.pl',@args],45);
}
sub counters {
    my $stats=compose('exec','-T','unbound','unbound-control','-c','/etc/unbound/recursive.conf','stats_noreset');
    my %v;
    for (split /\n/,$stats) { if (/\A(total\.num\.(?:queries|cachehits|cachemiss|queries_ip_ratelimited)|time\.up)=([\d.]+)\z/) { $v{$1}=0+$2; } }
    exists $v{'total.num.cachehits'} && exists $v{'total.num.cachemiss'} or die "cache counters unavailable\n";
    return \%v;
}
sub probe {
    my ($address,$proto,$name)=@_;
    client('probe',$address,$proto,$name) =~ /\Aok\s*\z/ or die "invalid fixture probe response\n";
}
sub stop_sampler {
    return unless defined $sampler;
    kill 'TERM',$sampler; waitpid($sampler,0); undef $sampler;
}
sub start_sampler {
    my ($file,$start,$ids)=@_;
    pipe(my $ready_r,my $ready_w) or die "sampler readiness pipe: $!\n";
    $sampler=fork(); defined $sampler or die "fork sampler: $!\n";
    if (!$sampler) {
        local $SIG{INT}='DEFAULT';
        # Finish the current bounded Docker stats call before leaving; avoid
        # killing its subprocess midway through an output sample.
        my $stop=0; local $SIG{TERM}=sub {$stop=1};
        close $ready_r; print {$ready_w} '1' or _exit(1); close $ready_w or _exit(1);
        while (!$stop) {
            my $raw=eval {cmd(['docker','stats','--no-stream','--format','{{json .}}',@$ids{qw(resolver client)}],8)};
            if (defined $raw) {
                my @samples;
                for my $line (split /\n/,$raw) {
                    my $s=eval {decode_json($line)}; next unless ref($s) eq 'HASH';
                    my $short=$s->{ID}//$s->{Container}//'';
                    next unless $short =~ /\A[0-9a-f]{12,64}\z/;
                    my ($role)=grep {index($ids->{$_},$short)==0} qw(resolver client);
                    next unless defined $role;
                    delete @$s{qw(Name ID Container)};
                    push @samples,{elapsed=>now()-$start,role=>$role,%$s};
                }
                if (@samples) {
                    open my $fh,'>>:raw',$file or _exit(1);
                    print {$fh} encode_json($_),"\n" for @samples;
                    close $fh or _exit(1);
                }
            }
            for (1..20) {last if $stop; sleep 0.1;}
        }
        _exit(0);
    }
    close $ready_w;
    my $ready=<$ready_r>; close $ready_r;
    defined $ready && $ready eq '1' or die "sampler failed to start\n";
}
sub phase {
    my ($id,$address,$proto,$kind,$count,$workers,$ids)=@_;
    sleep 1.1;
    my $before=counters();
    my $file="$dir/$id-stats.jsonl";
    start_sampler($file,now(),$ids) unless $quick;
    my $result=decode_json(client('phase',$address,$id,$proto,$kind,$count,$workers));
    stop_sampler();
    ref($result) eq 'HASH' && ($result->{requested}//0)==$count &&
        defined($result->{attempted}) && defined($result->{successes}) &&
        $result->{successes} <= $result->{attempted} && $result->{attempted} <= $count
        or die "invalid client phase result\n";
    my @samples=-f $file?map {decode_json($_)} split(/\n/,read_bytes($file)):();
    my $after=counters();
    $result->{cache_delta}={map {$_=>$after->{$_}-$before->{$_}} grep {exists $before->{$_}} keys %$after};
    @$result{qw(case protocol cache workers resource_samples)}=($id,$proto,$kind,$workers,\@samples);
    printf "%s: %d/%d successful, %.1f successful qps\n",$id,$result->{successes},$count,$result->{successful_qps};
    return $result;
}
my $ok=eval {
    local $SIG{INT}=sub {die "interrupted\n"}; local $SIG{TERM}=sub {die "terminated\n"};
    for (qw(compose.yaml resolver.conf fixture.conf Dockerfile.client DNSBench.pm ClientWorkload.pm client.pl)) {copy("$RealBin/$_","$dir/$_") or die $!; chmod 0644,"$dir/$_" or die $!;}
    my $image=decode_json(cmd(['docker','image','inspect','unbound-recursive:dev']))->[0];
    compose('config','--quiet');
    # Unique local tag; do not pull or publish the load generator at runtime.
    $built=1;
    cmd(['docker','build','--pull','--no-cache','--tag',$client_image,'--file',"$dir/Dockerfile.client",$dir],300);
    my $client_meta=inspect_object('image',$client_image);
    $started=1;
    compose('up','-d','--wait','--wait-timeout','90');
    my %ids=map {$_=>container_id($_ eq 'resolver'?'unbound':$_)} qw(resolver client fixture);
    my $network=inspect_object('network',"${project}_isolated");
    my $address=validate_lab_network($network,map {inspect_object('container',$ids{$_})} qw(resolver client fixture));
    probe($address,'udp','warm.bench.test.'); probe($address,'tcp','warm.bench.test.');
    my @phases;
    my $n=$quick?12:1000;
    for my $proto (qw(udp tcp)) {
        for my $kind (qw(warm cold)) {
            push @phases,phase("$proto-$kind",$address,$proto,$kind,$n,$quick?1:4,\%ids);
        }
    }
    push @phases,phase('udp-concurrent',$address,'udp','cold',4000,16,\%ids) unless $quick;
    sleep 2;
    probe($address,'udp','recovery.bench.test.'); probe($address,'tcp','recovery.bench.test.');
    my @os=uname();
    $report={schema=>2,client_image_id=>$client_meta->{Id},client_image_bytes=>$client_meta->{Size},client_image_architecture=>$client_meta->{Architecture},network=>'internal bridge; no published ports',utc=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime),os=>$os[0],architecture=>$os[4],image_id=>$image->{Id},image_bytes=>$image->{Size},image_architecture=>$image->{Architecture},docker_version=>cmd(['docker','version','--format','{{.Server.Version}}']),profile=>$quick?'quick':'bounded',recovery=>JSON::PP::true,phases=>\@phases};
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
    $md.="\nContainer-to-container internal bridge; loopback forwarding fixture only, not Internet recursion capacity. TCP includes new connections. Resolver and client resources are sampled separately, not peaks.\n";
    write_bytes("$dest/report.csv",$csv); write_bytes("$dest/report.md",$md);
    print "Reports: $dest\n";
    if ($quick) {
        for (@phases) { $_->{successes}==$_->{requested} or die "smoke test failed: $_->{case}\n"; }
        for (@phases) { my $key=$_->{cache} eq 'warm'?'total.num.cachehits':'total.num.cachemiss'; $_->{cache_delta}{$key}>0 or die "cache path not observed: $_->{case}\n"; }
    }
    1;
};
my $error=$@;
stop_sampler();
if ($started) { eval {compose('down','--volumes','--remove-orphans')}; if ($@) {warn "cleanup failed; lab retained at $dir: $@"; exit 1;} }
if ($built) { eval {cmd(['docker','image','rm',$client_image],30)}; warn "client image cleanup failed: $@" if $@; }
remove_tree($dir,{safe=>1});
die $error unless $ok;
