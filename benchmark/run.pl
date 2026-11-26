#!/usr/bin/env perl
# Disposable bounded load experiment; internal bridge only and synthetic fixture names.
use v5.26;
use strict;
use warnings;
use FindBin qw($RealBin);
use lib $RealBin, "$RealBin/../tests/lib";
use DNSBench qw(now);
use Profiles qw(profile_cases resolver_config validate_soak);
use LabNetwork qw(validate_lab_network);
use RunIdentity qw(project_name);
use ResourceEvidence qw(parse_stats coverage clock_anomaly container_healthy check_heartbeat);
use lib "$RealBin/../lib";
use LocalDocker qw(require_local_docker);
use ProjectTest qw(run_command read_bytes write_bytes);
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use Cwd qw(abs_path);
use JSON::PP qw(encode_json decode_json);
use POSIX qw(:sys_wait_h _exit uname strftime);
use Time::HiRes qw(sleep time);
$|=1;
my $profile=@ARGV==0?'baseline':@ARGV==1 && $ARGV[0] eq '--quick'?'quick':@ARGV==2 && $ARGV[0] eq '--profile'?$ARGV[1]:'';
my @cases=profile_cases($profile);
my $quick=$profile eq 'quick';
require_local_docker();
my $root=abs_path("$RealBin/..");
my $dir=tempdir('unbound-bench-XXXXXXXX',TMPDIR=>1,CLEANUP=>0);
my $project=project_name($dir);
my @compose=('docker','compose','--env-file','/dev/null','-p',$project,'-f',"$dir/compose.yaml");
local @ENV{qw(COMPOSE_PROJECT_NAME COMPOSE_DISABLE_ENV_FILE COMPOSE_ENV_FILES COMPOSE_PROFILES)}=($project,1,'','');
my $client_image="$project-client:local";
local $ENV{BENCH_CLIENT_IMAGE}=$client_image;
my $sampler;
my $built=0;
my $started=0;
my $report;
my $out="$root/benchmark-results";
-l $out and die "unsafe reports directory\n";
make_path($out,{mode=>0700});
my $dest=tempdir('run-XXXXXXXX',DIR=>$out,CLEANUP=>0);
print "Reports: $dest\n";
sub cmd {
    my ($argv,$limit,$watchdog)=@_;
    my $r=run_command($argv,'',$limit//60,$watchdog);
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
    my $watchdog=ref($args[-1]) eq 'CODE'?pop @args:undef;
    my $limit=$args[0] eq 'phase' && @args==10 ? $args[8]+40 : 80;
    return cmd([@compose,'exec','-T','client','perl','/bench/client.pl',@args],$limit,$watchdog);
}
sub counters {
    my $stats=compose('exec','-T','unbound','unbound-control','-c','/etc/unbound/recursive.conf','stats_noreset');
    my %v;
    for (split /\n/,$stats) { if (/\A(total\.num\.(?:queries|cachehits|cachemiss|queries_ip_ratelimited)|time\.up)=([\d.]+)\z/) { $v{$1}=0+$2; } }
    exists $v{'total.num.cachehits'} && exists $v{'total.num.cachemiss'} && exists $v{'total.num.queries_ip_ratelimited'} or die "cache counters unavailable\n";
    return \%v;
}
sub probe {
    my ($address,$proto,$name)=@_;
    client('probe',$address,$proto,$name) =~ /\Aok\s*\z/ or die "invalid fixture probe response\n";
}
sub stop_sampler {
    return 0 unless defined $sampler;
    kill 'TERM',$sampler;
    my $pid=waitpid($sampler,0);
    my $status=$?;
    my $ok=$pid==$sampler && $status==0;
    undef $sampler;
    return $ok;
}
sub append_jsonl {
    my ($file,@rows)=@_;
    open my $fh,'>>:raw',$file or die "open sampler journal: $!\n";
    for my $row (@rows) { print {$fh} encode_json($row),"\n" or die "write sampler journal: $!\n"; }
    close $fh or die "close sampler journal: $!\n";
}
sub start_sampler {
    my ($file,$start,$ids,$duration,$case)=@_;
    my $events="$file.events.jsonl";
    my $interval=$duration>60?30:2;
    pipe(my $ready_r,my $ready_w) or die "sampler readiness pipe: $!\n";
    $sampler=fork(); defined $sampler or die "fork sampler: $!\n";
    if (!$sampler) {
        local $SIG{INT}='DEFAULT';
        my $stop=0; local $SIG{TERM}=sub {$stop=1};
        close $ready_r; print {$ready_w} '1' or _exit(1); close $ready_w or _exit(1);
        my ($last_mono,$last_wall)=(now(),time());
        my $next_progress=60;
        my %last_sample;
        my $worker_ok=eval {
            while (!$stop) {
                my ($tick,$wall)=(now(),time());
                my ($dm,$dw)=($tick-$last_mono,$wall-$last_wall);
                if (clock_anomaly($dm,$dw,$interval+20)) {
                    append_jsonl($events,{kind=>'clock_gap',elapsed=>$tick-$start,monotonic_gap=>$dm,wall_gap=>$dw,epoch=>$wall});
                    warn "[$case] sampler clock/cadence gap detected\n";
                }
                ($last_mono,$last_wall)=($tick,$wall);
                my %pending=map {$_=>$ids->{$_}} qw(resolver client);
                my $capture=sub {
                    my ($wanted)=@_;
                    my $raw=eval {cmd(['docker','stats','--no-stream','--format','{{json .}}',map {$wanted->{$_}} sort keys %$wanted],10)};
                    my $err=$@;
                    if (!defined $raw) {
                        append_jsonl($events,{kind=>'stats_error',elapsed=>now()-$start,epoch=>time(),roles=>[sort keys %$wanted],message=>substr($err,0,1000)});
                        return;
                    }
                    my ($samples,$errors)=parse_stats($raw,$wanted,now()-$start,time());
                    if (@$errors) {append_jsonl($events,{kind=>'stats_invalid',elapsed=>now()-$start,epoch=>time(),errors=>$errors});}
                    if (@$samples) {
                        append_jsonl($file,@$samples);
                        for my $sample (@$samples) {
                            delete $pending{$sample->{role}};
                            $last_sample{$sample->{role}}=$sample->{elapsed};
                        }
                        write_bytes("$file.heartbeat.tmp",encode_json(\%last_sample));
                        rename "$file.heartbeat.tmp","$file.heartbeat.json" or die "publish sampler heartbeat: $!\n";
                    }
                };
                $capture->({%pending});
                # Retry missing roles separately; a bad row must not hide the other role.
                for my $role (sort keys %pending) {
                    last if $stop;
                    $capture->({$role=>$pending{$role}});
                }
                if (%pending) {
                    append_jsonl($events,{kind=>'missing_sample',elapsed=>now()-$start,epoch=>time(),roles=>[sort keys %pending]});
                    warn "[$case] resource sample missing for ".join(',',sort keys %pending)."\n";
                }
                if ($duration>60 && now()-$start >= $next_progress) {
                    printf "[%s] %.0f/%d seconds elapsed (resource sampling; results at phase end)\n",$case,now()-$start,$duration;
                    $next_progress+=60 while $next_progress <= now()-$start;
                }
                while (!$stop && now()<$tick+$interval) {sleep 0.1;}
            }
            1;
        };
        warn $@ unless $worker_ok;
        _exit($worker_ok?0:1);
    }
    close $ready_w;
    my $ready=<$ready_r>; close $ready_r;
    defined $ready && $ready eq '1' or die "sampler failed to start\n";
}
sub phase {
    my ($id,$proto,$kind,$count,$workers,$rate,$duration,$mode,$address,$ids)=@_;
    sleep 1.1;
    my $before=counters();
    my %before_runtime=map {$_=>inspect_object('container',$ids->{$_})} qw(resolver client fixture);
    my $phase_utc=int(time());
    my $phase_start=now();
    my $phase_wall=time();
    my $file="$dest/$id-stats.jsonl";
    start_sampler($file,$phase_start,$ids,$duration,$id) unless $quick;
    my @watchdog;
    if ($duration>60) {
        my ($last_mono,$last_wall)=(now(),time());
        @watchdog=(sub {
            my ($mono,$wall)=(now(),time());
            clock_anomaly($mono-$last_mono,$wall-$last_wall,75)
                and die "resource watchdog: host clock or scheduling interruption\n";
            ($last_mono,$last_wall)=($mono,$wall);
            my $last=-f "$file.heartbeat.json"?decode_json(read_bytes("$file.heartbeat.json")):{};
            check_heartbeat($last,$mono-$phase_start,75);
        });
    }
    my $result=decode_json(client('phase',$address,$id,$proto,$kind,$count,$workers,$rate,$duration,$mode,@watchdog));
    my $phase_elapsed=now()-$phase_start;
    my $wall_elapsed=time()-$phase_wall;
    my $sampler_ok=$quick?1:stop_sampler();
    ref($result) eq 'HASH' && ($result->{requested}//0)==$count &&
        defined($result->{attempted}) && defined($result->{sent}) && defined($result->{successes}) &&
        $result->{successes} <= $result->{sent} && $result->{sent} <= $result->{attempted} &&
        $result->{successes} <= $result->{attempted} && $result->{attempted} <= $count
        or die "invalid client phase result\n";
    my @samples=-f $file?map {decode_json($_)} split(/\n/,read_bytes($file)):();
    my @events=-f "$file.events.jsonl"?map {decode_json($_)} split(/\n/,read_bytes("$file.events.jsonl")):();
    if (!$quick) {
        my $ev=coverage(\@samples,$duration,$duration>60?30:2);
        $ev->{sampler_ok}=$sampler_ok?1:0;
        $ev->{events}=scalar @events;
        $ev->{missing_ticks}=scalar grep {$_->{kind} eq 'missing_sample'} @events;
        $ev->{clock_anomalies}=scalar grep {$_->{kind} eq 'clock_gap'} @events;
        $ev->{clock_anomalies}++ if abs($wall_elapsed-$phase_elapsed)>5;
        $ev->{complete}=0 if !$sampler_ok || $ev->{clock_anomalies};
        $result->{resource_coverage}=$ev;
        printf "%s: resource coverage %s (resolver %d, client %d; diagnostics %d)\n",$id,$ev->{complete}?'complete':'INCOMPLETE',$ev->{roles}{resolver}{count},$ev->{roles}{client}{count},$ev->{events};
    }
    my %after_runtime=map {$_=>inspect_object('container',$ids->{$_})} qw(resolver client fixture);
    $result->{runtime_healthy}=JSON::PP::true;
    for my $role (keys %before_runtime) {
        $result->{runtime_healthy}=JSON::PP::false unless container_healthy($before_runtime{$role},$after_runtime{$role});
    }
    my $after=counters();
    $result->{phase_epoch}=$phase_utc;
    $result->{cache_delta}={map {$_=>$after->{$_}-$before->{$_}} grep {exists $before->{$_}} keys %$after};
    @$result{qw(case protocol cache workers resource_samples)}=($id,$proto,$kind,$workers,\@samples);
    printf "%s: %d/%d successful; sent %d, offered %.1f/%.1f qps, goodput %.1f qps; IP limited %d\n",$id,$result->{successes},$count,$result->{sent},$result->{offered_qps},$rate,$result->{successful_qps},$result->{cache_delta}{'total.num.queries_ip_ratelimited'}//0;
    return $result;
}
my $ok=eval {
    local $SIG{INT}=sub {die "interrupted\n"}; local $SIG{TERM}=sub {die "terminated\n"};
    for (qw(compose.yaml resolver.conf fixture.conf fixture-healthcheck.sh Dockerfile.client DNSBench.pm ClientWorkload.pm AsyncUDP.pm client.pl)) {copy("$RealBin/$_","$dir/$_") or die $!; chmod 0644,"$dir/$_" or die $!;}
    write_bytes("$dir/resolver.conf",resolver_config(read_bytes("$dir/resolver.conf"),$profile));
    my $image=decode_json(cmd(['docker','image','inspect','unbound-recursive:dev']))->[0];
    compose('config','--quiet');
    # Unique local tag; do not pull or publish the load generator at runtime.
    cmd(['docker','build','--pull','--no-cache','--tag',$client_image,'--file',"$dir/Dockerfile.client",$dir],300);
    $built=1;
    my $client_meta=inspect_object('image',$client_image);
    $started=1;
    compose('up','-d','--wait','--wait-timeout','90');
    my %ids=map {$_=>container_id($_ eq 'resolver'?'unbound':$_)} qw(resolver client fixture);
    my $network=inspect_object('network',"${project}_isolated");
    my $address=validate_lab_network($network,map {inspect_object('container',$ids{$_})} qw(resolver client fixture));
    probe($address,'udp','warm.bench.test.'); probe($address,'tcp','warm.bench.test.');
    my @phases;
    for my $case (@cases) {
        push @phases,phase(@$case,$address,\%ids);
        write_bytes("$dest/phases.json.tmp",JSON::PP->new->canonical->pretty->encode(\@phases));
        rename "$dest/phases.json.tmp","$dest/phases.json" or die "publish completed phases: $!\n";
    }
    sleep 2;
    probe($address,'udp','recovery.bench.test.'); probe($address,'tcp','recovery.bench.test.');
    my @os=uname();
    $report={schema=>3,client_image_id=>$client_meta->{Id},client_image_bytes=>$client_meta->{Size},client_image_architecture=>$client_meta->{Architecture},network=>'internal bridge; no published ports',utc=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime),os=>$os[0],architecture=>$os[4],image_id=>$image->{Id},image_bytes=>$image->{Size},image_architecture=>$image->{Architecture},docker_version=>cmd(['docker','version','--format','{{.Server.Version}}']),profile=>$profile,recovery=>JSON::PP::true,phases=>\@phases};
    write_bytes("$dest/report.json",JSON::PP->new->canonical->pretty->encode($report));
    my $header="case,protocol,cache,tcp_mode,udp_mode,workers,target_qps,offered_qps,requested,attempted,sent,not_attempted,failed,successes,seconds,successful_qps,ip_ratelimited,min_ms,mean_ms,median_ms,p95_ms,p99_ms,max_ms\n";
    my $csv=$header;
    my $md="# Synthetic DNS benchmark\n\nImage ID: `$report->{image_id}`\n\n| Case | Successes / requested | Successful qps | p95 ms | p99 ms |\n|---|---:|---:|---:|---:|\n";
    for my $p (@phases) {
        my $lat=$p->{latency_ms}//{};
        $csv.=join(',',@$p{qw(case protocol cache tcp_mode)},$p->{udp_mode}//'',@$p{qw(workers target_qps offered_qps requested attempted sent not_attempted failed successes seconds successful_qps)},$p->{cache_delta}{'total.num.queries_ip_ratelimited'}//0,map {$lat->{$_}//''} qw(min mean median p95 p99 max))."\n";
        $md.=sprintf("| %s | %d / %d | %.1f | %s | %s |\n",@$p{qw(case successes requested successful_qps)},map {defined($_)?sprintf('%.3f',$_):'n/a'} @$lat{qw(p95 p99)});
    }
    $md.="\nContainer-to-container internal bridge; loopback forwarding fixture only, not Internet recursion capacity. Transport mode is per phase; persistent TCP reconnects on errors. Async UDP percentile upper bounds have variable histogram resolution; see JSON. Resolver and client resources are sampled separately, not peaks.\n";
    write_bytes("$dest/report.csv",$csv); write_bytes("$dest/report.md",$md);
    print "Reports: $dest\n";
    if ($profile =~ /\A(?:baseline|stress|soak|soak-day|soak-check)\z/) {
        for my $p (@phases) {
            $p->{cache_delta}{'total.num.queries_ip_ratelimited'}==0 or die "unexpected IP limiter activity: $p->{case}\n";
        }
    }
    if ($profile eq 'ratelimit') {
        for my $p (@phases) {
            my $limited=$p->{cache_delta}{'total.num.queries_ip_ratelimited'}//0;
            if ($p->{target_qps}==50) { $limited==0 && $p->{successes} >= 0.95*$p->{requested} or die "below-limit phase failed: $p->{case}\n"; }
            else { $p->{offered_qps}>100 && $limited>0 or die "rate limiting not demonstrated: $p->{case}\n"; }
        }
    }
    if ($profile =~ /\A(?:soak|soak-day|soak-check)\z/) {
        for my $p (@phases) {
            if ($profile eq 'soak-check') {
                # Qualify the sampler on shared runners, not their timing performance.
                $p->{sent}>0 && $p->{successes}==$p->{sent} && $p->{attempted}==$p->{sent}
                    or die "sampling smoke DNS failure: $p->{case}\n";
            } else { validate_soak($p); }
            $p->{resource_coverage}{complete} or die "incomplete resource coverage: $p->{case}\n";
            $p->{runtime_healthy} or die "container restart, exit or OOM observed: $p->{case}\n";
        }
    }
    if ($quick) {
        for (@phases) { $_->{successes}==$_->{requested} or die "smoke test failed: $_->{case}\n"; }
        for (@phases) { my $key=$_->{cache} eq 'warm'?'total.num.cachehits':'total.num.cachemiss'; $_->{cache_delta}{$key}>0 or die "cache path not observed: $_->{case}\n"; }
    }
    1;
};
my $error=$@;
stop_sampler();
if (!$ok) {
    write_bytes("$dest/error.txt",$error);
    if ($started) {
        for my $op (qw(ps logs)) {
            my $r=eval {run_command([@compose,$op,($op eq 'logs'?('--no-color','--tail','100'):('--all'))],'',20)};
            write_bytes("$dest/$op.txt",$r->{stdout}."\n".$r->{stderr}) if $r;
        }
    }
}
if ($started) { eval {compose('down','--volumes','--remove-orphans')}; if ($@) {warn "cleanup failed; lab retained at $dir: $@"; exit 1;} }
if ($built) { eval {cmd(['docker','image','rm',$client_image],30)}; warn "client image cleanup failed: $@" if $@; }
remove_tree($dir,{safe=>1});
die $error unless $ok;
