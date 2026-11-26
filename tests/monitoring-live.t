use v5.26;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use FindBin;
use Cwd qw(abs_path getcwd);
use JSON::PP qw(decode_json encode_json);
use Time::HiRes qw(sleep time);
use lib "$FindBin::Bin/lib";
use ProjectTest qw(run_command read_bytes write_bytes);
use lib "$FindBin::Bin/../monitoring";
use BenchmarkMetrics qw(report_lines);
use lib "$FindBin::Bin/../lib";
use LocalDocker qw(require_local_docker);
plan skip_all => 'opt in with make test-monitoring' unless ($ENV{RUN_MONITORING_LIVE}//'') eq '1';
my $operations=($ENV{RUN_MONITORING_OPERATIONS}//'') eq '1';
require_local_docker() if $operations;
$< != 0 or BAIL_OUT('run lab as non-root Docker operator');
my $source=abs_path("$FindBin::Bin/..");
my $dir=tempdir('unbound-monitor-XXXXXXXX', TMPDIR=>1, CLEANUP=>0);
my ($base)=$dir=~m{([^/]+)\z};
my $project=lc $base;
my $started=0;
my @compose=('docker','compose','--env-file','/dev/null','-p',$project,'-f',"$dir/compose.yaml");
# Environment only, random disposable credentials, never production credentials.
open my $random,'<:raw','/dev/urandom' or BAIL_OUT('cannot obtain random bytes');
read($random,my $bytes,48)==48 or BAIL_OUT('random bytes unavailable');
close $random or die $!;
local $ENV{LAB_TOKEN}=unpack('H*',substr($bytes,0,32));
local $ENV{LAB_PASSWORD}=unpack('H*',substr($bytes,32));
local $ENV{LAB_UID}=$<;
my ($gid)=split / /, $(;
local $ENV{LAB_GID}=$gid;
# Prevent an operator's Compose defaults from changing the isolated profile.
local $ENV{COMPOSE_PROJECT_NAME}=$project;
local $ENV{COMPOSE_PROFILES}='';
local $ENV{COMPOSE_ENV_FILES}='';
local $ENV{COMPOSE_DISABLE_ENV_FILE}=1;
my $cwd=getcwd();
my $snapshot="$dir/metrics/unbound.lp";
my $dashboard=decode_json(read_bytes("$source/monitoring/grafana-snapshot-flux.json"));
my $filter='from(bucket: "resolver-lab") |> range(start: -10m) |> filter(fn: (r) => r._measurement == "unbound_snapshot" and r._field == "total_num_queries" and r.host == "resolver-lab")';
sub command { run_command($_[0], '', $_[1]//60) }
sub require_cmd {
    my ($argv,$label,$timeout)=@_;
    my $r=command($argv,$timeout);
    ok($r->{code}==0,$label) or die "$label failed (exit $r->{code})\n";
    return $r->{stdout};
}
sub poll {
    my ($cb,$timeout)=@_;
    my $end=time()+$timeout;
    while (time()<$end) { my $val=eval {$cb->()}; return $val if defined $val; sleep 2; }
    return undef;
}
sub query {
    my ($flux)=@_;
    my $r=command([@compose,'exec','-T','influxdb','influx','query','--host','http://localhost:8086','--org','lab','--raw',$flux],30);
    return undef if $r->{code};
    my @rows=grep { /,(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*\z/ } split /\n/,$r->{stdout};
    return undef unless @rows;
    my ($v)=$rows[-1]=~/,(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\s*\z/;
    return $v;
}
sub latest_ns { query($filter.' |> last() |> map(fn: (r) => ({_value: int(v: r._time)}))') }
sub count_points { query($filter.' |> count() |> keep(columns: ["_value"])') }
sub collect {
    require_cmd([$^X,"$source/monitoring/collect-stats.pl",$snapshot],'collect and export real Unbound statistics');
    my $line=read_bytes($snapshot);
    my ($ts)=$line=~/ (\d+)\n\z/;
    defined $ts or die "timestamp missing\n";
    return $ts;
}
my $success=eval {
    make_path("$dir/metrics","$dir/dashboards","$dir/provisioning/datasources","$dir/provisioning/dashboards",{mode=>0755});
    chmod 0750,"$dir/metrics" or die $!;
    for my $file (qw(compose.yaml telegraf.conf provisioning/datasources/influx.yaml provisioning/dashboards/resolver.yaml)) {
        copy("$source/monitoring/lab/$file","$dir/$file") or die "copy $file: $!";
        chmod 0644,"$dir/$file" or die $!;
    }
    if ($operations) {
        make_path("$dir/provisioning/alerting",{mode=>0755});
        copy("$source/monitoring/lab/provisioning/alerts-freshness.json","$dir/provisioning/alerting/freshness.json") or die $!;
        chmod 0644,"$dir/provisioning/alerting/freshness.json" or die $!;
        # Accelerate retention only in this throwaway Compose project.
        my $compose=read_bytes("$dir/compose.yaml");
        $compose =~ s/(      DOCKER_INFLUXDB_INIT_MODE: setup\n)/$1      INFLUXD_STORAGE_RETENTION_CHECK_INTERVAL: 5s\n/ or die "retention test override missing\n";
        write_bytes("$dir/compose.yaml",$compose);
    }
    # Provision an exact copy with lab-specific variable defaults.
    $dashboard->{templating}{list}[0]{current}={text=>'Resolver lab Flux',value=>'resolver-lab-flux'};
    $dashboard->{templating}{list}[1]{query}='resolver-lab';
    $dashboard->{templating}{list}[1]{current}={text=>'resolver-lab',value=>'resolver-lab'};
    write_bytes("$dir/dashboards/resolver.json",encode_json($dashboard));
    chmod 0644,"$dir/dashboards/resolver.json" or die $!;
    chdir $dir or die "chdir lab: $!";
    require_cmd(['docker','image','inspect','unbound-recursive:dev'],'local resolver image exists (make build)');
    require_cmd([@compose,'config','--quiet'],'disposable Compose configuration');
    $started=1;
    require_cmd([@compose,'up','-d','--wait','--wait-timeout','180','unbound','influxdb','grafana'],'start isolated services',900);
    my $first=collect();
    require_cmd([@compose,'up','-d','telegraf'],'start stats-only Telegraf',600);
    my $received=poll(sub {my $v=latest_ns(); defined($v)&&$v eq $first ? $v : undef},90);
    is($received,$first,'InfluxDB preserves exact source timestamp') or die "no initial sample\n";
    my $n=count_points();
    is($n,1,'one initial stored point');
    sleep 8;
    is(latest_ns(),$first,'repeated file reads do not refresh timestamp');
    is(count_points(),1,'duplicate source points merge rather than multiply');
    require_cmd([@compose,'exec','-T','telegraf','sh','-c','test ! -S /var/run/docker.sock && test ! -S /run/resolver/control.sock && test ! -w /metrics/unbound.lp && test ! -w /metrics'],'Telegraf has no socket or snapshot write access');
    # Generate local, deterministic queries without external DNS dependency.
    require_cmd([@compose,'exec','-T','unbound','sh','-c','i=0; while [ "$i" -lt 30 ]; do /usr/local/bin/healthcheck.sh || exit 1; i=$((i+1)); done'],'generate 30 local DNS queries');
    my $second=collect();
    isnt($second,$first,'new collection timestamp');
    ok(defined poll(sub {my $v=latest_ns(); defined($v)&&$v eq $second ? $v : undef},60),'new sample arrives in InfluxDB');
    is(count_points(),2,'exactly two source timestamps stored');
    my $before=query($filter.' |> last() |> keep(columns: ["_value"])');
    cmp_ok($before,'>=',30,'query counter increased');
    my $rate=query($filter.' |> derivative(unit: 1s, nonNegative: true, initialZero: false) |> last() |> keep(columns: ["_value"])');
    cmp_ok($rate,'>',0,'positive query rate calculated from source points');
    my $age=query($filter.' |> last() |> map(fn: (r) => ({_value: float(v: int(v: now()) - int(v: r._time)) / 1000000000.0}))');
    ok(defined($age)&&$age>=0,'freshness query yields source age');
    my $binding=require_cmd([@compose,'port','grafana','3000'],'resolve loopback Grafana port');
    $binding =~ /\A127\.0\.0\.1:(\d+)\s*\z/ or die 'unexpected Grafana binding';
    my $url="http://127.0.0.1:$1";
    my @curl=('curl','--noproxy','*','--fail','--silent','--show-error','--max-time','15','-u',"lab:$ENV{LAB_PASSWORD}");
    my $api=poll(sub {my $r=command([@curl,"$url/api/dashboards/uid/unbound-recursive-snapshot"],20); $r->{code}?undef:$r->{stdout}},90);
    ok(defined $api,'Grafana provisioned the dashboard') or die 'dashboard missing';
    my $provisioned=decode_json($api);
    is(scalar @{$provisioned->{dashboard}{panels}},scalar @{$dashboard->{panels}},'all dashboard panels provisioned');
    for my $panel (@{$dashboard->{panels}}) {
        my $flux=$panel->{targets}[0]{query};
        $flux =~ s/\$\{bucket\}/resolver-lab/g;
        # v.timeRangeStart/Stop and v.windowPeriod are Grafana Flux macros.
        my $payload=encode_json({from=>'now-10m',to=>'now',queries=>[{refId=>'A',datasource=>{uid=>'resolver-lab-flux',type=>'influxdb'},query=>$flux,intervalMs=>2000,maxDataPoints=>300}]});
        my $r=run_command([@curl,'-H','Content-Type: application/json','--data-binary','@-',"$url/api/ds/query"],$payload,30);
        my $json=eval {decode_json($r->{stdout})};
        my $res=$json && $json->{results}{A};
        ok($r->{code}==0 && $res && !$res->{error} && ($res->{status}//200)<400,"Grafana Flux panel: $panel->{title}")
            or diag($res ? ($res->{error}//'query failed') : 'query failed');
        if ($panel->{id}==1) { ok($res && @{$res->{frames}//[]},'Grafana query-rate returned data frames'); }
    }
    # Test the report ingestion path using synthetic, known aggregates. This
    # does not run a benchmark or connect the benchmark and monitoring labs.
    my $epoch=int(time())-5;
    my $bench={schema=>3,profile=>'baseline',phases=>[{case=>'udp-warm',phase_epoch=>$epoch,
        target_qps=>1000,offered_qps=>900,successful_qps=>890,requested=>10000,sent=>9000,
        successes=>8900,failed=>100,not_attempted=>1000,cache_delta=>{'total.num.queries_ip_ratelimited'=>0},
        latency_ms=>{p95=>0.5,p99=>1},resource_samples=>[{role=>'resolver',CPUPerc=>'2.5%',MemUsage=>'10MiB / 512MiB',elapsed=>2}]}]};
    my $lp=report_lines($bench,'run-Test1234');
    my $written=run_command([@compose,'exec','-T','influxdb','influx','write','--host','http://localhost:8086','--org','lab','--bucket','resolver-lab','--precision','s'],$lp,30);
    is($written->{code},0,'import synthetic benchmark report into isolated bucket') or die 'benchmark write failed';
    my $bench_filter='from(bucket: "resolver-lab") |> range(start: -10m) |> filter(fn: (r) => r._measurement == "unbound_benchmark_phase" and r._field == "successful_qps" and r.run == "run-Test1234")';
    is(query($bench_filter.' |> last() |> keep(columns: ["_value"])'),890,'benchmark goodput stored without conversion');
    is(query($bench_filter.' |> last() |> map(fn: (r) => ({_value: int(v: r._time) / 1000000000}))'),$epoch,'benchmark source phase timestamp preserved');
    my $bench_dash=decode_json(read_bytes("$source/monitoring/grafana-benchmark-flux.json"));
    write_bytes("$dir/dashboards/benchmark.json",encode_json($bench_dash));
    chmod 0644,"$dir/dashboards/benchmark.json" or die $!;
    my $bench_api=poll(sub {my $r=command([@curl,"$url/api/dashboards/uid/unbound-recursive-benchmark"],20); $r->{code}?undef:$r->{stdout}},90);
    ok(defined $bench_api,'Grafana provisions added benchmark dashboard') or die 'benchmark dashboard missing';
    for my $panel (@{$bench_dash->{panels}}) {
        my $payload=encode_json({from=>'now-10m',to=>'now',queries=>[{refId=>'A',datasource=>{uid=>'resolver-lab-flux',type=>'influxdb'},query=>$panel->{targets}[0]{query},intervalMs=>2000,maxDataPoints=>300}]});
        my $r=run_command([@curl,'-H','Content-Type: application/json','--data-binary','@-',"$url/api/ds/query"],$payload,30);
        my $json=eval {decode_json($r->{stdout})}; my $res=$json && $json->{results}{A};
        ok($r->{code}==0 && $res && !$res->{error} && ($res->{status}//200)<400 && @{$res->{frames}//[]},"benchmark panel: $panel->{title}");
    }
    require_cmd([@compose,'restart','unbound'],'restart resolver');
    require_cmd([@compose,'up','-d','--wait','--wait-timeout','90','unbound'],'wait after restart');
    my $third=collect();
    ok(defined poll(sub {my $v=latest_ns(); defined($v)&&$v eq $third ? $v : undef},60),'post-restart sample received');
    my $after=query($filter.' |> last() |> keep(columns: ["_value"])');
    ok(defined($after)&&$after<$before,'actual cumulative query counter reset');
    my $negative=query($filter.' |> derivative(unit: 1s, nonNegative: true, initialZero: false) |> filter(fn: (r) => r._value < 0.0) |> count() |> keep(columns: ["_value"])');
    ok(!defined($negative)||$negative==0,'no negative query-rate samples');
    require_cmd([@compose,'stop','unbound'],'stop resolver to exercise stale collection');
    my $old_snapshot=read_bytes($snapshot);
    my $failed=command([$^X,"$source/monitoring/collect-stats.pl",$snapshot],30);
    isnt($failed->{code},0,'collection fails when resolver is stopped');
    is(read_bytes($snapshot),$old_snapshot,'failed collection retains previous source snapshot');
    sleep 8;
    is(latest_ns(),$third,'stopped resolver does not generate fresh source timestamps');
    my $stale=query($filter.' |> last() |> map(fn: (r) => ({_value: float(v: int(v: now()) - int(v: r._time)) / 1000000000.0}))');
    ok(defined($stale)&&$stale>=8,'freshness age increases after resolver stop');
    if ($operations) {
        my $rule_state=sub {
            my $r=command([@curl,"$url/api/prometheus/grafana/api/v1/rules"],20);
            return undef if $r->{code};
            my $data=eval {decode_json($r->{stdout})};
            return undef unless ref($data) eq 'HASH';
            for my $group (@{$data->{data}{groups}//[]}) {
                for my $rule (@{$group->{rules}//[]}) {
                    next unless ($rule->{name}//'') eq 'Resolver lab source metrics stale';
                    # Reject datasource error disguised as a firing freshness alert.
                    return undef if ($rule->{health}//'') ne 'ok';
                    return $rule->{state};
                }
            }
            return undef;
        };
        my $provisioned_rule=poll(sub {my $r=command([@curl,"$url/api/v1/provisioning/alert-rules/resolver-lab-freshness"],20);$r->{code}?undef:$r->{stdout}},60);
        ok(defined($provisioned_rule),'freshness alert provisioned') or die "alert provisioning missing\n";
        # The resolver is stopped from the previous test. Wait for actual stale state.
        ok(defined poll(sub {($rule_state->()//'') eq 'firing'?1:undef},250),'stale source raises firing state without query error') or die "freshness alert did not fire\n";
        require_cmd([@compose,'up','-d','--wait','--wait-timeout','90','unbound'],'restart resolver for alert recovery');
        my $recovered=collect();
        ok(defined poll(sub {my $v=latest_ns();defined($v)&&$v eq $recovered?$v:undef},60),'recovery snapshot received');
        ok(defined poll(sub {my $state=$rule_state->()//''; $state =~ /\A(?:normal|inactive)\z/?1:undef},90),'alert recovers with a fresh source');
        my $du_before=require_cmd([@compose,'exec','-T','influxdb','du','-sk','/var/lib/influxdb2','/etc/influxdb2'],'storage size before retention test');
        my $bucket='retention-fixture';
        my $created=require_cmd([@compose,'exec','-T','influxdb','influx','bucket','create','--org','lab','--name',$bucket,'--retention','24h','--shard-group-duration','1h','--json'],'create isolated retention bucket');
        my $b=decode_json($created);
        $b=$b->[0] if ref($b) eq 'ARRAY' && @$b==1;
        ref($b) eq 'HASH' or die "invalid fixture bucket response\n";
        my $bid=$b->{id}//'';
        $bid =~ /\A[0-9a-f]{16}\z/ or die "invalid fixture bucket ID\n";
        my $now=int(time());
        my $lp="retention_fixture,age=old value=1i ".($now-21600)."\nretention_fixture,age=recent value=2i $now\n";
        my $w=run_command([@compose,'exec','-T','influxdb','influx','write','--org','lab','--bucket',$bucket,'--precision','s'],$lp,30);
        is($w->{code},0,'write old and recent points before retention change') or die "fixture write failed\n";
        my $retention_query=sub {
            my ($age)=@_;
            my $flux='from(bucket: "retention-fixture") |> range(start: -24h) |> filter(fn: (r) => r._measurement == "retention_fixture" and r.age == "'.$age.'") |> last() |> keep(columns: ["_value"])';
            my $r=command([@compose,'exec','-T','influxdb','influx','query','--org','lab','--raw',$flux],30);
            die "retention query failed\n" if $r->{code};
            my @rows=grep {/,[12]\s*\z/} split /\n/,$r->{stdout};
            return scalar @rows;
        };
        is($retention_query->('old'),1,'old point initially visible');
        is($retention_query->('recent'),1,'recent point initially visible');
        require_cmd([@compose,'exec','-T','influxdb','influx','bucket','update','--id',$bid,'--retention','2h','--shard-group-duration','1h'],'shorten only fixture bucket retention');
        ok(defined poll(sub { $retention_query->('old')==0 && $retention_query->('recent')==1 ? 1:undef },120),'expired shard no longer queryable; recent point retained');
        require_cmd([@compose,'exec','-T','influxdb','influx','bucket','delete','--id',$bid],'delete only retention fixture bucket');
        my $du_after=require_cmd([@compose,'exec','-T','influxdb','du','-sk','/var/lib/influxdb2','/etc/influxdb2'],'storage size after retention test');
        diag("Storage snapshots (KiB; not daily growth): before $du_before after $du_after");
    }
    diag('Snapshot line bytes (uncompressed): '.length(read_bytes($snapshot)).'; sample count: '.(count_points()//'unknown'));
    1;
};
my $error=$@;
if ($started) {
    my $r=eval {command([@compose,'down','--volumes','--remove-orphans'],180)};
    ok($r && $r->{code}==0,'remove only disposable lab containers, networks and volumes');
    if (!$r || $r->{code}) { diag("Lab cleanup failed; review project $project using $dir/compose.yaml"); $started=2; }
}
chdir $cwd or die "restore cwd: $!";
remove_tree($dir) unless $started==2;
fail("lab aborted: $error") unless $success;
done_testing;
