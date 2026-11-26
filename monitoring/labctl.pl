#!/usr/bin/env perl
# Local developer lab only. Never target a deployment Compose project.
use v5.26;
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use LocalDocker qw(require_local_docker);
use lib $RealBin;
use BenchmarkMetrics qw(report_lines);
use Cwd qw(abs_path);
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use Fcntl qw(:flock O_CREAT O_RDWR O_NOFOLLOW);
use JSON::PP qw(decode_json encode_json);
use Time::HiRes qw(sleep);

my $root = abs_path("$RealBin/..");
my $dir = "$root/.monitoring-lab";
my ($op,$report_path) = @ARGV;
(@ARGV == 1 && $op =~ /\A(?:start|open|traffic|status|logs|usage|retention|alerts|stop|clean)\z/ || @ARGV == 2 && $op eq 'benchmark-import')
    or die "usage: labctl.pl start|open|traffic|status|logs|usage|retention|alerts|stop|clean|benchmark-import REPORT\n";
$< != 0 or die "run as a non-root Docker operator\n";
require_local_docker();
my ($benchmark_lp,$benchmark_run);
if ($op eq 'benchmark-import') {
    defined($report_path) && !-l $report_path && -f $report_path && -s $report_path <= 5_000_000 or die "invalid report file\n";
    my $resolved=abs_path($report_path);
    $resolved =~ m{\A\Q$root\E/benchmark-results/(run-[A-Za-z0-9_]{8})/report\.json\z} or die "use a local benchmark-results report\n";
    $benchmark_run=$1;
    $benchmark_lp=report_lines(decode_json(read_file($resolved)),$benchmark_run);
}
umask 077;
sysopen(my $lock, "$dir.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0600) or die "open lab lock: $!\n";
if ($op !~ /\A(?:open|status|logs|usage|retention)\z/) {
    flock($lock, LOCK_EX | LOCK_NB) or die "lab busy; stop monitoring-traffic with Ctrl+C first\n";
}
sub read_file {
    my ($path) = @_;
    -f $path && !-l $path or die "invalid lab file: $path\n";
    open my $fh, '<', $path or die "open $path: $!\n";
    local $/;
    return <$fh>;
}
sub write_file {
    my ($path, $data, $mode) = @_;
    open my $fh, '>', $path or die "open $path: $!\n";
    print {$fh} $data or die "write $path: $!\n";
    close $fh or die "close $path: $!\n";
    chmod $mode, $path or die "chmod $path: $!\n";
}
sub random_hex {
    my ($n) = @_;
    open my $fh, '<:raw', '/dev/urandom' or die "random: $!\n";
    read($fh, my $bytes, $n) == $n or die "random bytes unavailable\n";
    return unpack('H*', $bytes);
}
sub run {
    system {$_[0]} @_;
    $? == 0 or die "lab command failed (exit status $?): $_[0] $_[1]\n";
}
if (!-e $dir && !-l $dir) {
    if ($op eq 'clean' || $op eq 'stop') { print "No monitoring lab.\n"; exit 0; }
    $op eq 'start' or die "run make monitoring-start first\n";
    mkdir $dir, 0700 or die "mkdir lab: $!\n";
    my ($gid) = split / /, $(;
    my $project = 'unbound-mon-' . random_hex(8);
    write_file("$dir/identity.json", encode_json({project=>$project, password=>random_hex(16), token=>random_hex(32), uid=>0+$<, gid=>0+$gid}), 0600);
    make_path(map { "$dir/$_" } qw(metrics dashboards provisioning/datasources provisioning/dashboards));
    chmod 0750, "$dir/metrics" or die $!;
    my @readable = map { "$dir/$_" } qw(dashboards provisioning provisioning/datasources provisioning/dashboards);
    chmod(0755, @readable) == @readable or die $!;
    for my $file (qw(compose.yaml telegraf.conf provisioning/datasources/influx.yaml provisioning/dashboards/resolver.yaml)) {
        copy("$RealBin/lab/$file", "$dir/$file") or die "copy $file: $!\n";
        chmod 0644, "$dir/$file" or die $!;
    }
    my $d = decode_json(read_file("$RealBin/grafana-snapshot-flux.json"));
    $d->{templating}{list}[0]{current} = {text=>'Resolver lab Flux', value=>'resolver-lab-flux'};
    $d->{templating}{list}[1]{query} = 'resolver-lab';
    $d->{templating}{list}[1]{current} = {text=>'resolver-lab', value=>'resolver-lab'};
    write_file("$dir/dashboards/resolver.json", encode_json($d), 0644);
}
-d $dir && !-l $dir && -o $dir && ((stat($dir))[2] & 0077) == 0 or die "unsafe lab directory\n";
my $identity = decode_json(read_file("$dir/identity.json"));
my ($project,$password,$token,$uid,$gid) = @{$identity}{qw(project password token uid gid)};
$project =~ /\Aunbound-mon-[0-9a-f]{16}\z/ && $password =~ /\A[0-9a-f]{32}\z/ && $token =~ /\A[0-9a-f]{64}\z/ && $uid == $< && $gid =~ /\A\d+\z/ or die "invalid lab identity\n";
local @ENV{qw(LAB_PASSWORD LAB_TOKEN LAB_UID LAB_GID COMPOSE_PROJECT_NAME COMPOSE_DISABLE_ENV_FILE COMPOSE_ENV_FILES COMPOSE_PROFILES)} = ($password,$token,$uid,$gid,$project,1,'','');
chdir $dir or die "chdir lab: $!\n";
my @compose = ('docker','compose','--env-file','/dev/null','-p',$project,'-f','compose.yaml');
sub compose { run(@compose, @_); }
sub collect { run($^X, "$RealBin/collect-stats.pl", "$dir/metrics/unbound.lp"); }
sub url {
    open my $fh, '-|', @compose, 'port','grafana','3000' or die "port lookup: $!\n";
    my $binding = <$fh> // '';
    close $fh or die "Grafana not running\n";
    $binding =~ /\A127\.0\.0\.1:(\d+)\s*\z/ or die "unexpected Grafana binding\n";
    return "http://127.0.0.1:$1/d/unbound-recursive-snapshot";
}
sub login { my $url = url(); print "Grafana: $url\nUser: lab\nPassword: $password\n"; return $url; }
if ($op eq 'start') {
    run('docker','image','inspect','unbound-recursive:dev','--format','{{.Id}}');
    compose('up','-d','--wait','--wait-timeout','180','unbound','influxdb','grafana');
    collect();
    compose('up','-d','telegraf');
    login();
    print "Run make monitoring-traffic in a separate terminal to refresh metrics.\n";
} elsif ($op eq 'open') {
    my $url = login();
    run('open',$url) if $^O eq 'darwin';
} elsif ($op eq 'traffic') {
    local $SIG{INT} = sub { exit 0 };
    local $SIG{TERM} = sub { exit 0 };
    print "Collecting synthetic local queries; Ctrl+C to stop.\n";
    while (1) {
        compose('exec','-T','unbound','sh','-c','i=0; while [ "$i" -lt 10 ]; do /usr/local/bin/healthcheck.sh || exit 1; i=$((i+1)); done');
        collect();
        sleep 5;
    }
 } elsif ($op eq 'benchmark-import') {
    # Only the generated numeric line protocol reaches the disposable lab.
    open my $fh,'|-',@compose,'exec','-T','influxdb','influx','write','--host','http://localhost:8086','--org','lab','--bucket','resolver-lab','--precision','s' or die "open InfluxDB import: $!\n";
    print {$fh} $benchmark_lp or die "write benchmark metrics: $!\n";
    close $fh or die "InfluxDB import failed\n";
    -d "$dir/dashboards" && !-l "$dir/dashboards" && !-l "$dir/dashboards/benchmark.json" or die "unsafe dashboard path\n";
    write_file("$dir/dashboards/benchmark.json",read_file("$RealBin/grafana-benchmark-flux.json"),0644);
    my $url=url(); $url =~ s{/d/unbound-recursive-snapshot\z}{/d/unbound-recursive-benchmark};
    print "Imported $benchmark_run. Grafana: $url (select benchmark time range; provisioning polls for changes).\n";
    run('open',$url) if $^O eq 'darwin';
 } elsif ($op eq 'alerts') {
    my $target="$dir/provisioning/alerting";
    -d "$dir/provisioning" && !-l "$dir/provisioning" && !-l $target or die "unsafe alert provisioning directory\n";
    make_path($target,{mode=>0755});
    chmod 0755,$target or die "alert directory mode: $!\n";
    !-l "$target/freshness.json" or die "unsafe alert file\n";
    write_file("$target/freshness.json",read_file("$RealBin/lab/provisioning/alerts-freshness.json"),0644);
    compose('restart','grafana');
    print "Lab freshness alert installed; verify Alerting > Alert rules and configure a test contact point manually.\n";
} elsif ($op eq 'status') { compose('ps'); }
elsif ($op eq 'logs') { compose('logs','--tail=50'); }
elsif ($op eq 'usage') { compose('exec','-T','influxdb','du','-sk','/var/lib/influxdb2','/etc/influxdb2'); }
elsif ($op eq 'retention') { compose('exec','-T','influxdb','influx','bucket','list','--org','lab','--name','resolver-lab'); }
elsif ($op eq 'stop') { compose('stop'); }
elsif ($op eq 'clean') {
    compose('down','--volumes','--remove-orphans');
    chdir $root or die $!;
    remove_tree($dir, {safe=>1, error=>\my $errors});
    @$errors == 0 && !-e $dir or die "lab directory cleanup incomplete\n";
}
