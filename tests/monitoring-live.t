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
plan skip_all => 'opt in with make test-monitoring' unless ($ENV{RUN_MONITORING_LIVE}//'') eq '1';
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
